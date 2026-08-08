import '../models/beauty_preset.dart';
import '../quality/face_quality_context.dart';
import '../tools/tool_gate_engine.dart';
import '../tools/tool_gate_engine.dart';

/// Presets adaptativos (cap. 8) — modula valores base pelo Quality Score.
class AdaptivePresetEngine {
  const AdaptivePresetEngine({ToolGateEngine? gateEngine})
      : _gateEngine = gateEngine ?? const ToolGateEngine();

  final ToolGateEngine _gateEngine;

  static const adaptivePresetIds = [
    'bundled_natural',
    'bundled_studio',
    'bundled_soft',
    'bundled_beauty',
    'bundled_glam',
  ];

  /// Parâmetros modulados + gating aplicado.
  Map<String, double> modulate({
    required BeautyPreset preset,
    required FaceQualityContext quality,
  }) {
    final base = preset.toParameterMap();
    final modulated = <String, double>{};

    final global = quality.score.overall.clamp(0.4, 1.0);
    final sharp = quality.score.sharpness;
    final light = quality.score.lighting;
    final pose = quality.score.pose;
    final m = quality.metrics;

    for (final entry in base.entries) {
      final key = entry.key;
      var value = entry.value;
      if (value == 0) {
        modulated[key] = 0;
        continue;
      }

      value = _modulateKey(key, value, global, sharp, light, pose, m);
      modulated[key] = value;
    }

    final gatePlan = _gateEngine.evaluate(quality);
    return gatePlan.applyToParameters(modulated);
  }

  double _modulateKey(
    String key,
    double value,
    double global,
    double sharp,
    double light,
    double pose,
    FaceQualityMetrics m,
  ) {
    if (_isSkinKey(key)) {
      var scale = global;
      if (key == 'skin_smooth' || key == 'remove_acne' || key == 'remove_wrinkles') {
        scale *= sharp.clamp(0.35, 1.0);
      }
      if (key == 'skin_whitening') {
        scale *= light.clamp(0.5, 1.0);
      }
      return value * scale;
    }

    if (_isWarpKey(key)) {
      return value * pose.clamp(0.35, 1.0) * global;
    }

    if (key == 'temperature') {
      return value - m.wbWarmth * value.abs() * 0.5;
    }
    if (key == 'exposure') {
      return value * light.clamp(0.4, 1.0);
    }
    if (key == 'brightness') {
      return value * light.clamp(0.5, 1.0);
    }
    if (key == 'saturation' || key == 'vibrance') {
      return value * global;
    }

    return value * global;
  }

  bool _isSkinKey(String key) =>
      key.startsWith('skin_') ||
      key == 'remove_acne' ||
      key == 'remove_wrinkles' ||
      key == 'remove_dark_circles' ||
      key == 'teeth_whitening' ||
      key == 'blush' ||
      key == 'contour' ||
      key == 'eyebrows' ||
      key == 'eyelashes' ||
      key == 'iris_enhance';

  bool _isWarpKey(String key) =>
      key.contains('face') ||
      key.contains('nose') ||
      key.contains('eye') ||
      key.contains('mouth') ||
      key.contains('lip') ||
      key.contains('jaw') ||
      key.contains('chin') ||
      key.contains('cheek') ||
      key.contains('forehead') ||
      key.contains('temple') ||
      key.contains('smile') ||
      key == 'head_size' ||
      key == 'double_eyelid';
}
