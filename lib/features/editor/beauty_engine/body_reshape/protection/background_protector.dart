import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import '../maps/protection_maps.dart';
import '../models/background_analysis.dart';
import '../models/body_reshape_request.dart';
import 'edge_map.dart';
import 'line_map.dart';
import 'rigidity_map.dart';

/// Resultado da análise estrutural de fundo.
class BackgroundProtectionResult {
  final EdgeMap edges;
  final LineMap lines;
  final RigidityMap rigidity;
  final BackgroundAnalysis analysis;

  const BackgroundProtectionResult({
    required this.edges,
    required this.lines,
    required this.rigidity,
    required this.analysis,
  });

  bool get isEmpty => rigidity.isEmpty;
}

/// Orquestra edge/line/rigidity e aplica limite de deslocamento no [WarpField].
class BackgroundProtector {
  const BackgroundProtector({
    this.edgeBuilder = const EdgeMapBuilder(),
    this.lineBuilder = const LineMapBuilder(),
    this.rigidityBuilder = const RigidityMapBuilder(),
    this.maxLineDistortionPx = 1.25,
  });

  final EdgeMapBuilder edgeBuilder;
  final LineMapBuilder lineBuilder;
  final RigidityMapBuilder rigidityBuilder;

  /// Orçamento máximo de deslocamento em pixels sobre linhas estruturais.
  final double maxLineDistortionPx;

  BackgroundProtectionResult analyzeLuminance({
    required Float32List luminance,
    required int width,
    required int height,
    required Size imageSize,
    ProtectionMaps? protection,
    double confidence = 1,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    final mapSize = _resolveMapSize(
      sourceWidth: width,
      sourceHeight: height,
      imageSize: imageSize,
      qualityProfile: qualityProfile,
    );

    final luma = mapSize.width == width && mapSize.height == height
        ? luminance
        : _downsampleLuma(luminance, width, height, mapSize.width, mapSize.height);

    final edges = edgeBuilder.buildFromLuminance(
      luminance: luma,
      width: mapSize.width,
      height: mapSize.height,
      imageSize: imageSize,
    );
    final lines = lineBuilder.build(edges);
    final rigidity = rigidityBuilder.build(
      edges: edges,
      lines: lines,
      imageSize: imageSize,
      protection: protection,
      confidence: confidence,
    );

    return BackgroundProtectionResult(
      edges: edges,
      lines: lines,
      rigidity: rigidity,
      analysis: rigidity.toBackgroundAnalysis(confidence: confidence),
    );
  }

  BackgroundProtectionResult analyzeRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required Size imageSize,
    ProtectionMaps? protection,
    double confidence = 1,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    final luminance = Float32List(width * height);
    for (var i = 0; i < width * height; i++) {
      final o = i * 4;
      luminance[i] =
          (0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2]) / 255.0;
    }
    return analyzeLuminance(
      luminance: luminance,
      width: width,
      height: height,
      imageSize: imageSize,
      protection: protection,
      confidence: confidence,
      qualityProfile: qualityProfile,
    );
  }

  /// Aplica rigidez como limite do campo: `disp *= (1 - rigidity)`.
  ///
  /// Sobre linhas, também clampa |disp| ao orçamento [maxLineDistortionPx].
  WarpField applyToField({
    required WarpField field,
    required RigidityMap rigidity,
    LineMap? lines,
  }) {
    if (field.isIdentity || rigidity.isEmpty) {
      return field.copyWith(rigidityMap: rigidity.isEmpty ? null : rigidity);
    }

    final gridW = field.gridWidth;
    final gridH = field.gridHeight;
    final outDisp = Float32List(field.displacement.length);
    final outMask = Float32List(field.mask.length);
    final invW = field.imageSize.width > 0 ? 1.0 / field.imageSize.width : 0.0;
    final invH = field.imageSize.height > 0 ? 1.0 / field.imageSize.height : 0.0;
    final lineBudget = maxLineDistortionPx;

    for (var gy = 0; gy < gridH; gy++) {
      for (var gx = 0; gx < gridW; gx++) {
        final idx = gy * gridW + gx;
        final px = gx / math.max(gridW - 1, 1) * field.imageSize.width;
        final py = gy / math.max(gridH - 1, 1) * field.imageSize.height;
        final nnx = px * invW;
        final nny = py * invH;

        final r = rigidity.sampleNormalized(nnx, nny).clamp(0.0, 1.0);
        // Curva mais agressiva no fundo rígido (quase imóvel).
        final soft = (1.0 - r) * (1.0 - r);
        var dx = field.displacement[idx * 2] * soft;
        var dy = field.displacement[idx * 2 + 1] * soft;

        final lineStrength = lines == null || lines.isEmpty
            ? 0.0
            : lines.sampleStrength(nnx, nny);
        if (lineStrength > 0.12 || r > 0.55) {
          final mag = math.sqrt(dx * dx + dy * dy);
          final budget = lineBudget *
              (1.0 - 0.75 * math.max(lineStrength, r));
          if (mag > budget && mag > 1e-6) {
            final s = budget / mag;
            dx *= s;
            dy *= s;
          }
        }

        outDisp[idx * 2] = dx;
        outDisp[idx * 2 + 1] = dy;
        outMask[idx] = field.mask[idx] * (1.0 - r);
      }
    }

    return field.copyWith(
      displacement: outDisp,
      mask: outMask,
      rigidityMap: rigidity,
    );
  }

  ({int width, int height}) _resolveMapSize({
    required int sourceWidth,
    required int sourceHeight,
    required Size imageSize,
    required WarpQualityProfile qualityProfile,
  }) {
    final scale = qualityProfile.mapResolutionScale.clamp(0.35, 1.0);
    final maxSide = switch (qualityProfile.quality) {
      WarpQuality.interactive => 64,
      WarpQuality.preview => 96,
      WarpQuality.export => 128,
    };
    var w = math.max(16, (sourceWidth * scale).round());
    var h = math.max(16, (sourceHeight * scale).round());
    final longest = math.max(w, h);
    if (longest > maxSide) {
      final s = maxSide / longest;
      w = math.max(16, (w * s).round());
      h = math.max(16, (h * s).round());
    }
    return (width: w, height: h);
  }

  Float32List _downsampleLuma(
    Float32List source,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final out = Float32List(dstW * dstH);
    for (var y = 0; y < dstH; y++) {
      final sy = ((y + 0.5) / dstH * srcH).floor().clamp(0, srcH - 1);
      for (var x = 0; x < dstW; x++) {
        final sx = ((x + 0.5) / dstW * srcW).floor().clamp(0, srcW - 1);
        out[y * dstW + x] = source[sy * srcW + sx];
      }
    }
    return out;
  }
}
