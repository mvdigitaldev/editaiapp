import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../filters/face/skin/skin_weight_map.dart';
import '../filters/face/skin_mask_utils.dart';
import '../models/face_mesh_result.dart';
import 'face_parts_segmentation.dart';
import 'face_parsing_class.dart';
import 'face_parsing_result.dart';
import 'parsing_fallback_policy.dart';

/// Converte segmentação multiclass (6 classes) + landmarks → parsing 19 classes.
abstract final class FaceParsingMapper {
  static FaceParsingResult build({
    required int width,
    required int height,
    FacePartsSegmentation? parts,
    FaceMeshResult? face,
    SkinTileMapping mapping = const SkinTileMapping(),
    bool bisenetClasses = false,
    Uint8List? bisenetBuffer,
  }) {
    if (bisenetClasses && bisenetBuffer != null && bisenetBuffer.length == width * height) {
      return FaceParsingResult(
        classes: Uint8List.fromList(bisenetBuffer),
        width: width,
        height: height,
        source: FaceParsingSource.bisenet,
        confidence: 1,
      );
    }

    final source = ParsingFallbackPolicy.resolveSource(parts: parts, face: face);
    final confidence = ParsingFallbackPolicy.confidenceFor(
      source: source,
      parts: parts,
      face: face,
    );

    final pixels = width * height;
    if (pixels <= 0) {
      return FaceParsingResult(
        classes: Uint8List(0),
        width: width,
        height: height,
        source: source,
        confidence: confidence,
      );
    }

    final geometric =
        face != null ? SkinMaskUtils.build(face, Size(width.toDouble(), height.toDouble())) : null;
    final resolved = mapping.resolve(width, height);
    final classes = Uint8List(pixels);

    final useParts = source == FaceParsingSource.mappedMulticlass && parts != null;

    NormalizedEllipse? faceEllipse;
    Rect? gate;
    if (geometric != null && !geometric.isEmpty) {
      final bounds = geometric.faceBounds;
      faceEllipse = NormalizedEllipse(
        center: bounds.center,
        radiusX: bounds.width / 2,
        radiusY: bounds.height / 2,
      );
      gate = bounds.inflate(math.max(bounds.width, bounds.height) * 0.12);
    }

    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final nx = resolved.normalizedX(x);
        final index = y * width + x;

        final landmarkClass = _classFromLandmarks(nx, ny, geometric);
        if (landmarkClass != null) {
          classes[index] = landmarkClass.index;
          continue;
        }

        if (useParts) {
          final part = FacePartClass.fromIndex(parts!.classIndexAt(nx, ny));
          // Cabelo/roupa ficam fora do gate facial — não limitar ao bbox do rosto.
          if (part == FacePartClass.hair ||
              part == FacePartClass.clothes ||
              gate == null ||
              gate.contains(Offset(nx, ny))) {
            classes[index] = _mapPartClass(parts, nx, ny).index;
            continue;
          }
        }

        if (faceEllipse != null && faceEllipse.weight(nx, ny, edgeFeather: 0.02) > 0.2) {
          classes[index] = FaceParsingClass.skin.index;
          continue;
        }

        classes[index] = FaceParsingClass.background.index;
      }
    }

    return FaceParsingResult(
      classes: classes,
      width: width,
      height: height,
      source: source,
      confidence: confidence,
    );
  }

  static FaceParsingClass _mapPartClass(
    FacePartsSegmentation parts,
    double nx,
    double ny,
  ) {
    final idx = parts.classIndexAt(nx, ny);
    final part = FacePartClass.fromIndex(idx);
    switch (part) {
      case FacePartClass.background:
        return FaceParsingClass.background;
      case FacePartClass.hair:
        return FaceParsingClass.hair;
      case FacePartClass.bodySkin:
        return FaceParsingClass.neck;
      case FacePartClass.faceSkin:
        return FaceParsingClass.skin;
      case FacePartClass.clothes:
        return FaceParsingClass.cloth;
      case FacePartClass.others:
        return FaceParsingClass.others;
    }
  }

  static FaceParsingClass? _classFromLandmarks(
    double nx,
    double ny,
    SkinProcessingMask? geometric,
  ) {
    if (geometric == null || geometric.isEmpty) return null;
    final point = Offset(nx, ny);
    final protected = geometric.protectedRegions;

    if (protected.isNotEmpty && protected[0].inflate(0.008).contains(point)) {
      return FaceParsingClass.eyeG;
    }
    if (protected.length > 1 && protected[1].inflate(0.008).contains(point)) {
      return FaceParsingClass.eyeL;
    }
    if (protected.length > 2 && protected[2].inflate(0.008).contains(point)) {
      return FaceParsingClass.mouth;
    }

    final brows = geometric.eyebrowRegions;
    if (brows.isNotEmpty && brows[0].inflate(0.01).contains(point)) {
      return FaceParsingClass.browG;
    }
    if (brows.length > 1 && brows[1].inflate(0.01).contains(point)) {
      return FaceParsingClass.browL;
    }

    final mouthEllipse = geometric.innerMouthEllipse;
    if (mouthEllipse != null && mouthEllipse.weight(nx, ny) > 0.5) {
      return ny < mouthEllipse.center.dy
          ? FaceParsingClass.lipUpper
          : FaceParsingClass.lipLower;
    }

    for (final region in geometric.innerMouthRegions) {
      if (region.contains(point)) {
        return FaceParsingClass.mouth;
      }
    }

    return null;
  }
}
