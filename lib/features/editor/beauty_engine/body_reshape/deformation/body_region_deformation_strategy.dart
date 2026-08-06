import 'dart:typed_data';
import 'dart:ui';

import '../maps/torso_contour_profile.dart';
import '../mesh/adaptive_body_mesh.dart';
import '../models/body_adjustment.dart';
import '../models/body_frame_assets.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';

/// Contexto compartilhado pelas estratégias regionais V2.
class RegionDeformationContext {
  final AdaptiveBodyMesh mesh;
  final BodyFrameAssets assets;
  final BodyAdjustment adjustment;
  final Size imageSize;
  final TorsoContourProfile? torsoContour;

  /// Escala global de segurança (máscara fraca / oclusão / corpo parcial).
  final double safetyScale;

  const RegionDeformationContext({
    required this.mesh,
    required this.assets,
    required this.adjustment,
    required this.imageSize,
    this.torsoContour,
    this.safetyScale = 1,
  });

  double get intensity {
    final raw = (adjustment.effectiveIntensity * safetyScale.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    // Quase linear: o slider precisa responder desde os primeiros 20%.
    return raw * (0.82 + 0.18 * raw);
  }

  Offset? landmarkPx(BodyJoint joint) {
    final landmark = assets.landmark(joint);
    if (landmark == null) {
      return null;
    }
    return Offset(
      landmark.normalized.dx * imageSize.width,
      landmark.normalized.dy * imageSize.height,
    );
  }

  bool regionMatches(BodyRegion region) => adjustment.regions.contains(region);
}

/// Estratégia semântica: escreve deltas de vértice sem control points.
abstract class BodyRegionDeformationStrategy {
  const BodyRegionDeformationStrategy();

  /// Tipos de ajuste que esta estratégia sabe aplicar.
  Set<BodyAdjustmentType> get supportedTypes;

  /// Acumula deslocamentos em [deltas] (dx, dy intercalados).
  void apply({
    required RegionDeformationContext context,
    required Float32List deltas,
  });
}

/// Utilitários geométricos compartilhados pelas estratégias.
mixin RegionDeformationMath on BodyRegionDeformationStrategy {
  void accumulateDelta(
    Float32List deltas,
    int vertexIndex,
    double dx,
    double dy,
    double weight,
  ) {
    if (weight <= 0) {
      return;
    }
    deltas[vertexIndex * 2] += dx * weight;
    deltas[vertexIndex * 2 + 1] += dy * weight;
  }

  /// Confiança do contorno como atenuação suave.
  ///
  /// Usar a confiança como fator direto derruba o deslocamento a ~1/3 do alvo
  /// mesmo com contorno bom; aqui ela só modula a faixa [floor, 1].
  double softConfidence(double? confidence, {double floor = 0.7}) {
    final c = (confidence ?? 0.5).clamp(0.0, 1.0);
    return floor + (1 - floor) * c;
  }

  /// Peso de deformabilidade do vértice como atenuação suave.
  double softVertexWeight(double weight, {double floor = 0.55}) {
    return floor + (1 - floor) * weight.clamp(0.0, 1.0);
  }

  double falloffAlongAxis({
    required Offset point,
    required Offset a,
    required Offset b,
    required double halfWidth,
  }) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) {
      return 0;
    }
    final t = (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    final dist = (point - closest).distance;
    if (dist >= halfWidth) {
      return 0;
    }
    final u = 1.0 - dist / halfWidth;
    return u * u * (3 - 2 * u);
  }

  Offset inwardNormalTowardAxis({
    required Offset point,
    required Offset a,
    required Offset b,
  }) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) {
      return Offset.zero;
    }
    final t = (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    final toAxis = closest - point;
    final dist = toAxis.distance;
    if (dist < 1e-6) {
      return Offset.zero;
    }
    return Offset(toAxis.dx / dist, toAxis.dy / dist);
  }

  Offset horizontalOutwardFromMidline({
    required Offset point,
    required double midlineX,
  }) {
    final dx = point.dx - midlineX;
    if (dx.abs() < 1e-6) {
      return Offset.zero;
    }
    return Offset(dx.sign, 0);
  }
}
