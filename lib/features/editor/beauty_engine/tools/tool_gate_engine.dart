import 'dart:ui';

import '../models/face_mesh_result.dart';
import '../quality/face_quality_context.dart';
import 'beauty_tool_registry.dart';
import 'tool_descriptor.dart';
import 'tool_gate_decision.dart';

/// Avalia predicados de gating (cap. 19) sobre o Quality Score.
class ToolGateEngine {
  const ToolGateEngine();

  ToolGatePlan evaluate(FaceQualityContext context) {
    final decisions = <String, ToolGateDecision>{};
    for (final tool in BeautyToolRegistry.all) {
      decisions[tool.key] = _evaluateTool(tool.key, context);
    }
    return ToolGatePlan(decisions: decisions);
  }

  ToolGateDecision _evaluateTool(String key, FaceQualityContext ctx) {
    final m = ctx.metrics;

    if (!m.hasFace && _requiresFace(key)) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_no_face',
      );
    }

    switch (key) {
      case 'skin_smooth':
        return _skinSmooth(key, ctx);
      case 'remove_acne':
        return _acne(key, ctx);
      case 'remove_dark_circles':
        return _darkCircles(key, ctx);
      case 'skin_shine':
        return _skinShine(key, ctx);
      case 'teeth_whitening':
        return _teeth(key, ctx);
      case 'iris_enhance':
        return _irisEnhance(key, ctx);
      case 'face_slim':
      case 'narrow_face':
      case 'v_face':
      case 'jaw':
        return _faceWarp(key, ctx, yawThreshold: 0.2, minFacePx: 200);
      case 'eye_scale':
      case 'eye_distance':
      case 'eye_height':
      case 'eye_rotation':
      case 'double_eyelid':
        return _eyes(key, ctx);
      case 'nose_slim':
      case 'nose_tip':
        return _faceWarp(key, ctx, yawThreshold: 0.2, minFacePx: 180);
      case 'lip_thickness':
        return _faceWarp(key, ctx, yawThreshold: 0.25, minFacePx: 160);
      default:
        if (_isSkinKey(key) && !m.hasSkinSegmentation && m.yawAsymmetry > 0.35) {
          return ToolGateDecision(
            parameterKey: key,
            action: ToolGateAction.disabled,
            hintKey: 'gate_skin_unavailable',
          );
        }
        if (_isWarpKey(key)) {
          return _faceWarp(key, ctx, yawThreshold: 0.28, minFacePx: 180);
        }
        return ToolGateDecision(parameterKey: key);
    }
  }

  ToolGateDecision _skinSmooth(String key, FaceQualityContext ctx) {
    final m = ctx.metrics;
    final s = ctx.score;
    var scale = 1.0;
    var maxEff = 1.0;
    String? hint;

    if (s.sharpness < 0.45) {
      scale *= 0.55;
      maxEff = _min(maxEff, 0.5);
      hint = 'gate_blur_high';
    }
    if (m.noiseLevel > 0.35) {
      scale *= 0.65;
      maxEff = _min(maxEff, 0.55);
      hint ??= 'gate_noise_high';
    }
    if (m.faceShortEdgePx > 0 && m.faceShortEdgePx < 200) {
      scale *= m.faceShortEdgePx / 200;
      maxEff = _min(maxEff, 0.45);
      hint ??= 'gate_face_small';
    }
    if (!m.hasSkinSegmentation && m.yawAsymmetry > 0.35) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_skin_unavailable',
      );
    }
    if (m.occlusionRatio > 0.25) {
      hint ??= 'gate_partial_occlusion';
    }

    if (scale >= 0.99 && maxEff >= 0.99) {
      return ToolGateDecision(
        parameterKey: key,
        hintKey: hint,
        action: hint != null ? ToolGateAction.warn : ToolGateAction.allowed,
      );
    }
    return ToolGateDecision(
      parameterKey: key,
      action: ToolGateAction.reduced,
      intensityScale: scale,
      maxEffective: maxEff,
      hintKey: hint,
    );
  }

  ToolGateDecision _acne(String key, FaceQualityContext ctx) {
    final m = ctx.metrics;
    if (m.faceShortEdgePx > 0 && m.faceShortEdgePx < 150) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_face_too_small_acne',
      );
    }
    if (m.compressionScore > 0.45) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.reduced,
        intensityScale: 0.6,
        maxEffective: 0.5,
        hintKey: 'gate_compression_high',
      );
    }
    if (m.noiseLevel > 0.4) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.reduced,
        intensityScale: 0.7,
        maxEffective: 0.55,
        hintKey: 'gate_noise_high',
      );
    }
    return ToolGateDecision(parameterKey: key);
  }

  ToolGateDecision _darkCircles(String key, FaceQualityContext ctx) {
    final m = ctx.metrics;
    if (m.yawAsymmetry > 0.25) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.reduced,
        intensityScale: 0.65,
        hintKey: 'gate_hard_shadow',
      );
    }
    if (m.shadowClipRatio > 0.25) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.reduced,
        intensityScale: 0.7,
        hintKey: 'gate_low_light',
      );
    }
    return ToolGateDecision(parameterKey: key);
  }

  ToolGateDecision _skinShine(String key, FaceQualityContext ctx) {
    final m = ctx.metrics;
    if (!m.hasSkinSegmentation) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_skin_unavailable',
      );
    }
    if (m.highlightClipRatio > 0.2) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.warn,
        intensityScale: 0.75,
        hintKey: 'gate_exposure_blown',
      );
    }
    return ToolGateDecision(parameterKey: key);
  }

  ToolGateDecision _teeth(String key, FaceQualityContext ctx) {
    if (ctx.metrics.occlusionRatio > 0.35) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_mouth_occluded',
      );
    }
    final openness = _mouthOpenness(ctx.face);
    if (openness != null && openness < 0.012) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_mouth_closed',
      );
    }
    return ToolGateDecision(parameterKey: key);
  }

  ToolGateDecision _irisEnhance(String key, FaceQualityContext ctx) {
    if (ctx.metrics.occlusionRatio > 0.3) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_eyes_occluded',
      );
    }
    if (ctx.metrics.yawAsymmetry > 0.28) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.reduced,
        intensityScale: 0.65,
        hintKey: 'gate_yaw_high',
      );
    }
    return ToolGateDecision(parameterKey: key);
  }

  /// Distância vertical normalizada entre lábio superior e inferior.
  double? _mouthOpenness(FaceMeshResult? face) {
    if (face == null) return null;
    Offset? upper;
    Offset? lower;
    for (final lm in face.landmarks) {
      if (lm.index == 13) upper = lm.normalized;
      if (lm.index == 14) lower = lm.normalized;
    }
    if (upper == null || lower == null) return null;
    return (lower.dy - upper.dy).abs();
  }

  ToolGateDecision _eyes(String key, FaceQualityContext ctx) {
    final m = ctx.metrics;
    if (m.occlusionRatio > 0.3) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.disabled,
        hintKey: 'gate_eyes_occluded',
      );
    }
    var scale = 1.0;
    if (m.yawAsymmetry > 0.2) {
      scale *= (1 - m.yawAsymmetry).clamp(0.4, 1.0);
    }
    if (scale < 0.95) {
      return ToolGateDecision(
        parameterKey: key,
        action: ToolGateAction.reduced,
        intensityScale: scale,
        hintKey: 'gate_yaw_high',
      );
    }
    return ToolGateDecision(parameterKey: key);
  }

  ToolGateDecision _faceWarp(
    String key,
    FaceQualityContext ctx, {
    required double yawThreshold,
    required double minFacePx,
  }) {
    final m = ctx.metrics;
    var scale = 1.0;

    if (m.faceShortEdgePx > 0 && m.faceShortEdgePx < minFacePx) {
      scale *= (m.faceShortEdgePx / minFacePx).clamp(0.55, 1.0);
    }
    if (m.yawAsymmetry > yawThreshold) {
      scale *= (1 - (m.yawAsymmetry - yawThreshold) * 2).clamp(0.5, 1.0);
    } else if (ctx.score.pose < 0.98) {
      scale *= ctx.score.pose.clamp(0.85, 1.0);
    }

    if (scale >= 0.98) {
      return ToolGateDecision(parameterKey: key);
    }

    final String? hintKey;
    if (m.faceShortEdgePx > 0 && m.faceShortEdgePx < minFacePx) {
      hintKey = 'gate_face_small';
    } else if (m.yawAsymmetry > yawThreshold) {
      hintKey = 'gate_yaw_high';
    } else {
      hintKey = 'gate_pose_limited';
    }

    return ToolGateDecision(
      parameterKey: key,
      action: ToolGateAction.reduced,
      intensityScale: scale.clamp(0.55, 1.0),
      hintKey: hintKey,
    );
  }

  bool _requiresFace(String key) {
    return BeautyToolRegistry.byKey[key]?.requiresFace ?? false;
  }

  bool _isSkinKey(String key) =>
      BeautyToolRegistry.byKey[key]?.category == ToolCategory.skin;

  bool _isWarpKey(String key) =>
      BeautyToolRegistry.byKey[key]?.pipelineStage == ToolPipelineStage.warp;

  double _min(double a, double b) => a < b ? a : b;
}
