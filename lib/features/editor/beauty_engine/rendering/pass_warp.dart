import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../body_reshape/maps/influence_map.dart';
import '../body_reshape/protection/rigidity_map.dart';
import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../body_reshape/rendering/render_plan.dart';
import '../models/warp_field.dart';
import '../warp/warp_cpu_remap.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 1: remap de [WarpField] do Body Reshape.
///
/// Preferência: GPU ([FragmentProgramWarpBackend]).
/// Fallback: [WarpCpuRemap] com anti-ghosting + rigidity.
class PassWarp implements RenderPass {
  const PassWarp({
    WarpCpuRemap? remapper,
    FragmentProgramWarpBackend? warpBackend,
    bool preferGpu = true,
  })  : _remapper = remapper,
        _warpBackend = warpBackend,
        _preferGpu = preferGpu;

  final WarpCpuRemap? _remapper;
  final FragmentProgramWarpBackend? _warpBackend;
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
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }
    if (field == null || field.isIdentity) {
      return context.pool.acquireCopy(context.input);
    }

    final influence = context.uniforms['influenceMap'] as InfluenceMap?;
    final protection = context.uniforms['protectionMap'] as RigidityMap? ??
        field.rigidityMap;
    final forceCpu = context.uniforms['forceCpu'] == true || !_preferGpu;
    final fastMode = context.uniforms['fastMode'] == true;
    final antiGhosting = context.uniforms['antiGhosting'] != false;
    final interactivePreview =
        context.uniforms['interactivePreview'] == true;

    Uint8List? warpedRgba;

    if (!forceCpu && !interactivePreview) {
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

    if (warpedRgba == null) {
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

    final entry = context.store.create(
      rgba: warpedRgba,
      width: source.width,
      height: source.height,
    );
    return context.store.toHandle(entry);
  }
}
