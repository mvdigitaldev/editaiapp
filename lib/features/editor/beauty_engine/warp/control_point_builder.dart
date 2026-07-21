import 'dart:ui';

import '../mesh/mesh_topology.dart';
import '../models/mesh_region.dart';
import '../models/tri_mesh.dart';
import 'models/control_point.dart';

/// Constroi control points a partir de regioes da malha.
class ControlPointBuilder {
  const ControlPointBuilder();

  /// Pontos de ancoragem fixos (estabilizam MLS).
  static const _anchorLandmarkIndices = <int>[
    10, 338, 151, 9, 168, 1,
  ];

  List<ControlPoint> buildForRegion({
    required TriMesh mesh,
    required MeshRegion region,
    required double intensity,
    required Size imageSize,
  }) {
    if (intensity <= 0) {
      return const [];
    }

    return switch (region) {
      MeshRegion.jawLeft || MeshRegion.jawRight => _buildJawPoints(
          mesh: mesh,
          region: region,
          intensity: intensity,
          imageSize: imageSize,
        ),
      _ => _buildGenericRegionPoints(
          mesh: mesh,
          region: region,
          intensity: intensity,
          imageSize: imageSize,
        ),
    };
  }

  List<ControlPoint> _buildJawPoints({
    required TriMesh mesh,
    required MeshRegion region,
    required double intensity,
    required Size imageSize,
  }) {
    final points = <ControlPoint>[];
    final centerX = imageSize.width * 0.5;
    final maxShift = imageSize.width * 0.12 * intensity;

    for (final anchor in _anchorLandmarkIndices) {
      final source = _vertexAt(mesh, anchor);
      if (source != null) {
        points.add(ControlPoint(source: source, target: source));
      }
    }

    final jawIndices = MeshTopology.faceRegionLandmarks[region] ?? const {};
    for (final index in jawIndices) {
      final source = _vertexAt(mesh, index);
      if (source == null) {
        continue;
      }

      final towardCenter = centerX - source.dx;
      final shift = towardCenter.sign * maxShift * (towardCenter.abs() / (imageSize.width * 0.5));
      final target = Offset(source.dx + shift, source.dy);
      points.add(ControlPoint(source: source, target: target));
    }

    return points;
  }

  List<ControlPoint> _buildGenericRegionPoints({
    required TriMesh mesh,
    required MeshRegion region,
    required double intensity,
    required Size imageSize,
  }) {
    final indices = _uniqueVerticesFromRegion(mesh, region);
    if (indices.isEmpty) {
      return const [];
    }

    final points = <ControlPoint>[];
    for (final anchor in _anchorLandmarkIndices) {
      final source = _vertexAt(mesh, anchor);
      if (source != null) {
        points.add(ControlPoint(source: source, target: source));
      }
    }

    final center = Offset(imageSize.width * 0.5, imageSize.height * 0.5);
    for (final index in indices) {
      final source = _vertexAt(mesh, index);
      if (source == null) {
        continue;
      }
      final delta = Offset(
        (center.dx - source.dx) * 0.05 * intensity,
        (center.dy - source.dy) * 0.05 * intensity,
      );
      points.add(ControlPoint(source: source, target: source + delta));
    }
    return points;
  }

  Set<int> _uniqueVerticesFromRegion(TriMesh mesh, MeshRegion region) {
    final triangleIndices = mesh.regionIndices(region);
    final vertices = <int>{};
    for (var i = 0; i < triangleIndices.length; i++) {
      vertices.add(triangleIndices[i]);
    }
    return vertices;
  }

  Offset? _vertexAt(TriMesh mesh, int landmarkIndex) {
    if (landmarkIndex < 0 || landmarkIndex * 2 + 1 >= mesh.vertices.length) {
      return null;
    }
    return Offset(
      mesh.vertices[landmarkIndex * 2],
      mesh.vertices[landmarkIndex * 2 + 1],
    );
  }
}
