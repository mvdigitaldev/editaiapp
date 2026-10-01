import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Ilha do Sorriso. Não altera [RegionMasks]. Não importa outros Fields.
///
/// Nariz, queixo, olhos e sobrancelha não se furam aqui: o Field corta-os
/// com a distância, senão a rampa media o vão e come o lábio.
class LipSmileMasks {
  LipSmileMasks({
    required this.width,
    required this.height,
    required this.lips,
    required this.nose,
    required this.chin,
    required this.eyes,
    required this.brows,
  });

  final int width;
  final int height;
  final Uint8List lips;
  final Uint8List nose;
  final Uint8List chin;
  final Uint8List eyes;
  final Uint8List brows;

  int get pixelCount => width * height;

  static const chinLandmarks = {152, 175, 199, 208, 171, 140, 176, 148, 149, 150};

  static LipSmileMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required double hullPadFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = faceWidthOf(px);
    final pad = math.max(4, (hullPadFaceWidth * faceWidth).round());

    final lips = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      lips,
      width,
      height,
      _points(px, V2RegionCatalog.lips),
    );
    RegionMaskRaster.dilate(lips, width, height, pad);

    final nose = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      nose,
      width,
      height,
      _points(px, V2RegionCatalog.nose),
    );

    final chin = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      chin,
      width,
      height,
      _points(px, chinLandmarks),
    );

    final eyes = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      eyes,
      width,
      height,
      _points(px, V2RegionCatalog.rightEye),
    );
    RegionMaskRaster.fillConvexHull(
      eyes,
      width,
      height,
      _points(px, V2RegionCatalog.leftEye),
    );

    final brows = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      brows,
      width,
      height,
      _points(px, V2RegionCatalog.browRight),
    );
    RegionMaskRaster.fillConvexHull(
      brows,
      width,
      height,
      _points(px, V2RegionCatalog.browLeft),
    );

    return LipSmileMasks(
      width: width,
      height: height,
      lips: lips,
      nose: nose,
      chin: chin,
      eyes: eyes,
      brows: brows,
    );
  }

  static Offset? centroid(List<Offset?> px) {
    final pts = _points(px, V2RegionCatalog.lips);
    if (pts.isEmpty) {
      return null;
    }
    var sx = 0.0;
    var sy = 0.0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  static List<Offset?> landmarkPixels(FaceMeshResult face, Size imageSize) {
    final out =
        List<Offset?>.filled(FaceMeshResult.expectedLandmarkCount, null);
    for (final FaceLandmark lm in face.landmarks) {
      if (lm.index < 0 || lm.index >= out.length) {
        continue;
      }
      out[lm.index] = Offset(
        lm.normalized.dx * imageSize.width,
        lm.normalized.dy * imageSize.height,
      );
    }
    return out;
  }

  static List<Offset> _points(List<Offset?> px, Set<int> indices) {
    final out = <Offset>[];
    for (final id in indices) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        out.add(p);
      }
    }
    return out;
  }

  static double faceWidthOf(List<Offset?> px) {
    final oval = _points(px, V2RegionCatalog.faceOval);
    if (oval.isEmpty) {
      return 1.0;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return math.max(maxX - minX, 1.0);
  }
}
