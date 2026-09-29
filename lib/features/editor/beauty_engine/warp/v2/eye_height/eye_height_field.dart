import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'eye_height_masks.dart';
import 'eye_height_metrics.dart';

class EyeHeightFieldBuild {
  const EyeHeightFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final EyeHeightMasks masks;
  final EyeHeightFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dy`.
class EyeHeightFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitLeft;
  Float32List? unitRight;
  List<int>? active;
  DisplacementField? field;
  EyeHeightMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitLeft != null &&
        unitRight != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Sobe ou desce cada olho. Só Δy. Não importa outros Fields.
///
/// Direita do slider sobe. Esquerda desce.
abstract final class EyeHeightField {
  EyeHeightField._();

  /// Íris. 468 = foto esquerda. 473 = foto direita.
  static const centerPhotoLeft = 468;
  static const centerPhotoRight = 473;

  static const browPhotoLeft = 105;
  static const browPhotoRight = 334;
  static const hairlineTop = 10;

  static const amplitudeFaceWidth = 0.030;
  static const falloffFaceWidth = 0.07;
  static const hullPadFaceWidth = 0.025;
  static const guardFalloffFaceWidth = 0.04;
  static const boundarySmoothFaceWidth = 0.022;

  static EyeHeightFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    EyeHeightFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('eye_height_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amp = amplitudeFaceWidth * runtime.faceWidth;
      _scaleActive(
        field: runtime.field!,
        active: runtime.active!,
        unitLeft: runtime.unitLeft!,
        unitRight: runtime.unitRight!,
        dyLeft: -signedLeft * amp,
        dyRight: -signedRight * amp,
      );
      final metrics = computeMetrics
          ? EyeHeightFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: EyeHeightMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              centerLeft: centerPhotoLeft,
              centerRight: centerPhotoRight,
              browLeft: browPhotoLeft,
              browRight: browPhotoRight,
              hairlineTop: hairlineTop,
            )
          : EyeHeightFieldMetrics.skipped;
      return EyeHeightFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = EyeHeightMasks.landmarkPixels(face, imageSize);
    final faceWidth = EyeHeightMasks.faceWidthOf(px);
    final masks = EyeHeightMasks.build(
      face: face,
      imageSize: imageSize,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final packed = _packUnits(
      width: width,
      height: height,
      masks: masks,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    final amp = amplitudeFaceWidth * faceWidth;
    _scaleActive(
      field: field,
      active: packed.active,
      unitLeft: packed.unitLeft,
      unitRight: packed.unitRight,
      dyLeft: -signedLeft * amp,
      dyRight: -signedRight * amp,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitLeft = packed.unitLeft
        ..unitRight = packed.unitRight
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? EyeHeightFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            centerLeft: centerPhotoLeft,
            centerRight: centerPhotoRight,
            browLeft: browPhotoLeft,
            browRight: browPhotoRight,
            hairlineTop: hairlineTop,
          )
        : EyeHeightFieldMetrics.skipped;
    return EyeHeightFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitLeft,
    Float32List unitRight,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required EyeHeightMasks masks,
    required double faceWidth,
  }) {
    final falloff = math.max(8.0, falloffFaceWidth * faceWidth);
    final guard = math.max(6.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final rampLeft = BoundaryFeather.insideActive(
      mask: masks.photoLeft,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
    );
    final rampRight = BoundaryFeather.insideActive(
      mask: masks.photoRight,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
    );
    final distBrow = EuclideanDistanceTransform.toNonZeroOf(
      masks.brows,
      width,
      height,
    );
    final distNose = EuclideanDistanceTransform.toNonZeroOf(
      masks.nose,
      width,
      height,
    );

    final active = <int>[];
    final left = <double>[];
    final right = <double>[];
    for (var i = 0; i < width * height; i++) {
      final rampL = rampLeft[i];
      final rampR = rampRight[i];
      if (rampL <= 1e-6 && rampR <= 1e-6) {
        continue;
      }
      final guardW =
          _smoothstep(distBrow[i] / guard) * _smoothstep(distNose[i] / guard);
      if (guardW <= 1e-6) {
        continue;
      }
      var wL = rampL * guardW;
      var wR = rampR * guardW;
      if (wL > 1e-6 && wR > 1e-6) {
        if (wL >= wR) {
          wR = 0;
        } else {
          wL = 0;
        }
      }
      if (wL <= 1e-6 && wR <= 1e-6) {
        continue;
      }
      active.add(i);
      left.add(wL);
      right.add(wR);
    }
    return (
      unitLeft: Float32List.fromList(left),
      unitRight: Float32List.fromList(right),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required List<int> active,
    required Float32List unitLeft,
    required Float32List unitRight,
    required double dyLeft,
    required double dyRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = 0;
      field.dy[i] = dyLeft * unitLeft[k] + dyRight * unitRight[k];
    }
  }

  static double _smoothstep(double u) {
    if (u <= 0) {
      return 0;
    }
    if (u >= 1) {
      return 1;
    }
    return u * u * (3.0 - 2.0 * u);
  }
}
