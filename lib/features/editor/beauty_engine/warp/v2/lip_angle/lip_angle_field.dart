import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'lip_angle_masks.dart';
import 'lip_angle_metrics.dart';

class LipAngleFieldBuild {
  const LipAngleFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
    required this.center,
  });

  final DisplacementField field;
  final LipAngleMasks masks;
  final LipAngleFieldMetrics metrics;
  final Offset? center;
}

/// Cache do vector unitário (independente de t). O slider só escala θ.
class LipAngleFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Offset? center;
  Float32List? unitDx;
  Float32List? unitDy;
  List<int>? active;
  DisplacementField? field;
  LipAngleMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        unitDy != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Inclina a boca em volta do centróide. Δx e Δy — movimento na diagonal.
///
/// Direita do slider: canto da foto à esquerda desce, o da direita sobe.
/// Esquerda: o contrário. Não importa outros Fields.
abstract final class LipAngleField {
  LipAngleField._();

  /// Ângulo máximo em radianos. ~7°.
  static const angleGain = 0.12;
  static const falloffFaceWidth = 0.055;
  static const hullPadFaceWidth = 0.040;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;

  static LipAngleFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    LipAngleFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('lip_angle_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);
    final theta = intensity * angleGain;

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        unitDx: runtime.unitDx!,
        unitDy: runtime.unitDy!,
        active: runtime.active!,
        theta: theta,
      );
      final metrics = computeMetrics
          ? LipAngleFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: LipAngleMasks.landmarkPixels(face, imageSize),
              center: runtime.center ?? Offset.zero,
              faceWidth: runtime.faceWidth,
            )
          : LipAngleFieldMetrics.skipped;
      return LipAngleFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
        center: runtime.center,
      );
    }

    final px = LipAngleMasks.landmarkPixels(face, imageSize);
    final faceWidth = LipAngleMasks.faceWidthOf(px);
    final center = LipAngleMasks.centroid(px) ??
        Offset(width * 0.5, height * 0.62);
    final masks = LipAngleMasks.build(
      face: face,
      imageSize: imageSize,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final packed = _packUnits(
      width: width,
      height: height,
      masks: masks,
      center: center,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    _scaleActive(
      field: field,
      unitDx: packed.unitDx,
      unitDy: packed.unitDy,
      active: packed.active,
      theta: theta,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..center = center
        ..unitDx = packed.unitDx
        ..unitDy = packed.unitDy
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? LipAngleFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            center: center,
            faceWidth: faceWidth,
          )
        : LipAngleFieldMetrics.skipped;
    return LipAngleFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
      center: center,
    );
  }

  static ({
    Float32List unitDx,
    Float32List unitDy,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required LipAngleMasks masks,
    required Offset center,
    required double faceWidth,
  }) {
    final falloff = math.max(6.0, falloffFaceWidth * faceWidth);
    final guard = math.max(5.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final ramp = BoundaryFeather.insideActive(
      mask: masks.lips,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
    );
    final distNose = EuclideanDistanceTransform.toNonZeroOf(
      masks.nose,
      width,
      height,
    );
    final distChin = EuclideanDistanceTransform.toNonZeroOf(
      masks.chin,
      width,
      height,
    );
    final distEyes = EuclideanDistanceTransform.toNonZeroOf(
      masks.eyes,
      width,
      height,
    );
    final distBrows = EuclideanDistanceTransform.toNonZeroOf(
      masks.brows,
      width,
      height,
    );

    final active = <int>[];
    final dx = <double>[];
    final dy = <double>[];
    for (var i = 0; i < width * height; i++) {
      final r = ramp[i];
      if (r <= 1e-6) {
        continue;
      }
      final guardW = _smoothstep(distNose[i] / guard) *
          _smoothstep(distChin[i] / guard) *
          _smoothstep(distEyes[i] / guard) *
          _smoothstep(distBrows[i] / guard);
      if (guardW <= 1e-6) {
        continue;
      }
      final w = r * guardW;
      if (w <= 1e-6) {
        continue;
      }
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      final ux = w * (y - center.dy);
      final uy = -w * (x - center.dx);
      if (ux.abs() <= 1e-6 && uy.abs() <= 1e-6) {
        continue;
      }
      active.add(i);
      dx.add(ux);
      dy.add(uy);
    }
    return (
      unitDx: Float32List.fromList(dx),
      unitDy: Float32List.fromList(dy),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitDx,
    required Float32List unitDy,
    required List<int> active,
    required double theta,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = theta * unitDx[k];
      field.dy[i] = theta * unitDy[k];
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
