import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'nose_ala_masks.dart';
import 'nose_ala_metrics.dart';

class NoseAlaFieldBuild {
  const NoseAlaFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final NoseAlaMasks masks;
  final NoseAlaFieldMetrics metrics;
}

/// Cache do vector unitário (independente de t). O slider só entra em `α(t)`.
class NoseAlaFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitDxLeft;
  Float32List? unitDxRight;
  List<int>? active;
  DisplacementField? field;
  NoseAlaMasks? masks;

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

/// Afina ou alarga as asas em volta da midline. Só Δx.
///
/// Direita do slider afina. Esquerda alarga. L/R da foto.
/// Não importa outros Fields.
abstract final class NoseAlaField {
  NoseAlaField._();

  static const nasion = 168;
  static const tip = 1;
  static const alaPhotoLeft = 98;
  static const alaPhotoRight = 327;

  /// `s = 1 − k t`. k = 0.24 → afina a 0.76 e alarga a 1.24, só em x.
  static const scaleGain = 0.24;
  static const falloffFaceWidth = 0.065;
  static const hullPadFaceWidth = 0.050;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;
  static const midHoldFaceWidth = 0.028;
  static const profileHold = 0.12;
  static const profileFull = 0.42;

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

  static NoseAlaFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    NoseAlaFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('nose_ala_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        active: runtime.active!,
        unitDxLeft: runtime.unitDxLeft!,
        unitDxRight: runtime.unitDxRight!,
        alphaLeft: alphaOf(signedLeft),
        alphaRight: alphaOf(signedRight),
      );
      final metrics = computeMetrics
          ? NoseAlaFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: NoseAlaMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
            )
          : NoseAlaFieldMetrics.skipped;
      return NoseAlaFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = NoseAlaMasks.landmarkPixels(face, imageSize);
    final faceWidth = NoseAlaMasks.faceWidthOf(px);
    final masks = NoseAlaMasks.build(
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
      unitDxRight: packed.unitDxRight,
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
        ..unitDxRight = packed.unitDxRight
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? NoseAlaFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
          )
        : NoseAlaFieldMetrics.skipped;
    return NoseAlaFieldBuild(
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
    required NoseAlaMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(8.0, falloffFaceWidth * faceWidth);
    final guard = math.max(6.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final midHold = math.max(4.0, midHoldFaceWidth * faceWidth);
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
    final span = math.max(profileFull - profileHold, 1e-6);

    final active = <int>[];
    final dxL = <double>[];
    final dxR = <double>[];
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
        span: span,
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
      if (x < midX) {
        dxL.add(unit);
        dxR.add(0);
      } else {
        dxL.add(0);
        dxR.add(unit);
      }
    }
    return (
      unitDxLeft: Float32List.fromList(dxL),
      unitDxRight: Float32List.fromList(dxR),
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
    required double span,
  }) {
    if (root == null || axisLen2 < 1e-6) {
      return 1;
    }
    final u = ((x - root.dx) * axis.dx + (y - root.dy) * axis.dy) / axisLen2;
    if (u <= profileHold) {
      return 0;
    }
    if (u >= profileFull) {
      return 1;
    }
    return _smoothstep((u - profileHold) / span);
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
    required Float32List unitDxLeft,
    required Float32List unitDxRight,
    required double alphaLeft,
    required double alphaRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = alphaLeft * unitDxLeft[k] + alphaRight * unitDxRight[k];
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
