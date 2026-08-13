import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../body_reshape/maps/influence_map.dart';
import '../body_reshape/protection/rigidity_map.dart';
import '../debug/agent_debug_log.dart';
import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../body_reshape/rendering/render_plan.dart';
import '../config/face_warp_v3_config.dart';
import '../models/warp_field.dart';
import '../warp/face_mesh_gpu_payload.dart';
import '../warp/face_mesh_forward_warp.dart';
import '../warp/face_slim_warp.dart';
import '../warp/face_warp_render_contract.dart';
import '../warp/face_warp_renderer.dart';
import '../warp/anatomy/vertex_role_map.dart';
import '../segment/person_mask.dart';
import '../warp/anatomy/face_warp_vacancy_fill.dart';
import '../warp/face_warp_ghost_mask.dart';
import '../warp/face_warp_post_inpaint.dart';
import '../warp/fragment_program_face_inpaint_backend.dart';
import '../warp/fragment_program_face_mesh_backend.dart';
import '../warp/warp_cpu_remap.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Decisão de roteamento face_slim V3 vs legacy (Fase 1 — testável).
@immutable
class FaceSlimV3Routing {
  const FaceSlimV3Routing({
    required this.v3PayloadActive,
    required this.blockLegacyFaceSlim,
  });

  static const meshBackwardPassId = 'mesh-backward-preview';

  final bool v3PayloadActive;
  final bool blockLegacyFaceSlim;

  @visibleForTesting
  static FaceSlimV3Routing resolve({
    required bool faceSlimOnly,
    required bool mvpMeshPath,
    required FaceMeshForwardPayload? forwardPayload,
    required bool blockLegacyFlag,
    required bool useForwardMeshWarp,
  }) {
    final v3Active = (faceSlimOnly || mvpMeshPath) &&
        useForwardMeshWarp &&
        forwardPayload != null &&
        !forwardPayload.isIdentity;
    return FaceSlimV3Routing(
      v3PayloadActive: v3Active,
      blockLegacyFaceSlim: blockLegacyFlag || v3Active,
    );
  }
}

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

  /// Diagnóstico temporário Fase 2 — compara source vs output final sem alterar
  /// [warpChangedPixels] nem o retorno booleano.
  @visibleForTesting
  static Map<String, dynamic> diagnoseV3MeshPixelChange({
    required Uint8List source,
    required Uint8List output,
    required int width,
    required int height,
    int minAccumDiff = 8000,
    int sampleStride = 64,
  }) {
    if (source.length != output.length || source.isEmpty) {
      return {
        'changed': false,
        'accumulatedDiff': 0,
        'sampledPixels': 0,
        'maxPixelDiff': 0,
        'changedSampleCount': 0,
        'totalChangedRgbSamples': 0,
        'totalAbsoluteRgbDiff': 0,
        'changedPixelsGt0': 0,
        'changedPixelsGte2': 0,
        'changedPixelsGte5': 0,
        'changedBBoxMinX': null,
        'changedBBoxMinY': null,
        'changedBBoxMaxX': null,
        'changedBBoxMaxY': null,
        'sourceLength': source.length,
        'outputLength': output.length,
        'minAccumDiff': minAccumDiff,
        'sampleStride': sampleStride,
        'falseNegativeSuspected': false,
      };
    }

    final changed = warpChangedPixels(
      source,
      output,
      minAccumDiff: minAccumDiff,
      sampleStride: sampleStride,
    );

    var accumulatedDiff = 0;
    var sampledPixels = 0;
    var maxPixelDiff = 0;
    var changedSampleCount = 0;

    for (var i = 0; i < source.length; i += 4 * sampleStride) {
      sampledPixels++;
      final dr = (source[i] - output[i]).abs();
      final dg = (source[i + 1] - output[i + 1]).abs();
      final db = (source[i + 2] - output[i + 2]).abs();
      final pixelMax = math.max(dr, math.max(dg, db));
      final pixelSum = dr + dg + db;
      if (pixelMax > 0) {
        changedSampleCount++;
      }
      if (pixelMax > maxPixelDiff) {
        maxPixelDiff = pixelMax;
      }
      accumulatedDiff += pixelSum;
    }

    var totalChangedRgbSamples = 0;
    var totalAbsoluteRgbDiff = 0;
    var changedPixelsGt0 = 0;
    var changedPixelsGte2 = 0;
    var changedPixelsGte5 = 0;
    int? bboxMinX;
    int? bboxMinY;
    int? bboxMaxX;
    int? bboxMaxY;

    final pixelCount = source.length ~/ 4;
    for (var p = 0; p < pixelCount; p++) {
      final o = p * 4;
      final dr = (source[o] - output[o]).abs();
      final dg = (source[o + 1] - output[o + 1]).abs();
      final db = (source[o + 2] - output[o + 2]).abs();
      final pixelMax = math.max(dr, math.max(dg, db));
      final pixelSum = dr + dg + db;
      totalAbsoluteRgbDiff += pixelSum;
      if (pixelMax <= 0) {
        continue;
      }

      totalChangedRgbSamples++;
      changedPixelsGt0++;
      if (pixelMax >= 2) {
        changedPixelsGte2++;
      }
      if (pixelMax >= 5) {
        changedPixelsGte5++;
      }

      final x = p % width;
      final y = p ~/ width;
      bboxMinX = bboxMinX == null ? x : math.min(bboxMinX, x);
      bboxMinY = bboxMinY == null ? y : math.min(bboxMinY, y);
      bboxMaxX = bboxMaxX == null ? x : math.max(bboxMaxX, x);
      bboxMaxY = bboxMaxY == null ? y : math.max(bboxMaxY, y);
    }

    return {
      'changed': changed,
      'accumulatedDiff': accumulatedDiff,
      'sampledPixels': sampledPixels,
      'maxPixelDiff': maxPixelDiff,
      'changedSampleCount': changedSampleCount,
      'totalChangedRgbSamples': totalChangedRgbSamples,
      'totalAbsoluteRgbDiff': totalAbsoluteRgbDiff,
      'changedPixelsGt0': changedPixelsGt0,
      'changedPixelsGte2': changedPixelsGte2,
      'changedPixelsGte5': changedPixelsGte5,
      'changedBBoxMinX': bboxMinX,
      'changedBBoxMinY': bboxMinY,
      'changedBBoxMaxX': bboxMaxX,
      'changedBBoxMaxY': bboxMaxY,
      'sourceLength': source.length,
      'outputLength': output.length,
      'minAccumDiff': minAccumDiff,
      'sampleStride': sampleStride,
      'falseNegativeSuspected': !changed && changedPixelsGt0 > 0,
    };
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
    final postInpaintFlag = context.uniforms['postWarpInpaint'];
    final postInpaint = switch (postInpaintFlag) {
      true => true,
      false => false,
      _ => !interactivePreview && FaceWarpV3Config.usePostWarpInpaint,
    };

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
    final personMask = context.uniforms['personMask'] as PersonMask?;
    final protection = context.uniforms['protectionMap'] as RigidityMap? ??
        field?.rigidityMap;
    final forceCpu = context.uniforms['forceCpu'] == true || !_preferGpu;
    final fastMode = context.uniforms['fastMode'] == true;
    final antiGhosting = context.uniforms['antiGhosting'] != false;

    Uint8List? warpedRgba;
    final faceSlimOnly = FaceWarpVacancyFill.isFaceSlimOnly(warpParameters);
    final mvpMeshPath = FaceWarpVacancyFill.usesMvpMeshPath(warpParameters);
    final forwardPayload =
        context.uniforms['faceMeshForward'] as FaceMeshForwardPayload?;
    final routing = FaceSlimV3Routing.resolve(
      faceSlimOnly: faceSlimOnly,
      mvpMeshPath: mvpMeshPath,
      forwardPayload: forwardPayload,
      blockLegacyFlag:
          context.uniforms['blockLegacyFaceSlimFallback'] == true,
      useForwardMeshWarp: FaceWarpV3Config.useForwardMeshWarpFaceSlim,
    );

    if (routing.v3PayloadActive) {
      final payload = forwardPayload!;
      warpedRgba = FaceMeshForwardWarp.apply(
        rgba: source.rgba,
        width: source.width,
        height: source.height,
        payload: payload,
        runId: FaceSlimV3Routing.meshBackwardPassId,
      );
      final meshVerts = payload.mesh.vertices.length ~/ 2;
      final supportWeights = GeometricSupport.computeWeights(
        mesh: payload.mesh,
        coreField: payload.vertexField,
        influenceMap: payload.influenceMap,
        params: const DeformationSupportParams(),
        imageWidth: source.width,
        imageHeight: source.height,
        personMask: payload.personMask,
      );
      final fieldMetrics = FaceWarpFieldMetrics.computeFieldMetrics(
        coreField: payload.vertexField,
        mesh: payload.mesh,
        supportWeights: supportWeights,
        rigidIndices: VertexRoleMap.eyeLeft,
      );
      final changed = warpChangedPixels(source.rgba, warpedRgba);
      final renderMetrics = FaceWarpRenderer.renderFromPayload(
        rgba: source.rgba,
        width: source.width,
        height: source.height,
        payload: payload,
        runId: '${FaceSlimV3Routing.meshBackwardPassId}-diag',
      );
      final meshHitPx =
          renderMetrics.coverage?.where((v) => v > 0.5).length ?? 0;
      final pixelDiagnostics = diagnoseV3MeshPixelChange(
        source: source.rgba,
        output: warpedRgba,
        width: source.width,
        height: source.height,
      );
      // #region agent log
      AgentDebugLog.writePhase2Metrics(
        location: 'pass_warp.dart:mesh_backward',
        runId: FaceSlimV3Routing.meshBackwardPassId,
        metrics: fieldMetrics,
        landmarkCount: payload.vertexField.landmarkCount,
        meshVertexCount: meshVerts,
      );
      AgentDebugLog.write(
        location: 'pass_warp.dart:mesh_backward',
        message: 'v3_mesh_pixel_change_diagnostic',
        hypothesisId: 'P2D',
        runId: FaceSlimV3Routing.meshBackwardPassId,
        phase: '2',
        data: {
          'faceSlimIntensity': warpParameters['face_slim'],
          'peakDisplacement': payload.vertexField.maxDisplacementMagnitude(),
          'requestedDisplacement': fieldMetrics.requestedDisplacement,
          'effectiveDisplacement': fieldMetrics.effectiveDisplacement,
          'destinationCoverage': renderMetrics.metrics.destinationCoverage,
          'uncoveredRatio': renderMetrics.metrics.uncoveredRatio,
          'meshHitPx': meshHitPx,
          ...pixelDiagnostics,
        },
      );
      AgentDebugLog.writePhase1Routing(
        location: 'pass_warp.dart:mesh_backward',
        passId: FaceSlimV3Routing.meshBackwardPassId,
        backend: 'v3_mesh',
        fallbackUsed: false,
        landmarkCount: payload.vertexField.landmarkCount,
        meshVertexCount: meshVerts,
        error: changed ? null : 'v3_mesh_no_pixel_change',
      );
      AgentDebugLog.write(
        location: 'pass_warp.dart:mesh_backward',
        message: 'face_slim_mesh_backward_path',
        hypothesisId: 'B0',
        runId: FaceSlimV3Routing.meshBackwardPassId,
        phase: '1',
        data: {
          'peakDisp': payload.vertexField.maxDisplacementMagnitude(),
          'backend': 'v3_mesh',
          'fallbackUsed': false,
        },
      );
      // #endregion
    }

    final allowGpuFaceSlimPreview = false;
    final skipGpuFaceSlimLegacy =
        faceSlimOnly && routing.blockLegacyFaceSlim;

    if (warpedRgba == null &&
        !forceCpu &&
        !skipGpuFaceSlimLegacy &&
        gpuPayload != null &&
        !gpuPayload.isIdentity &&
        (!interactivePreview || allowGpuFaceSlimPreview)) {
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
        if (faceSlimOnly && field != null && influence != null) {
          warpedRgba = FaceSlimWarp.postProcess(
            original: source.rgba,
            warped: warpedRgba,
            width: source.width,
            height: source.height,
            field: field,
            influence: influence,
            parameters: warpParameters,
            personMask: personMask,
            backend: 'gpu',
            runId: 'face-slim-gpu',
          );
        }
        // #region agent log
        AgentDebugLog.write(
          location: 'pass_warp.dart:gpu_face_slim',
          message: 'face_slim_gpu_path',
          hypothesisId: 'G1',
          runId: 'face-slim-gpu',
          data: {'peakDisp': field?.maxDisplacementMagnitude ?? 0},
        );
        // #endregion
      }
    }

    if (!forceCpu &&
        !interactivePreview &&
        warpedRgba == null &&
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
      if (faceSlimOnly && influence != null && !influence.isEmpty) {
        if (routing.blockLegacyFaceSlim) {
          // #region agent log
          final meshVerts = forwardPayload != null
              ? forwardPayload.mesh.vertices.length ~/ 2
              : null;
          AgentDebugLog.writePhase1Routing(
            location: 'pass_warp.dart:face_slim_cpu',
            passId: FaceSlimV3Routing.meshBackwardPassId,
            backend: routing.v3PayloadActive ? 'v3_mesh' : 'v3_blocked',
            fallbackUsed: false,
            fallbackReason: routing.v3PayloadActive
                ? 'legacy_blocked_v3_payload_active'
                : 'legacy_blocked_by_flag',
            landmarkCount: forwardPayload?.vertexField.landmarkCount,
            meshVertexCount: meshVerts,
            error: routing.v3PayloadActive
                ? 'v3_payload_legacy_fallback_suppressed'
                : null,
          );
          // #endregion
        } else {
          warpedRgba = FaceSlimWarp.apply(
            rgba: source.rgba,
            width: source.width,
            height: source.height,
            field: field,
            influence: influence,
            parameters: warpParameters,
            personMask: personMask,
            runId: 'face-slim-cpu',
          );
          // #region agent log
          AgentDebugLog.writePhase1Routing(
            location: 'pass_warp.dart:face_slim_cpu',
            passId: 'face-slim-cpu',
            backend: 'legacy_face_slim_cpu',
            fallbackUsed: true,
            fallbackReason: 'no_v3_payload_authorized',
          );
          AgentDebugLog.write(
            location: 'pass_warp.dart:face_slim_cpu',
            message: 'face_slim_cpu_fallback_path',
            hypothesisId: 'G2',
            runId: 'face-slim-cpu',
            phase: '1',
            data: {
              'peakDisp': field.maxDisplacementMagnitude,
              'gridW': field.gridWidth,
              'gridH': field.gridHeight,
              'backend': 'legacy_face_slim_cpu',
              'fallbackUsed': true,
              'fallbackReason': 'no_v3_payload_authorized',
            },
          );
          // #endregion
        }
      } else {
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
    }

    if (warpedRgba == null) {
      return context.pool.acquireCopy(context.input);
    }

    if (postInpaint && field != null && !field.isIdentity) {
      final faceSlimPipeline = faceSlimOnly &&
          (FaceWarpV3Config.useForwardMeshWarpFaceSlim &&
                  forwardPayload != null ||
              (influence != null && !influence.isEmpty));
      if (!faceSlimPipeline) {
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
    if (FaceWarpVacancyFill.isFaceSlimOnly(warpParameters)) {
      return FaceWarpPostInpaint.apply(
        rgba: warpedRgba,
        width: width,
        height: height,
        field: field,
        influenceMap: influence,
        parameters: warpParameters,
        iterations: 2,
      );
    }

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
