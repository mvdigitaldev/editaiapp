import 'dart:math' as math;
import 'dart:ui';

import '../../models/face_landmark.dart';
import '../../models/face_mesh_result.dart';
import 'face_warp_utils.dart';
import 'skin_soft_region.dart';

export 'skin_soft_region.dart';

/// Máscaras faciais para skin engine (face oval − olhos/boca).
class SkinProcessingMask {
  const SkinProcessingMask({
    required this.faceBounds,
    required this.protectedRegions,
    required this.cheekRegions,
    required this.cheekEllipses,
    required this.underEyeRegions,
    required this.underEyeEllipses,
    required this.eyebrowRegions,
    required this.eyelashRegions,
    required this.innerMouthRegions,
    required this.innerMouthEllipse,
    required this.foreheadRegions,
    required this.contourRegions,
  });

  final Rect faceBounds;
  final List<Rect> protectedRegions;
  final List<Rect> cheekRegions;
  final List<NormalizedEllipse> cheekEllipses;
  final List<Rect> underEyeRegions;
  final List<NormalizedEllipse> underEyeEllipses;
  final List<Rect> eyebrowRegions;
  final List<Rect> eyelashRegions;
  final List<Rect> innerMouthRegions;
  final NormalizedEllipse? innerMouthEllipse;
  final List<Rect> foreheadRegions;
  final List<Rect> contourRegions;

  bool get isEmpty => faceBounds.isEmpty;
}

/// Utilitários de máscara para skin/makeup (Sprint 17).
abstract final class SkinMaskUtils {
  static const _leftEyeIndices = {
    263, 249, 390, 373, 374, 380, 381, 382, 362, 466, 388, 387, 386, 385, 384, 398,
  };
  static const _rightEyeIndices = {
    33, 7, 163, 144, 145, 153, 154, 155, 133, 246, 161, 160, 159, 158, 157, 173,
  };
  static const _leftBrowIndices = {276, 283, 282, 295, 285, 336, 296, 334, 293, 300};
  static const _rightBrowIndices = {46, 53, 52, 65, 55, 107, 66, 105, 63, 70};
  static const _innerMouthIndices = {
    13, 14, 87, 178, 88, 317, 402, 318, 324, 415, 310, 311, 312, 80, 81, 82, 191,
  };

  static const _faceOvalIndices = {
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365,
    379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93,
    234, 127, 162, 21, 54, 103, 67, 109,
  };

  static SkinProcessingMask build(FaceMeshResult face, Size imageSize) {
    final faceBounds = _normalizeBounds(
      FaceWarpUtils.landmarkBounds(face, imageSize, _faceOvalIndices),
      imageSize,
      pad: 0,
    );

    final leftEye = _boundsForIndices(face, imageSize, _leftEyeIndices, pad: 0.08);
    final rightEye = _boundsForIndices(face, imageSize, _rightEyeIndices, pad: 0.08);
    final mouth = _boundsForIndices(face, imageSize, _innerMouthIndices, pad: 0.05);
    final leftBrow = _boundsForIndices(face, imageSize, _leftBrowIndices, pad: 0.04);
    final rightBrow = _boundsForIndices(face, imageSize, _rightBrowIndices, pad: 0.04);

    final protected = [leftEye, rightEye, mouth]
        .where((r) => !r.isEmpty)
        .toList();

    final leftCheekEllipse = _ellipseForIndices(
      face,
      FaceWarpUtils.cheekboneLeft,
      padX: 0.028,
      padY: 0.022,
    );
    final rightCheekEllipse = _ellipseForIndices(
      face,
      FaceWarpUtils.cheekboneRight,
      padX: 0.028,
      padY: 0.022,
    );

    final leftCheek = _boundsForIndices(
      face,
      imageSize,
      FaceWarpUtils.cheekboneLeft,
      pad: 0.12,
    );
    final rightCheek = _boundsForIndices(
      face,
      imageSize,
      FaceWarpUtils.cheekboneRight,
      pad: 0.12,
    );

    final leftEyeEllipse = _ellipseForIndices(
      face,
      _leftEyeIndices,
      padX: 0.012,
      padY: 0.010,
    );
    final rightEyeEllipse = _ellipseForIndices(
      face,
      _rightEyeIndices,
      padX: 0.012,
      padY: 0.010,
    );

    final underEyeEllipses = [
      if (leftEyeEllipse != null) _underEyeEllipse(leftEyeEllipse),
      if (rightEyeEllipse != null) _underEyeEllipse(rightEyeEllipse),
    ].where((e) => e.isValid).toList();

    final underEyeLeft = _underEyeRegion(leftEye);
    final underEyeRight = _underEyeRegion(rightEye);

    final lashLeft = _boundsForIndices(
      face,
      imageSize,
      FaceWarpUtils.upperEyelidLeft,
      pad: 0.02,
    );
    final lashRight = _boundsForIndices(
      face,
      imageSize,
      FaceWarpUtils.upperEyelidRight,
      pad: 0.02,
    );

    final innerMouth = _boundsForIndices(
      face,
      imageSize,
      _innerMouthIndices,
      pad: 0.02,
    );
    final innerMouthEllipse = _ellipseForIndices(
      face,
      _innerMouthIndices,
      padX: 0.028,
      padY: 0.022,
    );

    final forehead = _boundsForIndices(
      face,
      imageSize,
      ForeheadMaskIndices.lowerForehead,
      pad: 0.06,
    );

    final contourLeft = _boundsForIndices(
      face,
      imageSize,
      {234, 127, 162, 93},
      pad: 0.08,
    );
    final contourRight = _boundsForIndices(
      face,
      imageSize,
      {251, 284, 356, 389},
      pad: 0.08,
    );

    return SkinProcessingMask(
      faceBounds: faceBounds,
      protectedRegions: protected,
      cheekRegions: [leftCheek, rightCheek].where((r) => !r.isEmpty).toList(),
      cheekEllipses: [
        if (leftCheekEllipse != null) leftCheekEllipse,
        if (rightCheekEllipse != null) rightCheekEllipse,
      ].where((e) => e.isValid).toList(),
      underEyeRegions: [underEyeLeft, underEyeRight].where((r) => !r.isEmpty).toList(),
      underEyeEllipses: underEyeEllipses,
      eyebrowRegions: [leftBrow, rightBrow].where((r) => !r.isEmpty).toList(),
      eyelashRegions: [lashLeft, lashRight].where((r) => !r.isEmpty).toList(),
      innerMouthRegions: innerMouth.isEmpty ? const [] : [innerMouth],
      innerMouthEllipse: innerMouthEllipse,
      foreheadRegions: forehead.isEmpty ? const [] : [forehead],
      contourRegions: [contourLeft, contourRight].where((r) => !r.isEmpty).toList(),
    );
  }

  static bool isInNormalizedRect(double nx, double ny, Rect region) {
    return region.contains(Offset(nx, ny));
  }

  static bool isProtected(
    double nx,
    double ny,
    SkinProcessingMask mask, {
    double feather = 0.02,
  }) {
    for (final region in mask.protectedRegions) {
      if (region.inflate(feather).contains(Offset(nx, ny))) {
        return true;
      }
    }
    return false;
  }

  static double underEyeWeight(double nx, double ny, SkinProcessingMask mask) {
    var weight = 0.0;
    for (final ellipse in mask.underEyeEllipses) {
      weight = math.max(weight, ellipse.weight(nx, ny, edgeFeather: 0.055));
    }
    for (final region in mask.underEyeRegions) {
      weight = math.max(weight, softRectWeight(nx, ny, region, edgeFeather: 0.045));
    }
    return weight;
  }

  static double teethWhiteningWeight(
    double nx,
    double ny,
    SkinProcessingMask mask,
    int r,
    int g,
    int b,
  ) {
    final region = teethRegionWeight(nx, ny, mask);
    if (region <= 0) {
      return 0;
    }
    return region * teethPixelWeight(r, g, b);
  }

  static double teethRegionWeight(double nx, double ny, SkinProcessingMask mask) {
    var weight = 0.0;
    final ellipse = mask.innerMouthEllipse;
    if (ellipse != null && ellipse.isValid) {
      weight = math.max(weight, ellipse.weight(nx, ny, edgeFeather: 0.055));
    }
    for (final region in mask.innerMouthRegions) {
      weight = math.max(
        weight,
        softRectWeight(nx, ny, region, edgeFeather: 0.045),
      );
    }
    return weight;
  }

  /// Preferência por pixels claros; reduz lábios avermelhados sem bloquear dentes.
  static double teethPixelWeight(int r, int g, int b) {
    final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    final saturation =
        maxChannel == 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;

    if (r > g + 35 && r > b + 25 && luminance < 190) {
      return 0.3;
    }

    final lumFactor = ((luminance - 35) / 185).clamp(0.0, 1.0);
    final satFactor = ((0.72 - saturation) / 0.72).clamp(0.0, 1.0);
    return (0.55 + 0.45 * lumFactor * satFactor).clamp(0.55, 1.0);
  }

  static double softRegionsWeight(
    double nx,
    double ny,
    List<Rect> regions, {
    double edgeFeather = 0.025,
  }) {
    var weight = 0.0;
    for (final region in regions) {
      weight = math.max(
        weight,
        softRectWeight(nx, ny, region, edgeFeather: edgeFeather),
      );
    }
    return weight;
  }

  /// Blush via elipses nas maçãs, excluindo testa e olhos.
  static double blushWeight(
    double nx,
    double ny,
    SkinProcessingMask mask, {
    double skinWeight = 1.0,
  }) {
    if (skinWeight <= 0) {
      return 0;
    }
    for (final region in mask.foreheadRegions) {
      if (region.inflate(0.02).contains(Offset(nx, ny))) {
        return 0;
      }
    }
    if (isProtected(nx, ny, mask)) {
      return 0;
    }
    var weight = 0.0;
    for (final ellipse in mask.cheekEllipses) {
      weight = math.max(weight, ellipse.weight(nx, ny, edgeFeather: 0.07));
    }
    if (weight <= 0) {
      weight = softRegionsWeight(nx, ny, mask.cheekRegions, edgeFeather: 0.04);
    }
    return weight * skinWeight;
  }

  static double foreheadWeight(double nx, double ny, SkinProcessingMask mask) {
    return softRegionsWeight(nx, ny, mask.foreheadRegions, edgeFeather: 0.035);
  }

  static NormalizedEllipse? _ellipseForIndices(
    FaceMeshResult face,
    Set<int> indices, {
    double padX = 0.015,
    double padY = 0.015,
    double shrinkX = 1.0,
    double shrinkY = 1.0,
  }) {
    final points = <Offset>[];
    for (final index in indices) {
      final landmark = _landmarkAt(face, index);
      if (landmark != null) {
        points.add(landmark.normalized);
      }
    }
    if (points.length < 2) {
      return null;
    }

    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final point in points) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }

    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final radiusX = (((maxX - minX) / 2) + padX) * shrinkX;
    final radiusY = (((maxY - minY) / 2) + padY) * shrinkY;

    return NormalizedEllipse(
      center: center,
      radiusX: radiusX.clamp(0.008, 0.28),
      radiusY: radiusY.clamp(0.005, 0.22),
    );
  }

  static NormalizedEllipse _underEyeEllipse(NormalizedEllipse eye) {
    return NormalizedEllipse(
      center: Offset(
        eye.center.dx,
        eye.center.dy + eye.radiusY * 0.65,
      ),
      radiusX: eye.radiusX * 1.08,
      radiusY: eye.radiusY * 0.62,
    );
  }

  static FaceLandmark? _landmarkAt(FaceMeshResult face, int index) {
    if (index >= 0 &&
        index < face.landmarks.length &&
        face.landmarks[index].index == index) {
      return face.landmarks[index];
    }
    for (final landmark in face.landmarks) {
      if (landmark.index == index) {
        return landmark;
      }
    }
    return null;
  }

  static Rect _boundsForIndices(
    FaceMeshResult face,
    Size imageSize,
    Set<int> indices, {
    double pad = 0.05,
  }) {
    return _normalizeBounds(
      FaceWarpUtils.landmarkBounds(face, imageSize, indices),
      imageSize,
      pad: pad,
    );
  }

  static Rect _normalizeBounds(Rect? raw, Size imageSize, {required double pad}) {
    if (raw == null) {
      return Rect.zero;
    }
    final w = imageSize.width;
    final h = imageSize.height;
    return Rect.fromLTWH(
      ((raw.left / w) - pad).clamp(0.0, 1.0),
      ((raw.top / h) - pad).clamp(0.0, 1.0),
      ((raw.width / w) + pad * 2).clamp(0.01, 0.5),
      ((raw.height / h) + pad * 2).clamp(0.01, 0.5),
    );
  }

  static Rect _underEyeRegion(Rect eye) {
    if (eye.isEmpty) {
      return Rect.zero;
    }
    return Rect.fromLTWH(
      eye.left,
      eye.top + eye.height * 0.65,
      eye.width,
      eye.height * 0.55,
    );
  }
}

/// Índices compartilhados com forehead filter.
abstract final class ForeheadMaskIndices {
  static const lowerForehead = {297, 332, 109, 67, 103, 54, 21};
}
