import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_filters/flutter_image_filters.dart';
import 'package:image/image.dart' as img;
import 'package:pro_image_editor/pro_image_editor.dart';

import '../beauty_engine/presets/lut_engine.dart';
import 'filter_preset.dart';

/// Pipeline GPU de grade Lightroom (LUT + ajustes) para preview e export.
class FilterGradeEngine {
  FilterGradeEngine({LutEngine? lutEngine}) : _lutEngine = lutEngine ?? LutEngine();

  final LutEngine _lutEngine;
  Future<Uint8List> applyToJpeg({
    required Uint8List jpegBytes,
    String? lutAssetPath,
    double lutIntensity = 1,
    FilterTuneParams tune = const FilterTuneParams(),
    int quality = 92,
    int? maxPreviewDimension,
  }) async {
    var working = jpegBytes;
    if (maxPreviewDimension != null) {
      working = _downscaleJpeg(working, maxPreviewDimension, quality);
    }

    if (kIsWeb) {
      return _applyCpu(
        jpegBytes: working,
        lutAssetPath: lutAssetPath,
        lutIntensity: lutIntensity,
        tune: tune,
        quality: quality,
      );
    }

    try {
      return await _applyGpu(
        jpegBytes: working,
        lutAssetPath: lutAssetPath,
        lutIntensity: lutIntensity,
        tune: tune,
        quality: quality,
      );
    } catch (_) {
      return _applyCpu(
        jpegBytes: working,
        lutAssetPath: lutAssetPath,
        lutIntensity: lutIntensity,
        tune: tune,
        quality: quality,
      );
    }
  }

  Future<Uint8List> applyPresetToJpeg({
    required Uint8List jpegBytes,
    required FilterPreset preset,
    int quality = 92,
    int? maxPreviewDimension,
  }) {
    return applyToJpeg(
      jpegBytes: jpegBytes,
      lutAssetPath: preset.lutAssetPath,
      lutIntensity: preset.lutIntensity,
      tune: preset.tune,
      quality: quality,
      maxPreviewDimension: maxPreviewDimension,
    );
  }

  /// Export do editor manual: tune já foi aplicado via matrices no preview.
  /// Reaplica LUT + ajustes avançados (vinheta, fade, etc.).
  Future<Uint8List> applyPresetForManualEditorExport({
    required Uint8List imageBytes,
    required FilterPreset preset,
    int quality = 92,
  }) {
    return applyToJpeg(
      jpegBytes: imageBytes,
      lutAssetPath: preset.lutAssetPath,
      lutIntensity: preset.lutIntensity,
      tune: preset.tuneForManualEditorExport(),
      quality: quality,
    );
  }

  Future<Uint8List> _applyGpu({
    required Uint8List jpegBytes,
    String? lutAssetPath,
    required double lutIntensity,
    required FilterTuneParams tune,
    required int quality,
  }) async {
    final group = GroupShaderConfiguration(reimportImage: true);
    final disposables = <ShaderConfiguration>[];

    if (lutAssetPath != null &&
        lutAssetPath.isNotEmpty &&
        lutIntensity > 0) {
      final lut = SquareLookupTableShaderConfiguration();
      await lut.setLutAsset(lutAssetPath);
      lut.intensity = lutIntensity.clamp(0.0, 1.0);
      group.add(lut);
      disposables.add(lut);
    }

    _addExposure(group, disposables, tune.exposure);
    _addContrast(group, disposables, tune.contrast);
    _addBrightness(group, disposables, tune.brightness);
    _addHighlightsShadows(group, disposables, tune.highlights, tune.shadows);
    _addWhiteBalance(group, disposables, tune.temperature, tune.tint);
    _addVibrance(group, disposables, tune.vibrance);
    _addSaturation(group, disposables, tune.saturation);
    _addHue(group, disposables, tune.hue);
    _addGamma(group, disposables, tune.gamma);
    _addMatrixStage(group, disposables, tune);
    _addVignette(group, disposables, tune.vignette);

    if (disposables.isEmpty) {
      return jpegBytes;
    }

    final source = await TextureSource.fromMemory(jpegBytes);
    final rendered = await group.export(source, source.size);

    for (final configuration in disposables) {
      configuration.dispose();
    }

    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return jpegBytes;
    }

    final decoded = img.decodeImage(byteData.buffer.asUint8List());
    if (decoded == null) {
      return jpegBytes;
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  Future<Uint8List> _applyCpu({
    required Uint8List jpegBytes,
    String? lutAssetPath,
    required double lutIntensity,
    required FilterTuneParams tune,
    required int quality,
  }) async {
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      return jpegBytes;
    }

    var output = img.Image.from(decoded);
    final matrices = filterTuneToColorMatrices(tune);
    if (matrices.isNotEmpty) {
      output = _applyMatricesCpu(output, matrices);
    }

    var encoded = Uint8List.fromList(img.encodeJpg(output, quality: quality));

    if (lutAssetPath != null &&
        lutAssetPath.isNotEmpty &&
        lutIntensity > 0) {
      encoded = await _lutEngine.applyToJpeg(
        jpegBytes: encoded,
        lutAssetPath: lutAssetPath,
        intensity: lutIntensity,
        quality: quality,
      );
    }

    return encoded;
  }

  void _addExposure(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = ExposureShaderConfiguration();
    config.exposure = (value * 4).clamp(-10.0, 10.0);
    group.add(config);
    disposables.add(config);
  }

  void _addContrast(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = ContrastShaderConfiguration();
    config.contrast = (1 + value * 1.2).clamp(0.0, 4.0);
    group.add(config);
    disposables.add(config);
  }

  void _addBrightness(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = BrightnessShaderConfiguration();
    config.brightness = (value * 2).clamp(-1.0, 1.0);
    group.add(config);
    disposables.add(config);
  }

  void _addHighlightsShadows(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double highlights,
    double shadows,
  ) {
    if (highlights == 0 && shadows == 0) return;
    final config = HighlightShadowShaderConfiguration();
    config.highlights = (1 + highlights).clamp(0.0, 1.0);
    config.shadows = (0.5 + shadows).clamp(0.0, 1.0);
    group.add(config);
    disposables.add(config);
  }

  void _addWhiteBalance(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double temperature,
    double tint,
  ) {
    if (temperature == 0 && tint == 0) return;
    final config = WhiteBalanceShaderConfiguration();
    config.temperature = 5000 + temperature * 3000;
    config.tint = tint * 100;
    group.add(config);
    disposables.add(config);
  }

  void _addVibrance(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = VibranceShaderConfiguration();
    config.vibrance = value * 2;
    group.add(config);
    disposables.add(config);
  }

  void _addSaturation(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = SaturationShaderConfiguration();
    config.saturation = (1 + value * 2).clamp(0.0, 2.0);
    group.add(config);
    disposables.add(config);
  }

  void _addHue(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = HueShaderConfiguration();
    config.hueAdjust = ((value + 0.5) * 360).clamp(0.0, 360.0);
    group.add(config);
    disposables.add(config);
  }

  void _addGamma(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = GammaShaderConfiguration();
    config.gamma = (1 + value).clamp(0.1, 3.0);
    group.add(config);
    disposables.add(config);
  }

  void _addMatrixStage(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    FilterTuneParams tune,
  ) {
    final matrices = <List<double>>[];
    if (tune.whites != 0) {
      matrices.add(ColorFilterAddons.brightness(tune.whites * 0.5));
    }
    if (tune.blacks != 0) {
      matrices.add(ColorFilterAddons.brightness(-tune.blacks * 0.5));
    }
    if (tune.fade != 0) {
      matrices.add(ColorFilterAddons.fade(tune.fade.abs().clamp(0.0, 1.0)));
    }
    if (tune.luminance != 0) {
      matrices.add(ColorFilterAddons.luminance(tune.luminance));
    }
    if (tune.sharpness != 0) {
      matrices.add(ColorFilterAddons.sharpness(tune.sharpness));
    }

    if (matrices.isEmpty) return;

    final merged = _mergeColorMatrices(matrices);
    final config = ColorMatrixShaderConfiguration();
    config.colorMatrix = _matrix4FromColorMatrix(merged);
    group.add(config);
    disposables.add(config);
  }

  void _addVignette(
    GroupShaderConfiguration group,
    List<ShaderConfiguration> disposables,
    double value,
  ) {
    if (value == 0) return;
    final config = VignetteShaderConfiguration();
    config.start = (0.5 - value.abs() * 0.35).clamp(0.0, 1.0);
    config.end = (0.85 + value.abs() * 0.1).clamp(0.0, 1.0);
    group.add(config);
    disposables.add(config);
  }

  Matrix4 _matrix4FromColorMatrix(List<double> matrix) {
    return Matrix4.fromList([
      matrix[0], matrix[1], matrix[2], matrix[3],
      matrix[5], matrix[6], matrix[7], matrix[8],
      matrix[10], matrix[11], matrix[12], matrix[13],
      matrix[15], matrix[16], matrix[17], matrix[18],
    ]);
  }

  img.Image _applyMatricesCpu(img.Image source, List<List<double>> matrices) {
    var output = img.Image.from(source);
    final merged = _mergeColorMatrices(matrices);
    for (var y = 0; y < output.height; y++) {
      for (var x = 0; x < output.width; x++) {
        final pixel = output.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final nr = (merged[0] * r +
                merged[1] * g +
                merged[2] * b +
                merged[4])
            .clamp(0, 255);
        final ng = (merged[5] * r +
                merged[6] * g +
                merged[7] * b +
                merged[9])
            .clamp(0, 255);
        final nb = (merged[10] * r +
                merged[11] * g +
                merged[12] * b +
                merged[14])
            .clamp(0, 255);
        output.setPixelRgba(
          x,
          y,
          nr.round(),
          ng.round(),
          nb.round(),
          pixel.a.toInt(),
        );
      }
    }
    return output;
  }

  Uint8List _downscaleJpeg(
    Uint8List jpegBytes,
    int maxDimension,
    int quality,
  ) {
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      return jpegBytes;
    }

    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (longest <= maxDimension) {
      return jpegBytes;
    }

    final scale = maxDimension / longest;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }
}

/// Matrices de preview leve para o pro_image_editor.
List<List<double>> filterTuneToColorMatrices(FilterTuneParams tune) {
  final matrices = <List<double>>[];

  void addIfNonZero(double value, List<double> Function(double) builder) {
    if (value != 0) {
      matrices.add(builder(value));
    }
  }

  addIfNonZero(tune.exposure, ColorFilterAddons.exposure);
  addIfNonZero(tune.contrast, ColorFilterAddons.contrast);
  addIfNonZero(tune.brightness, ColorFilterAddons.brightness);
  addIfNonZero(tune.highlights, (v) => ColorFilterAddons.brightness(v * 0.35));
  addIfNonZero(tune.shadows, (v) => ColorFilterAddons.brightness(v * 0.35));
  addIfNonZero(tune.whites, (v) => ColorFilterAddons.brightness(v * 0.5));
  addIfNonZero(tune.blacks, (v) => ColorFilterAddons.brightness(-v * 0.5));
  addIfNonZero(tune.temperature, ColorFilterAddons.temperature);
  addIfNonZero(tune.tint, (v) => ColorFilterAddons.addictiveColor(v * 20, 0, -v * 20));
  addIfNonZero(tune.vibrance, (v) => ColorFilterAddons.saturation(v * 0.8));
  addIfNonZero(tune.saturation, ColorFilterAddons.saturation);
  addIfNonZero(tune.hue, ColorFilterAddons.hue);
  addIfNonZero(tune.fade, (v) => ColorFilterAddons.fade(v.abs().clamp(0.0, 1.0)));
  addIfNonZero(tune.sharpness, ColorFilterAddons.sharpness);
  addIfNonZero(tune.luminance, ColorFilterAddons.luminance);
  addIfNonZero(tune.gamma, (v) => ColorFilterAddons.contrast(v * 0.25));

  return matrices;
}

List<double> _mergeColorMatrices(List<List<double>> matrices) {
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
