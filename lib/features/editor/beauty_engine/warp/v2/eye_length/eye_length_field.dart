import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import '../region_catalog.dart';
import 'eye_length_masks.dart';
import 'eye_length_metrics.dart';

class EyeLengthFieldBuild {
  const EyeLengthFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final EyeLengthMasks masks;
  final EyeLengthFieldMetrics metrics;
}

/// Cache do perfil do canto externo. O slider só escala `dx`.
class EyeLengthFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitDxLeft;
  Float32List? unitDxRight;
  List<int>? active;
  DisplacementField? field;
  EyeLengthMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitDxLeft != null &&
        unitDxRight != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Alonga ou encurta cada olho pelo canto externo. Só Δx.
///
/// Esquerda do slider encurta. Direita alonga. Não importa outros Fields.
abstract final class EyeLengthField {
  EyeLengthField._();

  /// Íris. 468 = foto esquerda. 473 = foto direita. Fica.
  static const centerPhotoLeft = 468;
  static const centerPhotoRight = 473;

  /// Canto externo. Anda. Canto interno fica.
  static const outerPhotoLeft = 33;
  static const outerPhotoRight = 263;
  static const innerPhotoLeft = 133;
  static const innerPhotoRight = 362;

  static const browPhotoLeft = 105;
  static const browPhotoRight = 334;
  static const hairlineTop = 10;

  /// Pico no canto externo, em fracção da largura da cara.
  static const amplitudeFaceWidth = 0.028;
  static const falloffFaceWidth = 0.07;
  static const hullPadFaceWidth = 0.025;
  static const guardFalloffFaceWidth = 0.04;
  static const boundarySmoothFaceWidth = 0.022;

  static EyeLengthFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    EyeLengthFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('eye_length_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amp = amplitudeFaceWidth * runtime.faceWidth;
      _scaleActive(
        field: runtime.field!,
        active: runtime.active!,
        unitDxLeft: runtime.unitDxLeft!,
        unitDxRight: runtime.unitDxRight!,
        dxLeft: signedLeft * amp,
        dxRight: signedRight * amp,
      );
      final metrics = computeMetrics
          ? EyeLengthFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: EyeLengthMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              centerLeft: centerPhotoLeft,
              centerRight: centerPhotoRight,
              outerLeft: outerPhotoLeft,
              outerRight: outerPhotoRight,
              innerLeft: innerPhotoLeft,
              innerRight: innerPhotoRight,
              browLeft: browPhotoLeft,
              browRight: browPhotoRight,
              hairlineTop: hairlineTop,
            )
          : EyeLengthFieldMetrics.skipped;
      return EyeLengthFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = EyeLengthMasks.landmarkPixels(face, imageSize);
    final faceWidth = EyeLengthMasks.faceWidthOf(px);
    final masks = EyeLengthMasks.build(
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
    final amp = amplitudeFaceWidth * faceWidth;
    _scaleActive(
      field: field,
      active: packed.active,
      unitDxLeft: packed.unitDxLeft,
      unitDxRight: packed.unitDxRight,
      dxLeft: signedLeft * amp,
      dxRight: signedRight * amp,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitDxLeft = packed.unitDxLeft
        ..unitDxRight = packed.unitDxRight
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? EyeLengthFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            centerLeft: centerPhotoLeft,
            centerRight: centerPhotoRight,
            outerLeft: outerPhotoLeft,
            outerRight: outerPhotoRight,
            innerLeft: innerPhotoLeft,
            innerRight: innerPhotoRight,
            browLeft: browPhotoLeft,
            browRight: browPhotoRight,
            hairlineTop: hairlineTop,
          )
        : EyeLengthFieldMetrics.skipped;
    return EyeLengthFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitDxLeft,
    Float32List unitDxRight,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required EyeLengthMasks masks,
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
    final outerLeft = _center(px, outerPhotoLeft, V2RegionCatalog.rightEye);
    final outerRight = _center(px, outerPhotoRight, V2RegionCatalog.leftEye);
    final sideLeft = (outerLeft.dx - cLeft.dx).sign;
    final sideRight = (outerRight.dx - cRight.dx).sign;
    final halfLeft = math.max(8.0, (outerLeft.dx - cLeft.dx).abs());
    final halfRight = math.max(8.0, (outerRight.dx - cRight.dx).abs());

    final active = <int>[];
    final dxL = <double>[];
    final dxR = <double>[];
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
      final profileL = _outerProfile(x, cLeft.dx, sideLeft, halfLeft);
      final profileR = _outerProfile(x, cRight.dx, sideRight, halfRight);
      wL *= profileL;
      wR *= profileR;
      if (wL <= 1e-6 && wR <= 1e-6) {
        continue;
      }
      active.add(i);
      dxL.add(wL * sideLeft);
      dxR.add(wR * sideRight);
    }
    return (
      unitDxLeft: Float32List.fromList(dxL),
      unitDxRight: Float32List.fromList(dxR),
      active: active,
    );
  }

  /// 0 na íris e no lado interno. 1 a partir do canto externo.
  static double _outerProfile(
    double x,
    double centerX,
    double side,
    double half,
  ) {
    if (side == 0 || half <= 1e-6) {
      return 0;
    }
    final u = ((x - centerX) * side) / half;
    if (u <= 0) {
      return 0;
    }
    if (u >= 1) {
      return 1;
    }
    return _smoothstep(u);
  }

  static void _scaleActive({
    required DisplacementField field,
    required List<int> active,
    required Float32List unitDxLeft,
    required Float32List unitDxRight,
    required double dxLeft,
    required double dxRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = dxLeft * unitDxLeft[k] + dxRight * unitDxRight[k];
      field.dy[i] = 0;
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
