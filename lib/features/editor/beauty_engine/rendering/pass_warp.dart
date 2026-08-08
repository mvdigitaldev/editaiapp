import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../body_reshape/maps/influence_map.dart';
import '../body_reshape/protection/rigidity_map.dart';
import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../body_reshape/rendering/render_plan.dart';
import '../config/face_warp_v3_config.dart';
import '../models/warp_field.dart';
import '../warp/face_mesh_gpu_payload.dart';
import '../warp/face_warp_ghost_mask.dart';
import '../warp/face_warp_post_inpaint.dart';
import '../warp/fragment_program_face_inpaint_backend.dart';
import '../warp/fragment_program_face_mesh_backend.dart';
import '../warp/warp_cpu_remap.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 1: warp remap (MLS / Body Reshape field / Face mesh GPU).
///
/// Preferência: GPU ([FragmentProgramWarpBackend] ou [FragmentProgramFaceMeshBackend]).
/// Fallback: [WarpCpuRemap] com anti-ghosting + rigidity (Sprint 11).
///
/// Preview interativo usa grade CPU (confiável); GPU piecewise fica reservado
/// para export. Se o shader GPU retornar imagem idêntica à origem, faz fallback.
class PassWarp implements RenderPass {
  const PassWarp({
    WarpCpuRemap? remapper,
    FragmentProgramWarpBackend? warpBackend,
    FragmentProgramFaceMeshBackend? faceMeshBackend,
    FragmentProgramFaceInpaintBackend? inpaintBackend,
    bool preferGpu = true,
  })  : _remapper = remapper,
        _warpBackend = warpBackend,
        _faceMeshBackend = faceMeshBackend,
        _inpaintBackend = inpaintBackend,
        _preferGpu = preferGpu;

  final WarpCpuRemap? _remapper;
  final FragmentProgramWarpBackend? _warpBackend;
  final FragmentProgramFaceMeshBackend? _faceMeshBackend;
  final FragmentProgramFaceInpaintBackend? _inpaintBackend;
  final bool _preferGpu;

  /// Amostragem leve — detecta shader GPU que retorna identidade silenciosa.
  @visibleForTesting
  static bool warpChangedPixels(
    Uint8List source,
    Uint8List output, {
    int minAccumDiff = 8000,
    int sampleStride = 64,
  }) {
    if (source.length != output.length || source.isEmpty) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < source.length; i += 4 * sampleStride) {
      diff += (source[i] - output[i]).abs();
      diff += (source[i + 1] - output[i + 1]).abs();
      diff += (source[i + 2] - output[i + 2]).abs();
      if (diff >= minAccumDiff) {
        return true;
      }
    }
    return diff >= minAccumDiff;
  }

  @override
  String get shaderName => RenderShaders.warpRemap;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final field = context.uniforms['warpField'] as WarpField?;
    final gpuPayload =
        context.uniforms['faceMeshGpuPayload'] as FaceMeshGpuPayload?;
    final warpParameters = context.uniforms['warpParameters']
            as Map<String, double>? ??
        const {};
    final interactivePreview =
        context.uniforms['interactivePreview'] == true;
    final postInpaint = context.uniforms['postWarpInpaint'] == true ||
        FaceWarpV3Config.usePostWarpInpaint;

    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    if ((field == null || field.isIdentity) &&
        (gpuPayload == null || gpuPayload.isIdentity)) {
      return context.pool.acquireCopy(context.input);
    }

    final influence = context.uniforms['influenceMap'] as InfluenceMap? ??
        gpuPayload?.influenceMap;
    final protection = context.uniforms['protectionMap'] as RigidityMap? ??
        field?.rigidityMap;
    final forceCpu = context.uniforms['forceCpu'] == true || !_preferGpu;
    final fastMode = context.uniforms['fastMode'] == true;
    final antiGhosting = context.uniforms['antiGhosting'] != false;

    Uint8List? warpedRgba;

    if (!forceCpu &&
        !interactivePreview &&
        gpuPayload != null &&
        !gpuPayload.isIdentity) {
      final meshBackend =
          _faceMeshBackend ?? FragmentProgramFaceMeshBackend.shared;
      final gpuOut = await meshBackend.apply(
        rgba: source.rgba,
        width: source.width,
        height: source.height,
        payload: gpuPayload,
        protectionMap: protection,
      );
      if (gpuOut != null &&
          warpChangedPixels(source.rgba, gpuOut, minAccumDiff: 4000)) {
        warpedRgba = gpuOut;
      }
    }

    if (warpedRgba == null &&
        !forceCpu &&
        !interactivePreview &&
        field != null &&
        !field.isIdentity) {
      final backend = _warpBackend ?? FragmentProgramWarpBackend.shared;
      final planUniform = context.uniforms['renderPlan'] as RenderPlan?;
      final gridOut = planUniform != null
          ? await backend.applyPlan(
              rgba: source.rgba,
              width: source.width,
              height: source.height,
              plan: planUniform,
            )
          : await backend.apply(
              rgba: source.rgba,
              width: source.width,
              height: source.height,
              field: field,
              influenceMap: influence,
              protectionMap: protection,
            );
      if (gridOut != null &&
          warpChangedPixels(source.rgba, gridOut, minAccumDiff: 4000)) {
        warpedRgba = gridOut;
      }
    }

    if (warpedRgba == null && field != null && !field.isIdentity) {
      final remapper =
          (_remapper ?? WarpCpuRemap(fastMode: fastMode)).copyWith(
        antiGhosting: antiGhosting,
        rigidityMap: protection,
        fastMode: fastMode,
      );
      warpedRgba = remapper.apply(
        rgba: source.rgba,
        width: source.width,
        height: source.height,
        field: field,
      );
    }

    if (warpedRgba == null) {
      return context.pool.acquireCopy(context.input);
    }

    if (postInpaint && field != null && !field.isIdentity) {
      warpedRgba = await _applyPostInpaint(
        warpedRgba: warpedRgba,
        width: source.width,
        height: source.height,
        field: field,
        influence: influence,
        warpParameters: warpParameters,
        forceCpu: forceCpu,
      );
    }

    final entry = context.store.create(
      rgba: warpedRgba,
      width: source.width,
      height: source.height,
    );
    return context.store.toHandle(entry);
  }

  Future<Uint8List> _applyPostInpaint({
    required Uint8List warpedRgba,
    required int width,
    required int height,
    required WarpField field,
    InfluenceMap? influence,
    required Map<String, double> warpParameters,
    required bool forceCpu,
  }) async {
    final useGpu = FaceWarpV3Config.useGpuInpaint && !forceCpu;
    if (useGpu) {
      final inpaint = _inpaintBackend ?? FragmentProgramFaceInpaintBackend.shared;
      final ghost = FaceWarpGhostMask.buildRgba(
        field: field,
        influenceMap: influence,
        parameters: warpParameters,
      );
      if (ghost != null) {
        await inpaint.initialize();
        if (inpaint.isAvailable) {
          final gpu = await inpaint.apply(
            rgba: warpedRgba,
            ghostMask: ghost,
            width: width,
            height: height,
          );
          if (gpu != null) {
            return gpu;
          }
        }
      }
    }

    return FaceWarpPostInpaint.apply(
      rgba: warpedRgba,
      width: width,
      height: height,
      field: field,
      influenceMap: influence,
      parameters: warpParameters,
    );
  }
}
