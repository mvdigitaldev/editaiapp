import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import '../region_catalog.dart';
import 'eye_size_masks.dart';
import 'eye_size_metrics.dart';

class EyeSizeFieldBuild {
  const EyeSizeFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final EyeSizeMasks masks;
  final EyeSizeFieldMetrics metrics;
}

/// Cache do vector unitário (independente de t). O slider só entra em `α(t)`.
class EyeSizeFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitDxLeft;
  Float32List? unitDyLeft;
  Float32List? unitDxRight;
  Float32List? unitDyRight;
  List<int>? active;
  DisplacementField? field;
  EyeSizeMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitDxLeft != null &&
        unitDyLeft != null &&
        unitDxRight != null &&
        unitDyRight != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Escala local de cada olho em volta da íris.
///
/// Esquerda do slider encolhe. Direita aumenta. Não importa outros Fields.
abstract final class EyeSizeField {
  EyeSizeField._();

  /// Íris. 468 = foto esquerda. 473 = foto direita.
  static const centerPhotoLeft = 468;
  static const centerPhotoRight = 473;

  /// Canto externo. Anda; a íris fica.
  static const outerPhotoLeft = 33;
  static const outerPhotoRight = 263;

  static const browPhotoLeft = 105;
  static const browPhotoRight = 334;
  static const hairlineTop = 10;

  /// `s = 1 + k t`. k = 0.28 → encolhe a 0.72 e aumenta a 1.28.
  static const scaleGain = 0.28;
  static const falloffFaceWidth = 0.07;
  static const hullPadFaceWidth = 0.025;
  static const guardFalloffFaceWidth = 0.04;
  static const boundarySmoothFaceWidth = 0.022;

  static double alphaOf(double t) {
    final denom = 1.0 + scaleGain * t;
    if (denom.abs() <= 1e-6) {
      return 0;
    }
    return scaleGain * t / denom;
  }

  static EyeSizeFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    EyeSizeFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('eye_size_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        active: runtime.active!,
        unitDxLeft: runtime.unitDxLeft!,
        unitDyLeft: runtime.unitDyLeft!,
        unitDxRight: runtime.unitDxRight!,
        unitDyRight: runtime.unitDyRight!,
        alphaLeft: alphaOf(signedLeft),
        alphaRight: alphaOf(signedRight),
      );
      final metrics = computeMetrics
          ? EyeSizeFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: EyeSizeMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              centerLeft: centerPhotoLeft,
              centerRight: centerPhotoRight,
              outerLeft: outerPhotoLeft,
              outerRight: outerPhotoRight,
              browLeft: browPhotoLeft,
              browRight: browPhotoRight,
              hairlineTop: hairlineTop,
            )
          : EyeSizeFieldMetrics.skipped;
      return EyeSizeFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = EyeSizeMasks.landmarkPixels(face, imageSize);
    final faceWidth = EyeSizeMasks.faceWidthOf(px);
    final masks = EyeSizeMasks.build(
      face: face,
      imageSize: imageSize,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final packed = _packUnits(
      width: width,
      height: height,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    _scaleActive(
      field: field,
      active: packed.active,
      unitDxLeft: packed.unitDxLeft,
      unitDyLeft: packed.unitDyLeft,
      unitDxRight: packed.unitDxRight,
      unitDyRight: packed.unitDyRight,
      alphaLeft: alphaOf(signedLeft),
      alphaRight: alphaOf(signedRight),
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitDxLeft = packed.unitDxLeft
        ..unitDyLeft = packed.unitDyLeft
        ..unitDxRight = packed.unitDxRight
        ..unitDyRight = packed.unitDyRight
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? EyeSizeFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            centerLeft: centerPhotoLeft,
            centerRight: centerPhotoRight,
            outerLeft: outerPhotoLeft,
            outerRight: outerPhotoRight,
            browLeft: browPhotoLeft,
            browRight: browPhotoRight,
            hairlineTop: hairlineTop,
          )
        : EyeSizeFieldMetrics.skipped;
    return EyeSizeFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitDxLeft,
    Float32List unitDyLeft,
    Float32List unitDxRight,
    Float32List unitDyRight,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required EyeSizeMasks masks,
    required List<Offset?> px,
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
    final cLeft = _center(px, centerPhotoLeft, V2RegionCatalog.rightEye);
    final cRight = _center(px, centerPhotoRight, V2RegionCatalog.leftEye);

    final active = <int>[];
    final dxL = <double>[];
    final dyL = <double>[];
    final dxR = <double>[];
    final dyR = <double>[];
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
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      var wL = rampL * guardW;
      var wR = rampR * guardW;
      if (wL > 1e-6 && wR > 1e-6) {
        final dL =
            (x - cLeft.dx) * (x - cLeft.dx) + (y - cLeft.dy) * (y - cLeft.dy);
        final dR = (x - cRight.dx) * (x - cRight.dx) +
            (y - cRight.dy) * (y - cRight.dy);
        if (dL <= dR) {
          wR = 0;
        } else {
          wL = 0;
        }
      }
      if (wL <= 1e-6 && wR <= 1e-6) {
        continue;
      }
      active.add(i);
      dxL.add(wL * (x - cLeft.dx));
      dyL.add(wL * (y - cLeft.dy));
      dxR.add(wR * (x - cRight.dx));
      dyR.add(wR * (y - cRight.dy));
    }
    return (
      unitDxLeft: Float32List.fromList(dxL),
      unitDyLeft: Float32List.fromList(dyL),
      unitDxRight: Float32List.fromList(dxR),
      unitDyRight: Float32List.fromList(dyR),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required List<int> active,
    required Float32List unitDxLeft,
    required Float32List unitDyLeft,
    required Float32List unitDxRight,
    required Float32List unitDyRight,
    required double alphaLeft,
    required double alphaRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = alphaLeft * unitDxLeft[k] + alphaRight * unitDxRight[k];
      field.dy[i] = alphaLeft * unitDyLeft[k] + alphaRight * unitDyRight[k];
    }
  }

  static Offset _center(List<Offset?> px, int id, Set<int> fallback) {
    final p = id < px.length ? px[id] : null;
    if (p != null) {
      return p;
    }
    var sx = 0.0;
    var sy = 0.0;
    var n = 0;
    for (final i in fallback) {
      final q = i < px.length ? px[i] : null;
      if (q == null) {
        continue;
      }
      sx += q.dx;
      sy += q.dy;
      n++;
    }
    if (n == 0) {
      return Offset.zero;
    }
    return Offset(sx / n, sy / n);
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
