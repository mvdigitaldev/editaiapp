import 'dart:ui';

import '../../models/face_mesh_result.dart';
import 'face_warp_utils.dart';

/// Máscaras faciais para skin engine (face oval − olhos/boca).
class SkinProcessingMask {
  const SkinProcessingMask({
    required this.faceBounds,
    required this.protectedRegions,
    required this.cheekRegions,
    required this.underEyeRegions,
    required this.eyebrowRegions,
    required this.eyelashRegions,
    required this.innerMouthRegions,
    required this.foreheadRegions,
    required this.contourRegions,
  });

  final Rect faceBounds;
  final List<Rect> protectedRegions;
  final List<Rect> cheekRegions;
  final List<Rect> underEyeRegions;
  final List<Rect> eyebrowRegions;
  final List<Rect> eyelashRegions;
  final List<Rect> innerMouthRegions;
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
      underEyeRegions: [underEyeLeft, underEyeRight].where((r) => !r.isEmpty).toList(),
      eyebrowRegions: [leftBrow, rightBrow].where((r) => !r.isEmpty).toList(),
      eyelashRegions: [lashLeft, lashRight].where((r) => !r.isEmpty).toList(),
      innerMouthRegions: innerMouth.isEmpty ? const [] : [innerMouth],
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
