import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../maps/protection_maps.dart';
import '../models/background_analysis.dart';
import 'edge_map.dart';
import 'line_map.dart';

/// Rigidez estrutural do fundo (0 = livre, 1 = imóvel).
///
/// Interior da pessoa permanece próximo de zero — não congela estampas de roupa.
class RigidityMap {
  final Float32List values;
  final int width;
  final int height;
  final Size imageSize;
  final double maxValue;
  final bool hadLines;

  const RigidityMap({
    required this.values,
    required this.width,
    required this.height,
    required this.imageSize,
    required this.maxValue,
    required this.hadLines,
  }) : assert(width >= 0 && height >= 0);

  bool get isEmpty => values.isEmpty || width <= 0 || height <= 0;

  double sampleNormalized(double nx, double ny) {
    if (isEmpty) {
      return 0;
    }
    final fx = (nx.clamp(0.0, 1.0) * (width - 1));
    final fy = (ny.clamp(0.0, 1.0) * (height - 1));
    final x0 = fx.floor().clamp(0, width - 1);
    final y0 = fy.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final v00 = values[y0 * width + x0];
    final v10 = values[y0 * width + x1];
    final v01 = values[y1 * width + x0];
    final v11 = values[y1 * width + x1];
    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }

  /// Ponte para o contrato de provider da Sprint 2.
  BackgroundAnalysis toBackgroundAnalysis({
    String providerId = 'background_protector',
    double confidence = 1,
  }) {
    final bytes = Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      bytes[i] = (values[i].clamp(0.0, 1.0) * 255).round();
    }
    return BackgroundAnalysis(
      rigidity: bytes,
      width: width,
      height: height,
      providerId: providerId,
      confidence: confidence,
    );
  }
}

/// Combina edge/line/proximidade/matte em [RigidityMap].
class RigidityMapBuilder {
  const RigidityMapBuilder({
    this.farBackgroundWeight = 0.97,
    this.lineWeight = 0.95,
    this.edgeWeight = 0.35,
    this.nearSilhouetteFraction = 0.045,
    this.farBackgroundFraction = 0.12,
  });

  final double farBackgroundWeight;
  final double lineWeight;
  final double edgeWeight;

  /// Fração da menor dimensão: anel próximo à silhueta.
  final double nearSilhouetteFraction;

  /// Fração da menor dimensão: fundo considerado "longe".
  final double farBackgroundFraction;

  RigidityMap build({
    required EdgeMap edges,
    required LineMap lines,
    required Size imageSize,
    ProtectionMaps? protection,
    double confidence = 1,
  }) {
    if (edges.isEmpty) {
      return RigidityMap(
        values: Float32List(0),
        width: 0,
        height: 0,
        imageSize: imageSize,
        maxValue: 0,
        hadLines: false,
      );
    }

    final width = edges.width;
    final height = edges.height;
    final values = Float32List(width * height);
    final conf = confidence.clamp(0.0, 1.0);
    final minDim = math.min(imageSize.width, imageSize.height);
    final nearSilhouettePx = math.max(6.0, minDim * nearSilhouetteFraction);
    final farBackgroundPx = math.max(nearSilhouettePx + 4, minDim * farBackgroundFraction);
    var maxValue = 0.0;

    for (var y = 0; y < height; y++) {
      final ny = height == 1 ? 0.5 : y / (height - 1);
      for (var x = 0; x < width; x++) {
        final nx = width == 1 ? 0.5 : x / (width - 1);
        final idx = y * width + x;

        // Interior da pessoa → rigidez ~0 (não protege textura/roupa).
        final personWeight = protection == null || protection.isEmpty
            ? 0.0
            : protection.sampleWarpWeight(nx, ny);
        final backgroundFactor = (1.0 - personWeight).clamp(0.0, 1.0);
        if (backgroundFactor <= 1e-4) {
          values[idx] = 0;
          continue;
        }

        final sdf = protection == null || protection.isEmpty
            ? farBackgroundPx
            : protection.sdf.sampleNormalized(nx, ny);
        // sdf > 0 = exterior. Longe da silhueta → fundo rígido.
        final far = sdf <= 0
            ? 0.0
            : _smoothstep(
                ((sdf - nearSilhouettePx * 0.2) /
                        math.max(farBackgroundPx - nearSilhouettePx * 0.2, 1))
                    .clamp(0.0, 1.0),
              );
        final nearBand = sdf <= 0
            ? 0.0
            : _smoothstep(
                (1.0 - (sdf / math.max(nearSilhouettePx, 1)).clamp(0.0, 1.0)),
              );

        final line = lines.isEmpty ? 0.0 : lines.strength[idx];
        final edge = edges.magnitude[idx];

        final combined = math.max(
          far * farBackgroundWeight,
          math.max(
            line * lineWeight * (0.45 + 0.55 * (nearBand + far).clamp(0.0, 1.0)),
            edge * edgeWeight * nearBand * (0.5 + 0.5 * far),
          ),
        );

        final rigidity =
            (backgroundFactor * combined).clamp(0.0, 1.0) * conf;

        values[idx] = rigidity;
        if (rigidity > maxValue) {
          maxValue = rigidity;
        }
      }
    }

    return RigidityMap(
      values: values,
      width: width,
      height: height,
      imageSize: imageSize,
      maxValue: maxValue,
      hadLines: lines.hasLines,
    );
  }

  double _smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}
