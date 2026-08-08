import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../body_reshape/maps/influence_map.dart';
import '../../mesh/mesh_topology.dart';
import '../../models/face_landmark.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import 'face_warp_region.dart';
import 'face_warp_utils.dart';
import 'skin_soft_region.dart';

/// Rasteriza mapas de influência 0–1 por região facial (Sprint 8).
abstract final class FaceInfluenceMapBuilder {
  static int _mapShortEdge(Size imageSize) {
    final minDim = math.min(imageSize.width, imageSize.height);
    return (minDim / 6).round().clamp(128, 384);
  }

  static InfluenceMap build({
    required FaceWarpRegion region,
    required FaceMeshResult face,
    required Size imageSize,
  }) {
    final size = _resolveMapSize(imageSize);
    final width = size.width.toInt();
    final height = size.height.toInt();
    if (width <= 0 || height <= 0) {
      return _empty(imageSize);
    }

    final values = Float32List(width * height);
    var maxValue = 0.0;

    for (var y = 0; y < height; y++) {
      final ny = height == 1 ? 0.5 : y / (height - 1);
      for (var x = 0; x < width; x++) {
        final nx = width == 1 ? 0.5 : x / (width - 1);
        final w = _weightAt(region: region, face: face, nx: nx, ny: ny);
        final idx = y * width + x;
        values[idx] = w;
        if (w > maxValue) {
          maxValue = w;
        }
      }
    }

    return InfluenceMap(
      values: values,
      width: width,
      height: height,
      imageSize: imageSize,
      regions: const {},
      confidence: 1,
      maxValue: maxValue,
    );
  }

  static double _weightAt({
    required FaceWarpRegion region,
    required FaceMeshResult face,
    required double nx,
    required double ny,
  }) {
    switch (region) {
      case FaceWarpRegion.lowerFace:
        return _lowerFaceWeight(face, nx, ny);
      case FaceWarpRegion.midFace:
        return _midFaceWeight(face, nx, ny);
      case FaceWarpRegion.eyes:
        return _eyesWeight(face, nx, ny);
      case FaceWarpRegion.mouth:
        return _mouthWeight(face, nx, ny);
      case FaceWarpRegion.cheek:
        return _cheekWeight(face, nx, ny);
      case FaceWarpRegion.contour:
        return _contourWeight(face, nx, ny);
    }
  }

  static double _lowerFaceWeight(FaceMeshResult face, double nx, double ny) {
    final mouthY = _landmarkNy(face, 13) ?? _landmarkNy(face, 14);
    if (mouthY != null && ny < mouthY - 0.015) {
      return 0;
    }

    final jawEllipse = _ellipseFromIndices(
      face,
      {
        ...MeshTopology.faceRegionLandmarks[MeshRegion.jawLeft]!,
        ...MeshTopology.faceRegionLandmarks[MeshRegion.jawRight]!,
        ...MeshTopology.faceRegionLandmarks[MeshRegion.leftCheek]!,
        ...MeshTopology.faceRegionLandmarks[MeshRegion.rightCheek]!,
        152, 175, 199, 200, 18,
      },
      padX: 0.035,
      padY: 0.04,
    );
    if (jawEllipse == null) {
      return 0;
    }
    return jawEllipse.weight(nx, ny, edgeFeather: 0.06);
  }

  static double _midFaceWeight(FaceMeshResult face, double nx, double ny) {
    final noseEllipse = _ellipseFromIndices(
      face,
      MeshTopology.faceRegionLandmarks[MeshRegion.nose]!,
      padX: 0.025,
      padY: 0.035,
    );
    if (noseEllipse == null) {
      return 0;
    }
    return noseEllipse.weight(nx, ny, edgeFeather: 0.05);
  }

  static double _eyesWeight(FaceMeshResult face, double nx, double ny) {
    final left = _ellipseFromIndices(
      face,
      MeshTopology.faceRegionLandmarks[MeshRegion.leftEye]!,
      padX: 0.032,
      padY: 0.022,
    );
    final right = _ellipseFromIndices(
      face,
      MeshTopology.faceRegionLandmarks[MeshRegion.rightEye]!,
      padX: 0.032,
      padY: 0.022,
    );
    var w = 0.0;
    if (left != null) {
      w = math.max(w, left.weight(nx, ny, edgeFeather: 0.075));
    }
    if (right != null) {
      w = math.max(w, right.weight(nx, ny, edgeFeather: 0.075));
    }
    // Ponte nasal suave entre os olhos (evita degrau no centro).
    if (w > 0 && w < 0.35) {
      final bridge = _ellipseFromIndices(
        face,
        {168, 6, 197, 195, 5, 4},
        padX: 0.04,
        padY: 0.025,
      );
      if (bridge != null) {
        w = math.max(w, bridge.weight(nx, ny, edgeFeather: 0.08) * 0.45);
      }
    }
    return w;
  }

  static double _mouthWeight(FaceMeshResult face, double nx, double ny) {
    final lips = _ellipseFromIndices(
      face,
      MeshTopology.faceRegionLandmarks[MeshRegion.lips]!,
      padX: 0.02,
      padY: 0.018,
    );
    if (lips == null) {
      return 0;
    }
    return lips.weight(nx, ny, edgeFeather: 0.045);
  }

  static double _cheekWeight(FaceMeshResult face, double nx, double ny) {
    final left = _ellipseFromIndices(
      face,
      FaceWarpUtils.cheekboneLeft,
      padX: 0.035,
      padY: 0.028,
    );
    final right = _ellipseFromIndices(
      face,
      FaceWarpUtils.cheekboneRight,
      padX: 0.035,
      padY: 0.028,
    );
    var w = 0.0;
    if (left != null) {
      w = math.max(w, left.weight(nx, ny, edgeFeather: 0.05));
    }
    if (right != null) {
      w = math.max(w, right.weight(nx, ny, edgeFeather: 0.05));
    }
    return w;
  }

  static double _contourWeight(FaceMeshResult face, double nx, double ny) {
    final oval = _ellipseFromIndices(
      face,
      MeshTopology.faceRegionLandmarks[MeshRegion.faceOval]!,
      padX: 0.01,
      padY: 0.01,
    );
    if (oval == null) {
      return 0;
    }
    var w = oval.weight(nx, ny, edgeFeather: 0.04);
    w *= 1 -
        math.max(
          _eyesWeight(face, nx, ny),
          _mouthWeight(face, nx, ny),
        );
    return w.clamp(0.0, 1.0);
  }

  static NormalizedEllipse? _ellipseFromIndices(
    FaceMeshResult face,
    Set<int> indices, {
    required double padX,
    required double padY,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var count = 0;

    for (final index in indices) {
      final lm = _landmark(face, index);
      if (lm == null) {
        continue;
      }
      minX = math.min(minX, lm.normalized.dx);
      minY = math.min(minY, lm.normalized.dy);
      maxX = math.max(maxX, lm.normalized.dx);
      maxY = math.max(maxY, lm.normalized.dy);
      count++;
    }
    if (count < 2) {
      return null;
    }

    return NormalizedEllipse(
      center: Offset((minX + maxX) / 2, (minY + maxY) / 2),
      radiusX: ((maxX - minX) / 2 + padX).clamp(0.012, 0.35),
      radiusY: ((maxY - minY) / 2 + padY).clamp(0.012, 0.35),
    );
  }

  static FaceLandmark? _landmark(FaceMeshResult face, int index) {
    for (final lm in face.landmarks) {
      if (lm.index == index) {
        return lm;
      }
    }
    return null;
  }

  static double? _landmarkNy(FaceMeshResult face, int index) {
    return _landmark(face, index)?.normalized.dy;
  }

  static Size _resolveMapSize(Size imageSize) {
    final minDim = math.min(imageSize.width, imageSize.height);
    if (minDim <= 0) {
      return Size.zero;
    }
    final scale = _mapShortEdge(imageSize) / minDim;
    return Size(
      (imageSize.width * scale).round().clamp(8, 256).toDouble(),
      (imageSize.height * scale).round().clamp(8, 256).toDouble(),
    );
  }

  static InfluenceMap _empty(Size imageSize) {
    return InfluenceMap(
      values: Float32List(0),
      width: 0,
      height: 0,
      imageSize: imageSize,
      regions: const {},
      confidence: 1,
      maxValue: 0,
    );
  }
}
