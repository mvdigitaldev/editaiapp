import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'lip_width_masks.dart';
import 'lip_width_metrics.dart';

class LipWidthFieldBuild {
  const LipWidthFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
    required this.center,
  });

  final DisplacementField field;
  final LipWidthMasks masks;
  final LipWidthFieldMetrics metrics;
  final Offset? center;
}

/// Cache do vector unitário (independente de t). O slider só entra em `α(t)`.
class LipWidthFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Offset? center;
  Float32List? unitDx;
  List<int>? active;
  DisplacementField? field;
  LipWidthMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Escala horizontal dos lábios em volta do centróide. Só Δx.
///
/// Esquerda do slider alarga. Direita afina. Não importa outros Fields.
abstract final class LipWidthField {
  LipWidthField._();

  /// Igual ao Tamanho, só em x. k = 0.12.
  static const scaleGain = 0.12;
  static const falloffFaceWidth = 0.042;
  static const hullPadFaceWidth = 0.030;
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

  static LipWidthFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    LipWidthFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('lip_width_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);
    final alpha = alphaOf(intensity);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        unitDx: runtime.unitDx!,
        active: runtime.active!,
        alpha: alpha,
      );
      final metrics = computeMetrics
          ? LipWidthFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: LipWidthMasks.landmarkPixels(face, imageSize),
              center: runtime.center ?? Offset.zero,
              faceWidth: runtime.faceWidth,
            )
          : LipWidthFieldMetrics.skipped;
      return LipWidthFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
        center: runtime.center,
      );
    }

    final px = LipWidthMasks.landmarkPixels(face, imageSize);
    final faceWidth = LipWidthMasks.faceWidthOf(px);
    final center = LipWidthMasks.centroid(px) ??
        Offset(width * 0.5, height * 0.62);
    final masks = LipWidthMasks.build(
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
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? LipWidthFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            center: center,
            faceWidth: faceWidth,
          )
        : LipWidthFieldMetrics.skipped;
    return LipWidthFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
      center: center,
    );
  }

  static ({
    Float32List unitDx,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required LipWidthMasks masks,
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
      final unit = w * (x - center.dx);
      if (unit.abs() <= 1e-6) {
        continue;
      }
      active.add(i);
      dx.add(unit);
    }
    return (
      unitDx: Float32List.fromList(dx),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitDx,
    required List<int> active,
    required double alpha,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = alpha * unitDx[k];
      field.dy[i] = 0;
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
