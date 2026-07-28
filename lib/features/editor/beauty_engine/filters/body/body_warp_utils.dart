import 'dart:math' as math;
import 'dart:ui';

import '../../mesh/mesh_topology.dart';
import '../../models/mesh_region.dart';
import '../../models/pose_landmark.dart';
import '../../models/pose_result.dart';
import '../../models/tri_mesh.dart';
import '../../segment/person_mask.dart';
import '../../warp/models/control_point.dart';

/// Utilitários warp corporais (MediaPipe Pose 33).
abstract final class BodyWarpUtils {
  static const visibilityThreshold = 0.5;

  /// Fração máxima da meia-largura local que o slim pode puxar (anti-fold).
  static const maxSlimFractionOfHalfWidth = 0.30;

  /// Sem PersonMask/matte, reduz intensidade para limitar artefatos de fundo.
  static const missingMatteIntensityScale = 0.65;

  static const anchorIndices = <int>[11, 12, 23, 24, 27, 28];

  /// Intensidade efetiva quando o domínio de proteção do matte não está disponível.
  static double intensityWithMatteGuard(
    double intensity, {
    PersonMask? personMask,
  }) {
    final clamped = intensity.clamp(0.0, 1.0);
    if (personMask != null) {
      return clamped;
    }
    return clamped * missingMatteIntensityScale;
  }

  static double poseConfidence(PoseResult pose, Set<int> indices) {
    if (indices.isEmpty) {
      return 1;
    }
    var sum = 0.0;
    var count = 0;
    for (final index in indices) {
      final landmark = _landmark(pose, index);
      if (landmark == null) {
        continue;
      }
      sum += landmark.visibility;
      count++;
    }
    if (count == 0) {
      return 0;
    }
    return (sum / count).clamp(0.0, 1.0);
  }

  static bool hasTorsoConfidence(PoseResult pose) {
    return poseConfidence(pose, {11, 12, 23, 24}) >= visibilityThreshold;
  }

  static bool hasLegConfidence(PoseResult pose) {
    return !pose.isPartial &&
        poseConfidence(pose, {23, 24, 25, 26, 27, 28}) >= visibilityThreshold;
  }

  /// Âncoras de identidade. [excludeIndices] evita conflito com pontos móveis.
  static List<ControlPoint> anchorPoints(
    TriMesh mesh, {
    Set<int> excludeIndices = const {},
  }) {
    final points = <ControlPoint>[];
    for (final index in anchorIndices) {
      if (excludeIndices.contains(index)) {
        continue;
      }
      final source = vertexAt(mesh, index);
      if (source != null) {
        points.add(ControlPoint(source: source, target: source));
      }
    }
    return points;
  }

  static Offset? vertexAt(TriMesh mesh, int landmarkIndex) {
    if (landmarkIndex < 0 || landmarkIndex * 2 + 1 >= mesh.vertices.length) {
      return null;
    }
    return Offset(
      mesh.vertices[landmarkIndex * 2],
      mesh.vertices[landmarkIndex * 2 + 1],
    );
  }

  static Iterable<int> regionIndices(MeshRegion region) {
    return MeshTopology.bodyRegionLandmarks[region] ?? const {};
  }

  static Offset clampToFrame(Offset target, Size imageSize,
      {double margin = 8}) {
    return Offset(
      target.dx.clamp(margin, imageSize.width - margin),
      target.dy.clamp(margin, imageSize.height - margin),
    );
  }

  /// Afina um segmento ósseo (ombro→cotovelo→punho etc.) estilo Liquify pro:
  /// pontos na borda estimada da silhueta são puxados para o eixo do osso.
  ///
  /// [limbHalfWidth] ~ metade da largura visual do membro.
  /// [shiftFraction] fração dessa largura a puxar (0–1).
  static List<ControlPoint> slimBoneSegment({
    required Offset proximal,
    required Offset distal,
    required Size imageSize,
    required double limbHalfWidth,
    required double shiftFraction,
    int samples = 5,
    bool freezeProximal = true,
    bool freezeDistal = false,
  }) {
    final shift = limbHalfWidth * shiftFraction.clamp(0.0, 1.0);
    if (shift < 0.5) {
      return const [];
    }

    final axis = distal - proximal;
    final len = axis.distance;
    if (len < 1) {
      return const [];
    }

    final dir = Offset(axis.dx / len, axis.dy / len);
    final normal = Offset(-dir.dy, dir.dx);
    final points = <ControlPoint>[];

    if (freezeProximal) {
      points.add(ControlPoint(source: proximal, target: proximal));
    }
    if (freezeDistal) {
      points.add(ControlPoint(source: distal, target: distal));
    }

    for (var i = 0; i < samples; i++) {
      final t = (i + 1) / (samples + 1);
      final center = Offset(
        proximal.dx + axis.dx * t,
        proximal.dy + axis.dy * t,
      );
      // Largura menor perto das articulações (cápsula).
      final radiusScale = 0.55 + 0.45 * math.sin(math.pi * t);
      final radius = limbHalfWidth * radiusScale;

      for (final side in [-1.0, 1.0]) {
        final edge = Offset(
          center.dx + normal.dx * radius * side,
          center.dy + normal.dy * radius * side,
        );
        final target = Offset(
          edge.dx - normal.dx * shift * side * radiusScale,
          edge.dy - normal.dy * shift * side * radiusScale,
        );
        points.add(
          ControlPoint(
            source: clampToFrame(edge, imageSize),
            target: clampToFrame(target, imageSize),
          ),
        );
      }
    }

    return points;
  }

  /// Afina torso/cintura: borda real (PersonMask) → centro.
  ///
  /// Usa esquerda/direita geométricas (menor/maior X), não labels MediaPipe.
  /// [profileFloor]/[profilePeak] controlam o peso ao longo do torso (t=0 ombro, t=1 quadril).
  static List<ControlPoint> slimTorsoSides({
    required Offset leftTop,
    required Offset rightTop,
    required Offset leftBottom,
    required Offset rightBottom,
    required Size imageSize,
    required double shiftPx,
    int samples = 6,
    PersonMask? personMask,
    double profileFloor = 0.55,
    double profilePeak = 1.0,
    double maxShiftFraction = maxSlimFractionOfHalfWidth,
  }) {
    if (shiftPx < 0.5) {
      return const [];
    }

    final points = <ControlPoint>[];
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final sideA = Offset(
        leftTop.dx + (leftBottom.dx - leftTop.dx) * t,
        leftTop.dy + (leftBottom.dy - leftTop.dy) * t,
      );
      final sideB = Offset(
        rightTop.dx + (rightBottom.dx - rightTop.dx) * t,
        rightTop.dy + (rightBottom.dy - rightTop.dy) * t,
      );

      final imageLeft = sideA.dx <= sideB.dx ? sideA : sideB;
      final imageRight = sideA.dx <= sideB.dx ? sideB : sideA;
      final midX = (imageLeft.dx + imageRight.dx) * 0.5;
      final y = imageLeft.dy;

      final profile =
          profileFloor + (profilePeak - profileFloor) * math.sin(math.pi * t);

      final edges = _torsoEdgesAtY(
        midX: midX,
        y: y,
        landmarkLeft: imageLeft,
        landmarkRight: imageRight,
        imageSize: imageSize,
        personMask: personMask,
      );
      final leftEdge = edges.$1;
      final rightEdge = edges.$2;
      final halfWidth = (rightEdge.dx - leftEdge.dx).abs() * 0.5;
      if (halfWidth < 2) {
        continue;
      }

      final localShift = math.min(
        shiftPx * profile,
        halfWidth * maxShiftFraction,
      );
      if (localShift < 0.5) {
        continue;
      }

      points.add(
        ControlPoint(
          source: clampToFrame(leftEdge, imageSize),
          target: clampToFrame(
            Offset(leftEdge.dx + localShift, leftEdge.dy),
            imageSize,
          ),
        ),
      );
      points.add(
        ControlPoint(
          source: clampToFrame(rightEdge, imageSize),
          target: clampToFrame(
            Offset(rightEdge.dx - localShift, rightEdge.dy),
            imageSize,
          ),
        ),
      );

      final center = Offset(midX, y);
      points.add(ControlPoint(source: center, target: center));
    }

    return points;
  }

  /// Expande/contrai quadril nas bordas reais da silhueta.
  static List<ControlPoint> hipSidePoints({
    required Offset landmarkA,
    required Offset landmarkB,
    required Size imageSize,
    required double shiftPx,
    PersonMask? personMask,
    double maxShiftFraction = maxSlimFractionOfHalfWidth,
  }) {
    if (shiftPx.abs() < 0.5) {
      return const [];
    }

    final imageLeft = landmarkA.dx <= landmarkB.dx ? landmarkA : landmarkB;
    final imageRight = landmarkA.dx <= landmarkB.dx ? landmarkB : landmarkA;
    final midX = (imageLeft.dx + imageRight.dx) * 0.5;
    final y = imageLeft.dy;

    final edges = _torsoEdgesAtY(
      midX: midX,
      y: y,
      landmarkLeft: imageLeft,
      landmarkRight: imageRight,
      imageSize: imageSize,
      personMask: personMask,
    );
    final leftEdge = edges.$1;
    final rightEdge = edges.$2;
    final halfWidth = (rightEdge.dx - leftEdge.dx).abs() * 0.5;
    final capped = math.min(shiftPx.abs(), halfWidth * maxShiftFraction);
    final signed = shiftPx >= 0 ? capped : -capped;

    return [
      ControlPoint(
        source: clampToFrame(leftEdge, imageSize),
        target: clampToFrame(
          Offset(leftEdge.dx - signed, leftEdge.dy),
          imageSize,
        ),
      ),
      ControlPoint(
        source: clampToFrame(rightEdge, imageSize),
        target: clampToFrame(
          Offset(rightEdge.dx + signed, rightEdge.dy),
          imageSize,
        ),
      ),
      ControlPoint(
        source: Offset(midX, y),
        target: Offset(midX, y),
      ),
    ];
  }

  /// Borda esquerda/direita em [y]: raycast na máscara ou fallback em landmarks.
  static (Offset, Offset) _torsoEdgesAtY({
    required double midX,
    required double y,
    required Offset landmarkLeft,
    required Offset landmarkRight,
    required Size imageSize,
    PersonMask? personMask,
  }) {
    if (personMask != null) {
      final left = findSilhouetteEdgeX(
        mask: personMask,
        imageSize: imageSize,
        midX: midX,
        y: y,
        findLeft: true,
      );
      final right = findSilhouetteEdgeX(
        mask: personMask,
        imageSize: imageSize,
        midX: midX,
        y: y,
        findLeft: false,
      );
      if (left != null && right != null && right > left + 4) {
        return (Offset(left, y), Offset(right, y));
      }
    }

    final halfWidth = (landmarkRight.dx - landmarkLeft.dx).abs() * 0.5;
    final edgePad = math.max(halfWidth * 0.12, imageSize.width * 0.01);
    return (
      Offset(landmarkLeft.dx - edgePad, y),
      Offset(landmarkRight.dx + edgePad, y),
    );
  }

  /// Percorre horizontalmente a partir do centro até a confiança cair abaixo do limiar.
  static double? findSilhouetteEdgeX({
    required PersonMask mask,
    required Size imageSize,
    required double midX,
    required double y,
    required bool findLeft,
    double threshold = 0.48,
  }) {
    if (imageSize.width <= 1 || imageSize.height <= 1) {
      return null;
    }

    final ny = (y / imageSize.height).clamp(0.0, 1.0);
    final startX = midX.clamp(0.0, imageSize.width - 1.0);
    final step = findLeft ? -1.0 : 1.0;
    final maxDist = imageSize.width * 0.48;

    // Garante que o meio está (aproximadamente) dentro da pessoa.
    final midV = mask.sampleNormalized(startX / imageSize.width, ny);
    if (midV < 0.2) {
      return null;
    }

    var lastInside = startX;
    for (var d = 0.0; d <= maxDist; d += 1.0) {
      final x = startX + step * d;
      if (x < 0 || x >= imageSize.width) {
        break;
      }
      final v = mask.sampleNormalized(x / imageSize.width, ny);
      if (v >= threshold) {
        lastInside = x;
      } else if (d > 2) {
        return lastInside;
      }
    }
    return lastInside;
  }

  /// Âncoras de fundo ao redor da região deformada (Freeze Mask do Liquify).
  static List<ControlPoint> backgroundFreezeRing({
    required List<ControlPoint> movable,
    required Size imageSize,
    double ringScale = 1.55,
  }) {
    if (movable.isEmpty) {
      return const [];
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in movable) {
      if (p.isAnchor) continue;
      minX = math.min(minX, p.source.dx);
      minY = math.min(minY, p.source.dy);
      maxX = math.max(maxX, p.source.dx);
      maxY = math.max(maxY, p.source.dy);
    }
    if (!minX.isFinite) {
      return const [];
    }

    final cx = (minX + maxX) * 0.5;
    final cy = (minY + maxY) * 0.5;
    final hw = math.max((maxX - minX) * 0.5 * ringScale, 24);
    final hh = math.max((maxY - minY) * 0.5 * ringScale, 24);

    final ring = <Offset>[
      Offset(cx - hw, cy - hh),
      Offset(cx, cy - hh),
      Offset(cx + hw, cy - hh),
      Offset(cx + hw, cy),
      Offset(cx + hw, cy + hh),
      Offset(cx, cy + hh),
      Offset(cx - hw, cy + hh),
      Offset(cx - hw, cy),
    ];

    return [
      for (final p in ring)
        ControlPoint(
          source: clampToFrame(p, imageSize),
          target: clampToFrame(p, imageSize),
        ),
    ];
  }

  /// Escala o deslocamento de cada CP móvel (multi-pass).
  static List<ControlPoint> scaleControlPointDeltas(
    List<ControlPoint> points,
    double factor,
  ) {
    if (factor >= 0.999) {
      return points;
    }
    return [
      for (final p in points)
        p.isAnchor
            ? p
            : ControlPoint(
                source: p.source,
                target: Offset(
                  p.source.dx + (p.target.dx - p.source.dx) * factor,
                  p.source.dy + (p.target.dy - p.source.dy) * factor,
                ),
              ),
    ];
  }

  static PoseLandmark? _landmark(PoseResult pose, int index) {
    for (final landmark in pose.landmarks) {
      if (landmark.index == index) {
        return landmark;
      }
    }
    return null;
  }
}
