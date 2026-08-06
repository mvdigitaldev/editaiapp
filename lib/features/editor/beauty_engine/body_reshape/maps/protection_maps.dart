import 'dart:typed_data';
import 'dart:ui';

import 'signed_distance_field.dart';

/// Mapas que controlam o domínio de deformação a partir do matte.
///
/// Interior: peso ≈ confidence. Borda interna: feather.
/// Exterior próximo: banda de decaimento ([outerBandPx]) para arrastar
/// o fundo vizinho e evitar borda dupla / gap ao afinar.
class ProtectionMaps {
  final Float32List warpWeight;
  final Float32List transitionBand;
  final SignedDistanceField sdf;
  final Uint8List contour;
  final Rect boundingRegion;
  final double confidence;
  final int width;
  final int height;
  final double transitionPx;
  final double outerBandPx;

  const ProtectionMaps({
    required this.warpWeight,
    required this.transitionBand,
    required this.sdf,
    required this.contour,
    required this.boundingRegion,
    required this.confidence,
    required this.width,
    required this.height,
    required this.transitionPx,
    this.outerBandPx = 0,
  }) : assert(confidence >= 0 && confidence <= 1);

  bool get isEmpty => warpWeight.isEmpty || width <= 0 || height <= 0;

  /// Peso de warp em coordenadas normalizadas.
  /// Fora da banda exterior → 0; dentro da banda → decaimento suave.
  double sampleWarpWeight(double nx, double ny) {
    return _sampleFloat(warpWeight, nx, ny);
  }

  /// Intensidade da banda de transição (borda interna + exterior).
  double sampleTransition(double nx, double ny) {
    return _sampleFloat(transitionBand, nx, ny);
  }

  /// Distância assinada em px do matte (negativo = dentro).
  double sampleSdf(double nx, double ny) {
    if (sdf.isEmpty) {
      return 0;
    }
    return sdf.sampleNormalized(nx, ny);
  }

  bool isOutside(double nx, double ny, {double epsilon = 1e-4}) {
    return sampleWarpWeight(nx, ny) <= epsilon;
  }

  /// True se o ponto está além da banda exterior (fundo rígido).
  bool isFarBackground(double nx, double ny, {double epsilon = 1e-4}) {
    if (sdf.isEmpty) {
      return sampleWarpWeight(nx, ny) <= epsilon;
    }
    return sdf.sampleNormalized(nx, ny) > outerBandPx + epsilon;
  }

  double _sampleFloat(Float32List values, double nx, double ny) {
    if (isEmpty || values.length != width * height) {
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
}
