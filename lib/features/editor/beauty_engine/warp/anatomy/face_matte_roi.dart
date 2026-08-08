import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../body_reshape/maps/influence_map.dart';
import '../../filters/face/face_warp_utils.dart';
import '../../filters/face/skin_soft_region.dart';
import '../../mesh/mesh_topology.dart';
import '../../models/face_landmark.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../segment/person_mask.dart';

/// Matte ROI facial — warp só dentro do oval; fundo imóvel (Sprint 33).
abstract final class FaceMatteRoi {
  static InfluenceMap buildInfluenceMap({
    required FaceMeshResult face,
    required Size imageSize,
    PersonMask? personMask,
  }) {
    final minDim = math.min(imageSize.width, imageSize.height);
    final edge = (minDim / 6).round().clamp(128, 384);
    final width = edge;
    final height = edge;
    final values = Float32List(width * height);
    var maxValue = 0.0;

    final oval = _faceOvalEllipse(face);
    for (var y = 0; y < height; y++) {
      final ny = height == 1 ? 0.5 : y / (height - 1);
      for (var x = 0; x < width; x++) {
        final nx = width == 1 ? 0.5 : x / (width - 1);
        var w = 0.0;
        if (oval != null) {
          w = oval.weight(nx, ny, edgeFeather: 0.035);
        }
        if (personMask != null && personMask.bytes.isNotEmpty) {
          w *= personMask.sampleNormalized(nx, ny);
        }
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
      confidence: personMask == null ? 0.85 : 1.0,
      maxValue: maxValue,
    );
  }

  static NormalizedEllipse? _faceOvalEllipse(FaceMeshResult face) {
    final indices = MeshTopology.faceRegionLandmarks[MeshRegion.faceOval];
    if (indices == null) {
      return null;
    }
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
      radiusX: ((maxX - minX) / 2 + 0.012).clamp(0.05, 0.42),
      radiusY: ((maxY - minY) / 2 + 0.012).clamp(0.05, 0.48),
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
}
