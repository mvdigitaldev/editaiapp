import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Máscaras do Eyebrow Height. Não altera [RegionMasks] (contrato Jaw).
///
/// Os olhos **não** são furados no domínio: a rampa de bordo mediria o vão e
/// comia o planalto. O `lidGate` no Field zera a pálpebra.
class EyebrowHeightMasks {
  EyebrowHeightMasks({
    required this.width,
    required this.height,
    required this.brow,
    required this.browActive,
    required this.eyes,
    required this.nose,
    required this.mouth,
    required this.hairline,
  });

  final int width;
  final int height;
  final Uint8List brow;
  final Uint8List browActive;
  final Uint8List eyes;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List hairline;

  int get pixelCount => width * height;

  int count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }

  static const hairlineIds = [21, 103, 67, 109, 10, 338, 297, 332, 251];

  /// Terço externo da pálpebra superior. O hull do olho pára no cílio;
  /// a dobra (vão cauda da brow → canto) fica de fora e o pad puxava-a.
  static const outerLidLeft = {263, 466, 388};
  static const outerLidRight = {33, 246, 161};

  static EyebrowHeightMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required double hullPadFaceWidth,
    required double outerLidLiftFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = faceWidthOf(px);

    final brow = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.fillConvexHull(
      brow,
      width,
      height,
      _points(px, V2RegionCatalog.browLeft),
    );
    RegionMaskRaster.fillConvexHull(
      brow,
      width,
      height,
      _points(px, V2RegionCatalog.browRight),
    );
    final pad = math.max(6, (hullPadFaceWidth * faceWidth).round());
    RegionMaskRaster.dilate(brow, width, height, pad);

    final eyes = RegionMaskRaster.zeros(width, height);
    final eyePts = [
      ..._points(px, V2RegionCatalog.eyes),
      ..._liftedOuterLid(px, outerLidLiftFaceWidth * faceWidth),
      ..._outerCreaseShelf(px),
    ];
    RegionMaskRaster.fillConvexHull(eyes, width, height, eyePts);
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

    // O domínio é a ilha dilatada. Olhos e L não se furam aqui.
    final browActive = Uint8List.fromList(brow);

    return EyebrowHeightMasks(
      width: width,
      height: height,
      brow: brow,
      browActive: browActive,
      eyes: eyes,
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

  /// Do canto (33/263) para a cauda (70/300), para antes do pelo.
  static const _outerCrease = [(70, 33), (300, 263)];

  static List<Offset> _outerCreaseShelf(List<Offset?> px) {
    final out = <Offset>[];
    for (final pair in _outerCrease) {
      final tail = pair.$1 < px.length ? px[pair.$1] : null;
      final canthus = pair.$2 < px.length ? px[pair.$2] : null;
      if (tail == null || canthus == null) {
        continue;
      }
      for (final t in const [0.30, 0.45, 0.58]) {
        out.add(
          Offset(
            canthus.dx + t * (tail.dx - canthus.dx),
            canthus.dy + t * (tail.dy - canthus.dy),
          ),
        );
      }
    }
    return out;
  }

  static List<Offset> _liftedOuterLid(List<Offset?> px, double lift) {
    if (lift <= 1e-6) {
      return const [];
    }
    final out = <Offset>[];
    for (final id in [...outerLidLeft, ...outerLidRight]) {
      final p = id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      out.add(Offset(p.dx, p.dy - lift));
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
