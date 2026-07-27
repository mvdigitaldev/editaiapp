import 'dart:math' as math;
import 'dart:ui';

import '../../mesh/mesh_topology.dart';
import '../../models/mesh_region.dart';
import '../../models/pose_landmark.dart';
import '../../models/pose_result.dart';
import '../../models/tri_mesh.dart';
import '../../warp/models/control_point.dart';

/// Utilitários warp corporais (MediaPipe Pose 33).
abstract final class BodyWarpUtils {
  static const visibilityThreshold = 0.5;

  static const anchorIndices = <int>[11, 12, 23, 24, 27, 28];

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

  static Offset clampToFrame(Offset target, Size imageSize, {double margin = 8}) {
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

  /// Afina torso/cintura: borda lateral estimada → centro.
  static List<ControlPoint> slimTorsoSides({
    required Offset leftTop,
    required Offset rightTop,
    required Offset leftBottom,
    required Offset rightBottom,
    required Size imageSize,
    required double shiftPx,
    int samples = 6,
  }) {
    if (shiftPx < 0.5) {
      return const [];
    }

    final points = <ControlPoint>[];
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final left = Offset(
        leftTop.dx + (leftBottom.dx - leftTop.dx) * t,
        leftTop.dy + (leftBottom.dy - leftTop.dy) * t,
      );
      final right = Offset(
        rightTop.dx + (rightBottom.dx - rightTop.dx) * t,
        rightTop.dy + (rightBottom.dy - rightTop.dy) * t,
      );
      final midX = (left.dx + right.dx) * 0.5;
      // Mais forte no meio (cintura), mais suave nos extremos.
      final waistWeight = 0.55 + 0.45 * math.sin(math.pi * t);
      final localShift = shiftPx * waistWeight;

      // Pontos na silhueta estimada (um pouco fora do esqueleto).
      final halfWidth = (right.dx - left.dx).abs() * 0.5;
      final edgePad = math.max(halfWidth * 0.35, imageSize.width * 0.02);

      final leftEdge = Offset(left.dx - edgePad, left.dy);
      final rightEdge = Offset(right.dx + edgePad, right.dy);

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

      // Âncora no eixo para o MLS não dobrar o centro.
      final center = Offset(midX, left.dy);
      points.add(ControlPoint(source: center, target: center));
    }

    return points;
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

  static PoseLandmark? _landmark(PoseResult pose, int index) {
    for (final landmark in pose.landmarks) {
      if (landmark.index == index) {
        return landmark;
      }
    }
    return null;
  }
}
