import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'nose_lift_masks.dart';
import 'nose_lift_metrics.dart';

class NoseLiftFieldBuild {
  const NoseLiftFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final NoseLiftMasks masks;
  final NoseLiftFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dy`.
class NoseLiftFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unit;
  List<int>? active;
  DisplacementField? field;
  NoseLiftMasks? masks;

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

/// Sobe ou desce a ponta do nariz em volta da raiz. Só Δy.
///
/// Direita do slider sobe. Esquerda desce. Não importa outros Fields.
abstract final class NoseLiftField {
  NoseLiftField._();

  static const nasion = 168;
  static const tip = 1;

  static const amplitudeFaceWidth = 0.045;
  static const falloffFaceWidth = 0.105;
  static const hullPadFaceWidth = 0.090;
  static const guardFalloffFaceWidth = 0.045;
  static const mouthGuardFalloffFaceWidth = 0.100;
  static const boundarySmoothFaceWidth = 0.022;
  static const profileHold = 0.08;
  static const profileFull = 0.48;

  static NoseLiftFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    NoseLiftFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('nose_lift_field_invalid_size: ${width}x$height');
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
          ? NoseLiftFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: NoseLiftMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
            )
          : NoseLiftFieldMetrics.skipped;
      return NoseLiftFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = NoseLiftMasks.landmarkPixels(face, imageSize);
    final faceWidth = NoseLiftMasks.faceWidthOf(px);
    final masks = NoseLiftMasks.build(
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
        ? NoseLiftFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
          )
        : NoseLiftFieldMetrics.skipped;
    return NoseLiftFieldBuild(
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
    required NoseLiftMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(8.0, falloffFaceWidth * faceWidth);
    final guard = math.max(6.0, guardFalloffFaceWidth * faceWidth);
    final mouthGuard = math.max(10.0, mouthGuardFalloffFaceWidth * faceWidth);
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

    final root = _point(px, nasion);
    final end = _point(px, tip);
    final axis = (root != null && end != null) ? end - root : Offset.zero;
    final axisLen2 = axis.dx * axis.dx + axis.dy * axis.dy;
    final span = math.max(profileFull - profileHold, 1e-6);

    final active = <int>[];
    final unit = <double>[];
    for (var i = 0; i < width * height; i++) {
      final r = ramp[i];
      if (r <= 1e-6) {
        continue;
      }
      final guardW = _smoothstep(distEyes[i] / guard) *
          _smoothstep(distBrows[i] / guard) *
          _smoothstep(distMouth[i] / mouthGuard);
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
      final w = r * guardW * profile;
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
