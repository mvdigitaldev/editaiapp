import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'seamless_blend_curve.dart';

enum CollageLayout { vertical, horizontal }

/// Configuração da colagem sem emenda.
class SeamlessBlendConfig {
  const SeamlessBlendConfig({
    this.layout = CollageLayout.vertical,
    this.fusionStrength = 0.5,
    this.maxCrossAxis = 2048,
    this.jpegQuality = 92,
  });

  final CollageLayout layout;
  final double fusionStrength;
  final int maxCrossAxis;
  final int jpegQuality;
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

/// Motor CPU para colagem com transição suave entre fotos.
class SeamlessBlendEngine {
  const SeamlessBlendEngine();

  static const int minPhotos = 2;
  static const int maxPhotos = 12;

  /// Overlap uniforme por eixo transversal, limitado pelas fotos adjacentes.
  static int overlapPixels({
    required int crossAxis,
    required int sizeA,
    required int sizeB,
  }) {
    if (sizeA <= 0 || sizeB <= 0 || crossAxis <= 0) return 0;

    final base = (crossAxis * SeamlessBlendCurve.overlapRatio).round();
    final limit = math.min(sizeA, sizeB) ~/ 3;
    return base.clamp(4, math.max(4, limit));
  }

  /// Compatibilidade com testes legados (2 fotos mesma dimensão).
  static int overlapPixelsLegacy(int sizeA, int sizeB) {
    return overlapPixels(
      crossAxis: math.max(sizeA, sizeB),
      sizeA: sizeA,
      sizeB: sizeB,
    );
  }

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

    final result = config.layout == CollageLayout.vertical
        ? _blendVertical(decoded, config)
        : _blendHorizontal(decoded, config);

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
    final targetWidth = _targetCrossAxis(
      images.map((i) => i.width).toList(),
      config.maxCrossAxis,
    );

    final scaled = images
        .map((image) => img.copyResize(image, width: targetWidth))
        .toList();

    final heights = scaled.map((i) => i.height).toList();
    final overlaps = _computeOverlaps(
      sizes: heights,
      crossAxis: targetWidth,
    );

    var totalHeight = scaled.first.height;
    for (var i = 1; i < scaled.length; i++) {
      totalHeight += scaled[i].height - overlaps[i - 1];
    }

    final canvas = img.Image(width: targetWidth, height: totalHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, scaled.first, dstY: 0);

    var currentY = scaled.first.height;
    for (var i = 1; i < scaled.length; i++) {
      final overlap = overlaps[i - 1];
      final current = scaled[i];
      final dstY = currentY - overlap;

      _blendOverlapVertical(
        canvas: canvas,
        bottom: current,
        dstY: dstY,
        overlap: overlap,
        fusionStrength: config.fusionStrength,
      );

      for (var row = overlap; row < current.height; row++) {
        for (var x = 0; x < targetWidth; x++) {
          canvas.setPixel(x, dstY + row, current.getPixel(x, row));
        }
      }

      currentY = dstY + current.height;
    }

    return canvas;
  }

  img.Image _blendHorizontal(List<img.Image> images, SeamlessBlendConfig config) {
    final targetHeight = _targetCrossAxis(
      images.map((i) => i.height).toList(),
      config.maxCrossAxis,
    );

    final scaled = images
        .map((image) => img.copyResize(image, height: targetHeight))
        .toList();

    final widths = scaled.map((i) => i.width).toList();
    final overlaps = _computeOverlaps(
      sizes: widths,
      crossAxis: targetHeight,
    );

    var totalWidth = scaled.first.width;
    for (var i = 1; i < scaled.length; i++) {
      totalWidth += scaled[i].width - overlaps[i - 1];
    }

    final canvas = img.Image(width: totalWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, scaled.first, dstX: 0);

    var currentX = scaled.first.width;
    for (var i = 1; i < scaled.length; i++) {
      final overlap = overlaps[i - 1];
      final current = scaled[i];
      final dstX = currentX - overlap;

      _blendOverlapHorizontal(
        canvas: canvas,
        right: current,
        dstX: dstX,
        overlap: overlap,
        fusionStrength: config.fusionStrength,
      );

      for (var col = overlap; col < current.width; col++) {
        for (var y = 0; y < targetHeight; y++) {
          canvas.setPixel(dstX + col, y, current.getPixel(col, y));
        }
      }

      currentX = dstX + current.width;
    }

    return canvas;
  }

  /// Todas as junções usam o mesmo overlap base; fotos do meio têm orçamento limitado.
  List<int> _computeOverlaps({
    required List<int> sizes,
    required int crossAxis,
  }) {
    final overlaps = <int>[];
    for (var i = 0; i < sizes.length - 1; i++) {
      overlaps.add(
        overlapPixels(
          crossAxis: crossAxis,
          sizeA: sizes[i],
          sizeB: sizes[i + 1],
        ),
      );
    }

    for (var i = 1; i < sizes.length - 1; i++) {
      final budget =
          (sizes[i] * SeamlessBlendCurve.middlePhotoOverlapBudget).round();
      final top = overlaps[i - 1];
      final bottom = overlaps[i];
      final total = top + bottom;

      if (total > budget && budget >= 8) {
        final scale = budget / total;
        overlaps[i - 1] = math.max(4, (top * scale).round());
        overlaps[i] = math.max(4, (bottom * scale).round());
      }
    }

    return overlaps;
  }

  int _targetCrossAxis(List<int> values, int maxCrossAxis) {
    final maxValue = values.reduce(math.max);
    return maxValue.clamp(1, maxCrossAxis);
  }

  /// Amostra o topo do canvas (composite acumulado) + base da foto nova.
  void _blendOverlapVertical({
    required img.Image canvas,
    required img.Image bottom,
    required int dstY,
    required int overlap,
    required double fusionStrength,
  }) {
    for (var row = 0; row < overlap; row++) {
      final t = row / overlap;
      final weight = SeamlessBlendCurve.blendWeight(t, fusionStrength);
      for (var x = 0; x < canvas.width; x++) {
        final topPixel = canvas.getPixel(x, dstY + row);
        final bottomPixel = bottom.getPixel(x, row);
        canvas.setPixel(
          x,
          dstY + row,
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
      final t = col / overlap;
      final weight = SeamlessBlendCurve.blendWeight(t, fusionStrength);
      for (var y = 0; y < canvas.height; y++) {
        final leftPixel = canvas.getPixel(dstX + col, y);
        final rightPixel = right.getPixel(col, y);
        canvas.setPixel(
          dstX + col,
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
