import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/occlusion_map.dart';

/// Tipos de oclusor que o motor sabe preservar.
enum OccluderKind {
  leftHand,
  rightHand,
  leftArm,
  rightArm,
  hair,
  foregroundObject,
  unknown,
}

/// Extensão operacional do [OcclusionMap] de transporte (Sprint 2).
///
/// Mantém pesos 0–255 e opcionalmente um mapa de classes de oclusor.
class OcclusionField {
  final OcclusionMap map;
  final Uint8List? kindCodes;
  final Set<OccluderKind> presentKinds;
  final String reason;

  const OcclusionField({
    required this.map,
    this.kindCodes,
    this.presentKinds = const {},
    this.reason = 'occlusion_detected',
  });

  int get width => map.width;
  int get height => map.height;
  bool get isEmpty => map.isEmpty;
  double get confidence => map.confidence;
  String get providerId => map.providerId;

  factory OcclusionField.fromMap(
    OcclusionMap map, {
    Uint8List? kindCodes,
    Set<OccluderKind>? presentKinds,
    String reason = 'occlusion_detected',
  }) {
    final kinds = presentKinds ??
        (kindCodes == null
            ? (map.isEmpty ? const <OccluderKind>{} : {OccluderKind.unknown})
            : {
                for (final code in kindCodes)
                  if (code > 0 && code <= OccluderKind.values.length)
                    OccluderKind.values[code - 1],
              });
    return OcclusionField(
      map: map,
      kindCodes: kindCodes,
      presentKinds: kinds,
      reason: reason,
    );
  }

  /// Peso normalizado [0,1] em coordenadas da imagem.
  double sampleNormalized(double nx, double ny) {
    if (isEmpty) {
      return 0;
    }
    final values = map.weights;
    final width = map.width;
    final height = map.height;
    final fx = (nx.clamp(0.0, 1.0) * (width - 1));
    final fy = (ny.clamp(0.0, 1.0) * (height - 1));
    final x0 = fx.floor().clamp(0, width - 1);
    final y0 = fy.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final tx = fx - x0;
    final ty = fy - y0;

    final v00 = values[y0 * width + x0] / 255.0;
    final v10 = values[y0 * width + x1] / 255.0;
    final v01 = values[y1 * width + x0] / 255.0;
    final v11 = values[y1 * width + x1] / 255.0;
    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }

  OccluderKind kindAtNormalized(double nx, double ny) {
    if (kindCodes == null || isEmpty) {
      return presentKinds.isEmpty ? OccluderKind.unknown : presentKinds.first;
    }
    final x = (nx.clamp(0.0, 1.0) * (width - 1)).round().clamp(0, width - 1);
    final y = (ny.clamp(0.0, 1.0) * (height - 1)).round().clamp(0, height - 1);
    final code = kindCodes![y * width + x];
    if (code <= 0 || code > OccluderKind.values.length) {
      return OccluderKind.unknown;
    }
    return OccluderKind.values[code - 1];
  }

  /// Fração da ROI coberta por oclusão (média dos pesos > limiar).
  double overlapRatioInNormalizedRect(Rect rect, {double threshold = 0.2}) {
    if (isEmpty) {
      return 0;
    }
    final x0 = (rect.left.clamp(0.0, 1.0) * (width - 1)).floor();
    final y0 = (rect.top.clamp(0.0, 1.0) * (height - 1)).floor();
    final x1 = (rect.right.clamp(0.0, 1.0) * (width - 1)).ceil();
    final y1 = (rect.bottom.clamp(0.0, 1.0) * (height - 1)).ceil();
    var covered = 0;
    var total = 0;
    var weightSum = 0.0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        total++;
        final w = map.weights[y * width + x] / 255.0;
        weightSum += w;
        if (w >= threshold) {
          covered++;
        }
      }
    }
    if (total == 0) {
      return 0;
    }
    // Mistura cobertura binária e média contínua.
    return math.max(covered / total, weightSum / total);
  }

  static int codeFor(OccluderKind kind) => kind.index + 1;
}
