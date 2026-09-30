import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Ilha da Ponte do dorso. Não altera [RegionMasks]. Não importa outros Fields.
///
/// Olhos, boca e sobrancelha não se furam aqui: o Field corta-os com a
/// distância, senão a rampa media o vão e come o dorso.
class NoseBridgeMasks {
  NoseBridgeMasks({
    required this.width,
    required this.height,
    required this.nose,
    required this.eyes,
    required this.brows,
    required this.mouth,
  });

  final int width;
  final int height;
  final Uint8List nose;
  final Uint8List eyes;
  final Uint8List brows;
  final Uint8List mouth;

  int get pixelCount => width * height;

  static NoseBridgeMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required double hullPadFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = faceWidthOf(px);
    final pad = math.max(4, (hullPadFaceWidth * faceWidth).round());

    final nose = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      nose,
      width,
      height,
      _points(px, V2RegionCatalog.nose),
    );
    RegionMaskRaster.dilate(nose, width, height, pad);

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

    final mouth = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      mouth,
      width,
      height,
      _points(px, V2RegionCatalog.lips),
    );

    return NoseBridgeMasks(
      width: width,
      height: height,
      nose: nose,
      eyes: eyes,
      brows: brows,
      mouth: mouth,
    );
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
