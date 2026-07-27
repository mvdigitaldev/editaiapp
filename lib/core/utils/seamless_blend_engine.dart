import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'seamless_blend_curve.dart';

/// Configuração da colagem sem emenda.
class SeamlessBlendConfig {
  const SeamlessBlendConfig({
    this.aspect = CollageAspectPreset.ratio16x9Portrait,
    this.fusionStrength = 0.5,
    this.maxEdge = 2048,
    this.jpegQuality = 92,
  });

  final CollageAspectPreset aspect;
  final double fusionStrength;
  /// Maior lado do canvas (export 2048, preview 720).
  final int maxEdge;
  final int jpegQuality;

  /// Compat: aliases antigos.
  int get maxCrossAxis => maxEdge;
}

class SeamlessBlendResult {
  const SeamlessBlendResult({
    required this.image,
    required this.width,
    required this.height,
  });

  final img.Image image;
  final int width;
  final int height;
}

/// Motor CPU: canvas no aspect escolhido + slots cover + overlap por fusão.
class SeamlessBlendEngine {
  const SeamlessBlendEngine();

  static const int minPhotos = 2;
  static const int maxPhotos = 12;

  Future<SeamlessBlendResult> blend({
    required List<String> imagePaths,
    SeamlessBlendConfig config = const SeamlessBlendConfig(),
  }) async {
    if (imagePaths.length < minPhotos) {
      throw ArgumentError('São necessárias pelo menos $minPhotos fotos.');
    }
    if (imagePaths.length > maxPhotos) {
      throw ArgumentError('Máximo de $maxPhotos fotos.');
    }

    final decoded = <img.Image>[];
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw FormatException('Não foi possível decodificar: $path');
      }
      decoded.add(image);
    }

    final result = config.aspect.isHorizontalStack
        ? _blendHorizontal(decoded, config)
        : _blendVertical(decoded, config);

    return SeamlessBlendResult(
      image: result,
      width: result.width,
      height: result.height,
    );
  }

  Future<File> exportToFile({
    required List<String> imagePaths,
    SeamlessBlendConfig config = const SeamlessBlendConfig(),
  }) async {
    final result = await blend(imagePaths: imagePaths, config: config);
    final jpegBytes = img.encodeJpg(result.image, quality: config.jpegQuality);
    if (jpegBytes.isEmpty) {
      throw StateError('Falha ao exportar colagem.');
    }

    final tempFile = File(
      '${Directory.systemTemp.path}/seamless_collage_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await tempFile.writeAsBytes(jpegBytes);
    return tempFile;
  }

  img.Image _blendVertical(List<img.Image> images, SeamlessBlendConfig config) {
    final size = config.aspect.canvasSize(config.maxEdge);
    final canvasW = size.width;
    final canvasH = size.height;
    final n = images.length;

    var overlap = SeamlessBlendCurve.overlapPixels(
      axisLength: canvasH,
      photoCount: n,
      fusionStrength: config.fusionStrength,
    );
    overlap = _applyMiddleBudget(
      overlap: overlap,
      photoCount: n,
      slotHint: SeamlessBlendCurve.slotSpan(
        axisLength: canvasH,
        photoCount: n,
        overlap: overlap,
      ),
      fusionStrength: config.fusionStrength,
    );

    final slotH = SeamlessBlendCurve.slotSpan(
      axisLength: canvasH,
      photoCount: n,
      overlap: overlap,
    );
    final step = math.max(1, slotH - overlap);

    final slots = [
      for (final image in images) _coverCrop(image, canvasW, slotH),
    ];

    final canvas = img.Image(width: canvasW, height: canvasH);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    // Primeira foto.
    _blit(canvas, slots.first, 0, 0);

    for (var i = 1; i < n; i++) {
      final dstY = i * step;
      final current = slots[i];
      final blendRows = math.min(overlap, canvasH - dstY);

      if (blendRows > 0) {
        _blendOverlapVertical(
          canvas: canvas,
          bottom: current,
          dstY: dstY,
          overlap: blendRows,
          fusionStrength: config.fusionStrength,
        );
      }

      for (var row = blendRows; row < slotH; row++) {
        final cy = dstY + row;
        if (cy < 0 || cy >= canvasH) continue;
        for (var x = 0; x < canvasW; x++) {
          canvas.setPixel(x, cy, current.getPixel(x, row));
        }
      }
    }

    return canvas;
  }

  img.Image _blendHorizontal(List<img.Image> images, SeamlessBlendConfig config) {
    final size = config.aspect.canvasSize(config.maxEdge);
    final canvasW = size.width;
    final canvasH = size.height;
    final n = images.length;

    var overlap = SeamlessBlendCurve.overlapPixels(
      axisLength: canvasW,
      photoCount: n,
      fusionStrength: config.fusionStrength,
    );
    overlap = _applyMiddleBudget(
      overlap: overlap,
      photoCount: n,
      slotHint: SeamlessBlendCurve.slotSpan(
        axisLength: canvasW,
        photoCount: n,
        overlap: overlap,
      ),
      fusionStrength: config.fusionStrength,
    );

    final slotW = SeamlessBlendCurve.slotSpan(
      axisLength: canvasW,
      photoCount: n,
      overlap: overlap,
    );
    final step = math.max(1, slotW - overlap);

    final slots = [
      for (final image in images) _coverCrop(image, slotW, canvasH),
    ];

    final canvas = img.Image(width: canvasW, height: canvasH);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    _blit(canvas, slots.first, 0, 0);

    for (var i = 1; i < n; i++) {
      final dstX = i * step;
      final current = slots[i];
      final blendCols = math.min(overlap, canvasW - dstX);

      if (blendCols > 0) {
        _blendOverlapHorizontal(
          canvas: canvas,
          right: current,
          dstX: dstX,
          overlap: blendCols,
          fusionStrength: config.fusionStrength,
        );
      }

      for (var col = blendCols; col < slotW; col++) {
        final cx = dstX + col;
        if (cx < 0 || cx >= canvasW) continue;
        for (var y = 0; y < canvasH; y++) {
          canvas.setPixel(cx, y, current.getPixel(col, y));
        }
      }
    }

    return canvas;
  }

  int _applyMiddleBudget({
    required int overlap,
    required int photoCount,
    required int slotHint,
    required double fusionStrength,
  }) {
    if (photoCount <= 2) return overlap;
    final budget = (slotHint *
            SeamlessBlendCurve.middlePhotoOverlapBudget(fusionStrength))
        .round();
    // Cada foto do meio participa de 2 emendas → limita overlap individual.
    final maxEach = math.max(4, budget ~/ 2);
    return math.min(overlap, maxEach);
  }

  img.Image _coverCrop(img.Image source, int targetW, int targetH) {
    if (targetW <= 0 || targetH <= 0) {
      return img.Image(width: 1, height: 1);
    }
    final scale = math.max(
      targetW / source.width,
      targetH / source.height,
    );
    final newW = math.max(targetW, (source.width * scale).round());
    final newH = math.max(targetH, (source.height * scale).round());
    final resized = img.copyResize(source, width: newW, height: newH);
    final x = ((resized.width - targetW) / 2).round().clamp(
          0,
          math.max(0, resized.width - targetW),
        );
    final y = ((resized.height - targetH) / 2).round().clamp(
          0,
          math.max(0, resized.height - targetH),
        );
    return img.copyCrop(
      resized,
      x: x.toInt(),
      y: y.toInt(),
      width: targetW,
      height: targetH,
    );
  }

  void _blit(img.Image canvas, img.Image src, int dstX, int dstY) {
    for (var y = 0; y < src.height; y++) {
      final cy = dstY + y;
      if (cy < 0 || cy >= canvas.height) continue;
      for (var x = 0; x < src.width; x++) {
        final cx = dstX + x;
        if (cx < 0 || cx >= canvas.width) continue;
        canvas.setPixel(cx, cy, src.getPixel(x, y));
      }
    }
  }

  void _blendOverlapVertical({
    required img.Image canvas,
    required img.Image bottom,
    required int dstY,
    required int overlap,
    required double fusionStrength,
  }) {
    for (var row = 0; row < overlap; row++) {
      final t = overlap <= 1 ? 1.0 : row / (overlap - 1);
      final weight = SeamlessBlendCurve.blendWeight(t, fusionStrength);
      final cy = dstY + row;
      if (cy < 0 || cy >= canvas.height) continue;
      for (var x = 0; x < canvas.width; x++) {
        if (x >= bottom.width || row >= bottom.height) continue;
        final topPixel = canvas.getPixel(x, cy);
        final bottomPixel = bottom.getPixel(x, row);
        canvas.setPixel(
          x,
          cy,
          _lerpPixel(topPixel, bottomPixel, weight),
        );
      }
    }
  }

  void _blendOverlapHorizontal({
    required img.Image canvas,
    required img.Image right,
    required int dstX,
    required int overlap,
    required double fusionStrength,
  }) {
    for (var col = 0; col < overlap; col++) {
      final t = overlap <= 1 ? 1.0 : col / (overlap - 1);
      final weight = SeamlessBlendCurve.blendWeight(t, fusionStrength);
      final cx = dstX + col;
      if (cx < 0 || cx >= canvas.width) continue;
      for (var y = 0; y < canvas.height; y++) {
        if (y >= right.height || col >= right.width) continue;
        final leftPixel = canvas.getPixel(cx, y);
        final rightPixel = right.getPixel(col, y);
        canvas.setPixel(
          cx,
          y,
          _lerpPixel(leftPixel, rightPixel, weight),
        );
      }
    }
  }

  img.Color _lerpPixel(img.Pixel a, img.Pixel b, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return img.ColorRgba8(
      SeamlessColorBlend.lerpChannel(a.r.toInt(), b.r.toInt(), clamped),
      SeamlessColorBlend.lerpChannel(a.g.toInt(), b.g.toInt(), clamped),
      SeamlessColorBlend.lerpChannel(a.b.toInt(), b.b.toInt(), clamped),
      SeamlessColorBlend.lerpChannel(a.a.toInt(), b.a.toInt(), clamped),
    );
  }
}
