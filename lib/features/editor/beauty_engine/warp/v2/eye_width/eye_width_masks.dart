import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Ilhas do Largura do olho. Não altera [RegionMasks]. Não importa outros Fields.
///
/// Cada olho é um hull próprio. A sobrancelha e o nariz não se furam aqui:
/// o Field corta-os com a distância, senão a rampa media o vão e come a pálpebra.
class EyeWidthMasks {
  EyeWidthMasks({
    required this.width,
    required this.height,
    required this.photoLeft,
    required this.photoRight,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.hairline,
  });

  final int width;
  final int height;
  final Uint8List photoLeft;
  final Uint8List photoRight;
  final Uint8List brows;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List hairline;

  int get pixelCount => width * height;

  static const hairlineIds = [21, 103, 67, 109, 10, 338, 297, 332, 251];

  static EyeWidthMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required double hullPadFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = faceWidthOf(px);
    final pad = math.max(4, (hullPadFaceWidth * faceWidth).round());

    final photoLeft = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      photoLeft,
      width,
      height,
      _points(px, V2RegionCatalog.rightEye),
    );
    RegionMaskRaster.dilate(photoLeft, width, height, pad);

    final photoRight = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      photoRight,
      width,
      height,
      _points(px, V2RegionCatalog.leftEye),
    );
    RegionMaskRaster.dilate(photoRight, width, height, pad);

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

    final nose = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      nose,
      width,
      height,
      _points(px, V2RegionCatalog.nose),
    );
    final mouth = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      mouth,
      width,
      height,
      _points(px, V2RegionCatalog.lips),
    );

    final hairline = RegionMaskRaster.zeros(width, height);
    final hairRadius = 0.025 * faceWidth;
    for (final id in hairlineIds) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(hairline, width, height, p, hairRadius);
      }
    }

    return EyeWidthMasks(
      width: width,
      height: height,
      photoLeft: photoLeft,
      photoRight: photoRight,
      brows: brows,
      nose: nose,
      mouth: mouth,
      hairline: hairline,
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
