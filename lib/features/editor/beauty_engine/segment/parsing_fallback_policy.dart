import 'dart:ui';

import '../filters/face/skin_mask_utils.dart';
import '../models/face_mesh_result.dart';
import 'face_parts_segmentation.dart';
import 'face_parsing_result.dart';

/// Decide se a segmentação semântica é confiável ou se o fallback geométrico
/// deve prevalecer (cap. Sprint 4 / ficha A1).
abstract final class ParsingFallbackPolicy {
  static const minFaceSkinCoverage = 0.005;

  static FaceParsingSource resolveSource({
    FacePartsSegmentation? parts,
    FaceMeshResult? face,
    bool bisenetAvailable = false,
  }) {
    if (bisenetAvailable) {
      return FaceParsingSource.bisenet;
    }
    if (parts != null &&
        !parts.isEmpty &&
        parts.coverageOf(FacePartClass.faceSkin) >= minFaceSkinCoverage) {
      return FaceParsingSource.mappedMulticlass;
    }
    if (face != null && !SkinMaskUtils.build(face, const Size(1, 1)).isEmpty) {
      return FaceParsingSource.geometric;
    }
    return FaceParsingSource.geometric;
  }

  static double confidenceFor({
    required FaceParsingSource source,
    FacePartsSegmentation? parts,
    FaceMeshResult? face,
  }) {
    switch (source) {
      case FaceParsingSource.bisenet:
        return 1;
      case FaceParsingSource.mappedMulticlass:
        if (parts == null || parts.isEmpty) return 0;
        final skin = parts.coverageOf(FacePartClass.faceSkin);
        final hair = parts.coverageOf(FacePartClass.hair);
        return (skin * 0.7 + hair * 0.3).clamp(0, 1);
      case FaceParsingSource.geometric:
        if (face == null) return 0;
        return face.confidence.clamp(0, 1);
    }
  }
}
