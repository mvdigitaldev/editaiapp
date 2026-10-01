import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'lip_height_masks.dart';
import 'lip_height_metrics.dart';

class LipHeightFieldBuild {
  const LipHeightFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final LipHeightMasks masks;
  final LipHeightFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dy`.
class LipHeightFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unit;
  List<int>? active;
  DisplacementField? field;
  LipHeightMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unit != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Sobe ou desce a boca inteira. Só Δy.
///
/// Direita do slider sobe. Esquerda desce. Não importa outros Fields.
abstract final class LipHeightField {
  LipHeightField._();

  static const amplitudeFaceWidth = 0.024;
  static const falloffFaceWidth = 0.055;
  static const hullPadFaceWidth = 0.040;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;

  static LipHeightFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    LipHeightFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('lip_height_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amp = amplitudeFaceWidth * runtime.faceWidth;
      _scaleActive(
        field: runtime.field!,
        unit: runtime.unit!,
        active: runtime.active!,
        dy: -intensity * amp,
      );
      final metrics = computeMetrics
          ? LipHeightFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: LipHeightMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
            )
          : LipHeightFieldMetrics.skipped;
      return LipHeightFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = LipHeightMasks.landmarkPixels(face, imageSize);
    final faceWidth = LipHeightMasks.faceWidthOf(px);
    final masks = LipHeightMasks.build(
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
      unit: packed.unit,
      active: packed.active,
      dy: -intensity * amp,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unit = packed.unit
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? LipHeightFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
          )
        : LipHeightFieldMetrics.skipped;
    return LipHeightFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unit,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required LipHeightMasks masks,
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
    final unit = <double>[];
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
      active.add(i);
      unit.add(w);
    }
    return (
      unit: Float32List.fromList(unit),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unit,
    required List<int> active,
    required double dy,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = 0;
      field.dy[i] = dy * unit[k];
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
