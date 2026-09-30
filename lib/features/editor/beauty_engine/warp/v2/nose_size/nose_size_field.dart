import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'nose_size_masks.dart';
import 'nose_size_metrics.dart';

class NoseSizeFieldBuild {
  const NoseSizeFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
    required this.center,
  });

  final DisplacementField field;
  final NoseSizeMasks masks;
  final NoseSizeFieldMetrics metrics;
  final Offset? center;
}

/// Cache do vector unitário (independente de t). O slider só entra em `α(t)`.
class NoseSizeFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Offset? center;
  Float32List? unitDx;
  Float32List? unitDy;
  List<int>? active;
  DisplacementField? field;
  NoseSizeMasks? masks;

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

/// Escala local do nariz em volta do centróide da ilha.
///
/// Esquerda do slider aumenta. Direita encolhe. Não importa outros Fields.
abstract final class NoseSizeField {
  NoseSizeField._();

  /// `s = 1 − k t`. k = 0.14 → encolhe a 0.86 e aumenta a 1.14.
  static const scaleGain = 0.14;
  static const falloffFaceWidth = 0.055;
  static const hullPadFaceWidth = 0.040;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;

  static double scaleOf(double t) {
    return 1.0 - scaleGain * t.clamp(-1.0, 1.0);
  }

  static double alphaOf(double t) {
    final s = scaleOf(t);
    if ((s - 1.0).abs() < 1e-9) {
      return 0;
    }
    return 1.0 - 1.0 / s;
  }

  static NoseSizeFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    NoseSizeFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('nose_size_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);
    final alpha = alphaOf(intensity);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        unitDx: runtime.unitDx!,
        unitDy: runtime.unitDy!,
        active: runtime.active!,
        alpha: alpha,
      );
      final metrics = computeMetrics
          ? NoseSizeFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: NoseSizeMasks.landmarkPixels(face, imageSize),
              center: runtime.center ?? Offset.zero,
              faceWidth: runtime.faceWidth,
            )
          : NoseSizeFieldMetrics.skipped;
      return NoseSizeFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
        center: runtime.center,
      );
    }

    final px = NoseSizeMasks.landmarkPixels(face, imageSize);
    final faceWidth = NoseSizeMasks.faceWidthOf(px);
    final center = NoseSizeMasks.centroid(px) ??
        Offset(width * 0.5, height * 0.45);
    final masks = NoseSizeMasks.build(
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
      alpha: alpha,
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
        ? NoseSizeFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            center: center,
            faceWidth: faceWidth,
          )
        : NoseSizeFieldMetrics.skipped;
    return NoseSizeFieldBuild(
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
    required NoseSizeMasks masks,
    required Offset center,
    required double faceWidth,
  }) {
    final falloff = math.max(8.0, falloffFaceWidth * faceWidth);
    final guard = math.max(6.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final ramp = BoundaryFeather.insideActive(
      mask: masks.nose,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
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
    final distMouth = EuclideanDistanceTransform.toNonZeroOf(
      masks.mouth,
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
      final guardW = _smoothstep(distEyes[i] / guard) *
          _smoothstep(distBrows[i] / guard) *
          _smoothstep(distMouth[i] / guard);
      if (guardW <= 1e-6) {
        continue;
      }
      final w = r * guardW;
      if (w <= 1e-6) {
        continue;
      }
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      active.add(i);
      dx.add(w * (x - center.dx));
      dy.add(w * (y - center.dy));
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
    required double alpha,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = alpha * unitDx[k];
      field.dy[i] = alpha * unitDy[k];
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
