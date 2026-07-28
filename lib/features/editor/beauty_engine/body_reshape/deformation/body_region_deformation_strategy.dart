import 'dart:typed_data';
import 'dart:ui';

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

  const RegionDeformationContext({
    required this.mesh,
    required this.assets,
    required this.adjustment,
    required this.imageSize,
  });

  double get intensity {
    final raw = adjustment.effectiveIntensity;
    // Smoothstep — evita over-deformação nos extremos.
    return raw * raw * (3 - 2 * raw);
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
