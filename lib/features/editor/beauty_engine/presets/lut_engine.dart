import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_filters/flutter_image_filters.dart';
import 'package:image/image.dart' as img;

import 'lut_square_table.dart';

/// Motor unificado de LUT — Manual Editor + Beauty Engine GPU pass.
class LutEngine {
  LutEngine();

  final Map<String, Uint8List> _pngCache = {};
  final Map<String, ({Uint8List rgba, int width, int height})> _decodedCache =
      {};

  /// Paths bundled disponíveis no app.
  static const bundledNatural = 'assets/filters/lut/natural.png';
  static const bundledCinema = 'assets/filters/lut/cinema_teal_orange.png';

  /// Carrega bytes PNG da LUT (cache em memória).
  Future<Uint8List> loadLutPng(String assetPath) async {
    final cached = _pngCache[assetPath];
    if (cached != null) {
      return cached;
    }

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    _pngCache[assetPath] = bytes;
    return bytes;
  }

  /// Decodifica LUT PNG para RGBA (cache).
  Future<({Uint8List rgba, int width, int height})> decodeLutAsset(
    String assetPath,
  ) async {
    final cached = _decodedCache[assetPath];
    if (cached != null) {
      return cached;
    }

    final png = await loadLutPng(assetPath);
    final decoded = LutSquareTable.decodeLutPng(png);
    _decodedCache[assetPath] = decoded;
    return decoded;
  }

  /// Aplica LUT em buffer RGBA via CPU (paridade com `pass_lut` / shader).
  Future<Uint8List> applyToRgba({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required String lutAssetPath,
    double intensity = 1,
  }) async {
    final lut = await decodeLutAsset(lutAssetPath);
    return LutSquareTable.apply(
      sourceRgba: sourceRgba,
      width: width,
      height: height,
      lutRgba: lut.rgba,
      lutWidth: lut.width,
      lutHeight: lut.height,
      intensity: intensity,
    );
  }

  /// Aplica LUT em JPEG via CPU (ExportPipeline Manual).
  Future<Uint8List> applyToJpeg({
    required Uint8List jpegBytes,
    required String lutAssetPath,
    double intensity = 1,
    int quality = 92,
  }) async {
    if (intensity <= 0) {
      return jpegBytes;
    }

    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      return jpegBytes;
    }

    final sourceRgba = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        sourceRgba[offset++] = pixel.r.toInt();
        sourceRgba[offset++] = pixel.g.toInt();
        sourceRgba[offset++] = pixel.b.toInt();
        sourceRgba[offset++] = pixel.a.toInt();
      }
    }

    final filtered = await applyToRgba(
      sourceRgba: sourceRgba,
      width: decoded.width,
      height: decoded.height,
      lutAssetPath: lutAssetPath,
      intensity: intensity,
    );

    final output = img.Image(width: decoded.width, height: decoded.height);
    var pixelIndex = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        output.setPixelRgba(
          x,
          y,
          filtered[pixelIndex],
          filtered[pixelIndex + 1],
          filtered[pixelIndex + 2],
          filtered[pixelIndex + 3],
        );
        pixelIndex += 4;
      }
    }

    return Uint8List.fromList(img.encodeJpg(output, quality: quality));
  }

  /// Caminho GPU via flutter_image_filters (preview/export de alta fidelidade).
  Future<Uint8List> applyToJpegViaGpu({
    required Uint8List jpegBytes,
    required String lutAssetPath,
    double intensity = 1,
    int quality = 92,
  }) async {
    if (kIsWeb || intensity <= 0) {
      return applyToJpeg(
        jpegBytes: jpegBytes,
        lutAssetPath: lutAssetPath,
        intensity: intensity,
        quality: quality,
      );
    }

    final configuration = SquareLookupTableShaderConfiguration();
    await configuration.setLutAsset(lutAssetPath);
    configuration.intensity = intensity.clamp(0.0, 1.0);

    final source = await TextureSource.fromMemory(jpegBytes);
    final rendered = await configuration.export(source, source.size);
    configuration.dispose();

    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return jpegBytes;
    }

    final png = byteData.buffer.asUint8List();
    final decoded = img.decodeImage(png);
    if (decoded == null) {
      return jpegBytes;
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  void clearCache() {
    _pngCache.clear();
    _decodedCache.clear();
  }
}
