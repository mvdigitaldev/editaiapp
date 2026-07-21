import 'dart:math' as math;
import 'dart:ui';

import '../../mesh/mesh_topology.dart';
import '../../models/face_landmark.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import '../../warp/models/control_point.dart';

/// Utilitários compartilhados pelos filtros warp faciais (Sprint 10–13).
abstract final class FaceWarpUtils {
  static const anchorLandmarkIndices = <int>[
    10, 338, 151, 9, 168, 1,
  ];

  /// Íris MediaPipe (478 landmarks) — excluídos de warp ocular.
  static const irisLandmarkIndices = {
    468, 469, 470, 471, 472, 473, 474, 475, 476, 477,
  };

  static const upperEyelidLeft = {386, 385, 384, 398, 362, 466};
  static const upperEyelidRight = {159, 158, 157, 173, 133, 246};

  static const cheekboneLeft = {123, 147, 187, 116};
  static const cheekboneRight = {352, 411, 425, 345};

  static const mouthCornerLeft = {61, 78};
  static const mouthCornerRight = {291, 308};
  static const lipOuterUpper = {185, 40, 39, 37, 0, 267, 269, 270, 409};
  static const lipOuterLower = {146, 91, 181, 84, 17, 314, 405, 321, 375};

  /// Interior da boca — nunca warpar (protege dentes no smile).
  static const innerMouthExcluded = {
    13, 14, 87, 178, 88, 317, 402, 318, 324, 415, 310, 311, 312, 80, 81, 82, 191,
  };

  /// Reduz intensidade em perfil (evita over-warp).
  static double yawClampFactor(FaceMeshResult face) {
    final left = _landmark(face, 234);
    final right = _landmark(face, 454);
    if (left == null || right == null) {
      return 1;
    }
    final asymmetry = (left.z - right.z).abs();
    return (1 - asymmetry * 2.5).clamp(0.35, 1.0).toDouble();
  }

  static List<ControlPoint> anchorPoints(TriMesh mesh) {
    final points = <ControlPoint>[];
    for (final index in anchorLandmarkIndices) {
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

  static Offset? landmarkPoint(
    FaceMeshResult face,
    int index,
    Size imageSize,
  ) {
    final landmark = _landmark(face, index);
    if (landmark == null) {
      return null;
    }
    return Offset(
      landmark.normalized.dx * imageSize.width,
      landmark.normalized.dy * imageSize.height,
    );
  }

  static Offset noseAxisCenter(TriMesh mesh) {
    final points = [168, 1, 2, 4, 5]
        .map((i) => vertexAt(mesh, i))
        .whereType<Offset>()
        .toList();
    if (points.isEmpty) {
      return Offset.zero;
    }
    var x = 0.0;
    var y = 0.0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / points.length, y / points.length);
  }

  static Iterable<int> regionIndices(MeshRegion region) {
    return MeshTopology.faceRegionLandmarks[region] ?? const {};
  }

  static bool isIrisLandmark(int index) => irisLandmarkIndices.contains(index);

  static Offset? eyeCenter(TriMesh mesh, MeshRegion eyeRegion) {
    final indices = regionIndices(eyeRegion);
    var x = 0.0;
    var y = 0.0;
    var count = 0;
    for (final index in indices) {
      if (isIrisLandmark(index)) {
        continue;
      }
      final point = vertexAt(mesh, index);
      if (point == null) {
        continue;
      }
      x += point.dx;
      y += point.dy;
      count++;
    }
    if (count == 0) {
      return null;
    }
    return Offset(x / count, y / count);
  }

  static List<ControlPoint> scaleEyeRegion({
    required TriMesh mesh,
    required MeshRegion region,
    required double scale,
  }) {
    final center = eyeCenter(mesh, region);
    if (center == null) {
      return const [];
    }

    final points = <ControlPoint>[];
    for (final index in regionIndices(region)) {
      if (isIrisLandmark(index)) {
        continue;
      }
      final source = vertexAt(mesh, index);
      if (source == null) {
        continue;
      }
      final dx = source.dx - center.dx;
      final dy = source.dy - center.dy;
      points.add(
        ControlPoint(
          source: source,
          target: Offset(center.dx + dx * scale, center.dy + dy * scale),
        ),
      );
    }
    return points;
  }

  static List<ControlPoint> shiftEyeRegion({
    required TriMesh mesh,
    required MeshRegion region,
    required Offset delta,
  }) {
    final points = <ControlPoint>[];
    for (final index in regionIndices(region)) {
      if (isIrisLandmark(index)) {
        continue;
      }
      final source = vertexAt(mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: source + delta,
        ),
      );
    }
    return points;
  }

  static List<ControlPoint> rotateEyeRegion({
    required TriMesh mesh,
    required MeshRegion region,
    required double angleRadians,
  }) {
    final center = eyeCenter(mesh, region);
    if (center == null) {
      return const [];
    }

    final angle = angleRadians;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final points = <ControlPoint>[];

    for (final index in regionIndices(region)) {
      if (isIrisLandmark(index)) {
        continue;
      }
      final source = vertexAt(mesh, index);
      if (source == null) {
        continue;
      }
      final dx = source.dx - center.dx;
      final dy = source.dy - center.dy;
      points.add(
        ControlPoint(
          source: source,
          target: Offset(
            center.dx + dx * cosA - dy * sinA,
            center.dy + dx * sinA + dy * cosA,
          ),
        ),
      );
    }
    return points;
  }

  static Offset? lipCenter(TriMesh mesh) {
    final indices = {...lipOuterUpper, ...lipOuterLower};
    var x = 0.0;
    var y = 0.0;
    var count = 0;
    for (final index in indices) {
      if (innerMouthExcluded.contains(index)) {
        continue;
      }
      final point = vertexAt(mesh, index);
      if (point == null) {
        continue;
      }
      x += point.dx;
      y += point.dy;
      count++;
    }
    if (count == 0) {
      return null;
    }
    return Offset(x / count, y / count);
  }

  static List<ControlPoint> shiftLipIndices({
    required TriMesh mesh,
    required Set<int> indices,
    required Offset delta,
    Set<int> exclude = const {},
  }) {
    final points = <ControlPoint>[];
    for (final index in indices) {
      if (exclude.contains(index)) {
        continue;
      }
      final source = vertexAt(mesh, index);
      if (source == null) {
        continue;
      }
      points.add(ControlPoint(source: source, target: source + delta));
    }
    return points;
  }

  /// Regiões normalizadas (0–1) para overlay de pálpebra dupla.
  static List<Rect> eyeOverlayRegions(FaceMeshResult face, Size imageSize) {
    final regions = <Rect>[];
    for (final eyeIndices in [upperEyelidLeft, upperEyelidRight]) {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = double.negativeInfinity;
      var maxY = double.negativeInfinity;
      var count = 0;

      for (final index in eyeIndices) {
        final point = landmarkPoint(face, index, imageSize);
        if (point == null) {
          continue;
        }
        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
        count++;
      }

      if (count == 0) {
        continue;
      }

      final w = (maxX - minX).clamp(8.0, imageSize.width);
      final h = (maxY - minY).clamp(4.0, imageSize.height);
      regions.add(
        Rect.fromLTWH(
          (minX / imageSize.width).clamp(0.0, 1.0),
          (minY / imageSize.height).clamp(0.0, 1.0),
          (w / imageSize.width).clamp(0.01, 0.4),
          (h / imageSize.height).clamp(0.005, 0.2),
        ),
      );
    }
    return regions;
  }

  /// Highlight + shadow para contour de maçã do rosto (Sprint 14).
  static CheekboneContourRegions cheekboneContourRegions(
    FaceMeshResult face,
    Size imageSize,
  ) {
    final highlights = <Rect>[];
    final shadows = <Rect>[];

    for (final indices in [cheekboneLeft, cheekboneRight]) {
      final box = landmarkBounds(face, imageSize, indices);
      if (box == null) {
        continue;
      }
      final w = box.width / imageSize.width;
      final h = box.height / imageSize.height;
      final left = box.left / imageSize.width;
      final top = box.top / imageSize.height;

      highlights.add(
        Rect.fromLTWH(
          left.clamp(0.0, 1.0),
          top.clamp(0.0, 1.0),
          w.clamp(0.02, 0.25),
          (h * 0.55).clamp(0.01, 0.15),
        ),
      );
      shadows.add(
        Rect.fromLTWH(
          left.clamp(0.0, 1.0),
          (top + h * 0.35).clamp(0.0, 1.0),
          w.clamp(0.02, 0.25),
          (h * 0.65).clamp(0.01, 0.18),
        ),
      );
    }

    return CheekboneContourRegions(
      highlights: highlights,
      shadows: shadows,
    );
  }

  static Rect? landmarkBounds(
    FaceMeshResult face,
    Size imageSize,
    Set<int> indices,
  ) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var count = 0;

    for (final index in indices) {
      final point = landmarkPoint(face, index, imageSize);
      if (point == null) {
        continue;
      }
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
      count++;
    }

    if (count == 0) {
      return null;
    }

    return Rect.fromLTRB(
      minX,
      minY,
      maxX,
      maxY,
    );
  }

  static FaceLandmark? _landmark(FaceMeshResult face, int index) {
    for (final landmark in face.landmarks) {
      if (landmark.index == index) {
        return landmark;
      }
    }
    return null;
  }
}

/// Regiões normalizadas para highlight/shadow de maçã do rosto.
class CheekboneContourRegions {
  const CheekboneContourRegions({
    required this.highlights,
    required this.shadows,
  });

  final List<Rect> highlights;
  final List<Rect> shadows;
}
