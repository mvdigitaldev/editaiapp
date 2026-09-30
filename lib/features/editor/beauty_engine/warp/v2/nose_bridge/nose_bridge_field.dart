import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'nose_bridge_masks.dart';
import 'nose_bridge_metrics.dart';

class NoseBridgeFieldBuild {
  const NoseBridgeFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final NoseBridgeMasks masks;
  final NoseBridgeFieldMetrics metrics;
}

/// Cache do vector unitário (independente de t). O slider só entra em `α(t)`.
class NoseBridgeFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitDx;
  List<int>? active;
  DisplacementField? field;
  NoseBridgeMasks? masks;

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

/// Afina ou alarga o dorso em volta da midline. Só Δx.
///
/// Direita do slider afina. Esquerda alarga. Não importa outros Fields.
abstract final class NoseBridgeField {
  NoseBridgeField._();

  static const nasion = 168;
  static const tip = 1;

  /// `s = 1 − k t`. k = 0.28 → afina a 0.72 e alarga a 1.28, só em x.
  static const scaleGain = 0.28;
  static const falloffFaceWidth = 0.070;
  static const hullPadFaceWidth = 0.055;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;
  static const midHoldFaceWidth = 0.022;
  static const profileRiseStart = 0.18;
  static const profileRiseEnd = 0.32;
  static const profileFallStart = 0.50;
  static const profileFallEnd = 0.70;

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

  static NoseBridgeFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    NoseBridgeFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('nose_bridge_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);
    final alpha = alphaOf(intensity);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        active: runtime.active!,
        unitDx: runtime.unitDx!,
        alpha: alpha,
      );
      final metrics = computeMetrics
          ? NoseBridgeFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: NoseBridgeMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
            )
          : NoseBridgeFieldMetrics.skipped;
      return NoseBridgeFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = NoseBridgeMasks.landmarkPixels(face, imageSize);
    final faceWidth = NoseBridgeMasks.faceWidthOf(px);
    final masks = NoseBridgeMasks.build(
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
      unitDx: packed.unitDx,
      alpha: alpha,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitDx = packed.unitDx
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? NoseBridgeFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
          )
        : NoseBridgeFieldMetrics.skipped;
    return NoseBridgeFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitDx,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required NoseBridgeMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(8.0, falloffFaceWidth * faceWidth);
    final guard = math.max(6.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final midHold = math.max(3.0, midHoldFaceWidth * faceWidth);
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

    final root = _point(px, nasion);
    final end = _point(px, tip);
    final midX = _midX(root, end, width);
    final axis = (root != null && end != null) ? end - root : Offset.zero;
    final axisLen2 = axis.dx * axis.dx + axis.dy * axis.dy;

    final active = <int>[];
    final dx = <double>[];
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
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      final profile = _profile(
        x: x,
        y: y,
        root: root,
        axis: axis,
        axisLen2: axisLen2,
      );
      final midGate = _smoothstep((x - midX).abs() / midHold);
      final w = r * guardW * profile * midGate;
      if (w <= 1e-6) {
        continue;
      }
      final unit = w * (x - midX);
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

  static double _midX(Offset? root, Offset? end, int width) {
    if (root != null && end != null) {
      return 0.5 * (root.dx + end.dx);
    }
    return (root ?? end)?.dx ?? width * 0.5;
  }

  static double _profile({
    required double x,
    required double y,
    required Offset? root,
    required Offset axis,
    required double axisLen2,
  }) {
    if (root == null || axisLen2 < 1e-6) {
      return 1;
    }
    final u = ((x - root.dx) * axis.dx + (y - root.dy) * axis.dy) / axisLen2;
    if (u <= profileRiseStart || u >= profileFallEnd) {
      return 0;
    }
    if (u >= profileRiseEnd && u <= profileFallStart) {
      return 1;
    }
    if (u < profileRiseEnd) {
      return _smoothstep(
        (u - profileRiseStart) / (profileRiseEnd - profileRiseStart),
      );
    }
    return _smoothstep(
      (profileFallEnd - u) / (profileFallEnd - profileFallStart),
    );
  }

  static Offset? _point(List<Offset?> px, int id) {
    if (id < 0 || id >= px.length) {
      return null;
    }
    return px[id];
  }

  static void _scaleActive({
    required DisplacementField field,
    required List<int> active,
    required Float32List unitDx,
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
