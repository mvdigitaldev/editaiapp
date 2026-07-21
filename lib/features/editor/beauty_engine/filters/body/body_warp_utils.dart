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

  static List<ControlPoint> anchorPoints(TriMesh mesh) {
    final points = <ControlPoint>[];
    for (final index in anchorIndices) {
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

  static PoseLandmark? _landmark(PoseResult pose, int index) {
    for (final landmark in pose.landmarks) {
      if (landmark.index == index) {
        return landmark;
      }
    }
    return null;
  }
}
