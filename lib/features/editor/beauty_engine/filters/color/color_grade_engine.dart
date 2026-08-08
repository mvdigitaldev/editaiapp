import 'dart:math' as math;
import 'dart:typed_data';

import '../../../filter_presets/filter_grade_engine.dart';
import '../../../filter_presets/filter_preset_mapper.dart';
import '../../color/color_science.dart';
import '../../models/tune_params.dart';

/// Motor de cor global para RGBA8 — paridade com [FilterGradeEngine] CPU,
/// mais vinheta radial e nitidez com proteção de pele.
class ColorGradeEngine {
  const ColorGradeEngine();

  Uint8List applyToRgba({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required TuneParams tune,
    Float32List? skinProtectionWeights,
  }) {
    if (tune.isEmpty) {
      return Uint8List.fromList(sourceRgba);
    }

    final filterTune = tuneParamsToFilterTune(tune);
    final matrices = filterTuneToColorMatrices(filterTune);
    var rgba = matrices.isEmpty
        ? Uint8List.fromList(sourceRgba)
        : _applyMatrices(sourceRgba, width, height, matrices);

    if (tune.vignette.abs() > 1e-6) {
      _applyVignette(rgba, width, height, tune.vignette);
    }

    if (tune.sharpness.abs() > 1e-6) {
      _applySharpness(
        rgba,
        width,
        height,
        tune.sharpness,
        skinProtectionWeights,
      );
    }

    return rgba;
  }

  Uint8List _applyMatrices(
    Uint8List source,
    int width,
    int height,
    List<List<double>> matrices,
  ) {
    final merged = mergeFilterColorMatrices(matrices);
    final output = Uint8List.fromList(source);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final r = output[i].toDouble();
        final g = output[i + 1].toDouble();
        final b = output[i + 2].toDouble();

        final nr = (merged[0] * r + merged[1] * g + merged[2] * b + merged[4])
            .clamp(0, 255);
        final ng = (merged[5] * r + merged[6] * g + merged[7] * b + merged[9])
            .clamp(0, 255);
        final nb =
            (merged[10] * r + merged[11] * g + merged[12] * b + merged[14])
                .clamp(0, 255);

        output[i] = nr.round();
        output[i + 1] = ng.round();
        output[i + 2] = nb.round();
      }
    }
    return output;
  }

  void _applyVignette(
    Uint8List rgba,
    int width,
    int height,
    double amount,
  ) {
    final strength = amount.clamp(-1.0, 1.0);
    if (strength == 0) {
      return;
    }

    final cx = width / 2.0;
    final cy = height / 2.0;
    final maxDist = math.sqrt(cx * cx + cy * cy);
    final start = (0.5 - strength.abs() * 0.35).clamp(0.0, 1.0);
    final end = (0.85 + strength.abs() * 0.1).clamp(0.0, 1.0);
    final range = (end - start).clamp(0.01, 1.0);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) /
            maxDist;
        final t = ((dist - start) / range).clamp(0.0, 1.0);
        final falloff = strength > 0 ? t * t : 0;
        final factor = (1.0 - strength.abs() * falloff).clamp(0.0, 1.0);
        if (factor >= 0.999) {
          continue;
        }
        final i = (y * width + x) * 4;
        rgba[i] = (rgba[i] * factor).round().clamp(0, 255);
        rgba[i + 1] = (rgba[i + 1] * factor).round().clamp(0, 255);
        rgba[i + 2] = (rgba[i + 2] * factor).round().clamp(0, 255);
      }
    }
  }

  void _applySharpness(
    Uint8List rgba,
    int width,
    int height,
    double amount,
    Float32List? skinProtection,
  ) {
    final strength = amount.clamp(-1.0, 1.0);
    if (strength == 0) {
      return;
    }

    final luma = ColorScience.lumaFromRgba(rgba, width, height);
    final blurred = _boxBlur3(luma, width, height);
    final scale = strength * 4.0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = y * width + x;
        final detail = luma[p] - blurred[p];
        var mix = (detail * scale).clamp(-0.35, 0.35);
        if (skinProtection != null && p < skinProtection.length) {
          final protect = skinProtection[p].clamp(0.0, 1.0);
          mix *= 1.0 - protect * 0.85;
        }
        if (mix.abs() < 1e-5) {
          continue;
        }
        final i = p * 4;
        for (var ch = 0; ch < 3; ch++) {
          final linear = ColorScience.srgbToLinear(rgba[i + ch] / 255.0);
          final adjusted = ColorScience.linearToSrgb8(linear + mix);
          rgba[i + ch] = adjusted;
        }
      }
    }
  }

  Float32List _boxBlur3(Float32List source, int width, int height) {
    final temp = Float32List(source.length);
    final out = Float32List(source.length);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var sum = 0.0;
        var count = 0;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          sum += source[y * width + nx];
          count++;
        }
        temp[y * width + x] = sum / count;
      }
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var sum = 0.0;
        var count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          sum += temp[ny * width + x];
          count++;
        }
        out[y * width + x] = sum / count;
      }
    }
    return out;
  }
}

/// Combina matrices 5×4 do pro_image_editor (exportado para reuse no beauty).
List<double> mergeFilterColorMatrices(List<List<double>> matrices) {
  var combined = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  for (final matrix in matrices) {
    combined = _multiplyColorMatrices(matrix, combined);
  }
  return combined;
}

List<double> _multiplyColorMatrices(List<double> a, List<double> b) {
  const size = 4;
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < size; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = col == 4 ? a[row * 5 + 4] : 0.0;
      for (var k = 0; k < size; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      result[row * 5 + col] = sum;
    }
  }
  return result;
}
