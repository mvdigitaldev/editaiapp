import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import 'head_masks.dart';
import 'head_metrics.dart';

class HeadFieldBuild {
  const HeadFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
    required this.center,
  });

  final DisplacementField field;
  final HeadMasks masks;
  final HeadFieldMetrics metrics;
  final Offset? center;
}

/// Cache do peso unitário (independente de t). O slider só multiplica por α(t).
/// `unitDx`/`unitDy` = `w · (q − c) · min(1, R₊ / |q − c|)`.
class HeadFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Offset? center;
  Float32List? unitDx;
  Float32List? unitDy;
  List<int>? active;
  DisplacementField? field;
  HeadMasks? masks;

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

/// Constrói o campo head. Sem RGBA, sem render.
///
/// `t ∈ [-1, 1]`: t<0 cresce; t>0 encolhe; t=0 identidade.
/// `s = 1 − k t`, `D = w · (q − c) · (1 − 1/s)`. Sem crista. Sem max(gaussianas).
abstract final class HeadField {
  HeadField._();

  static const scaleRange = 0.12;
  static const falloffFaceWidth = 0.24;

  /// Pad ≥ rampa: o plateau de w=1 tem de cobrir a silhueta aumentada.
  /// Senão ∇w senta-se na cara e o campo inverte.
  static const hullPadFaceWidth = 0.28;
  static const crownPadFaceWidth = 0.04;
  static const crownExtendFaceWidth = 0.70;
  static const crownMarginPx = 8.0;

  /// Asa lateral: o oval/orelha não cobrem o cabelo volumoso.
  static const hairWingFaceWidth = 0.34;
  static const boundarySmoothFaceWidth = 0.022;

  static double scaleOf(double t) {
    return 1.0 - scaleRange * t.clamp(-1.0, 1.0);
  }

  static double alphaOf(double t) {
    final s = scaleOf(t);
    if ((s - 1.0).abs() < 1e-9) {
      return 0;
    }
    return 1.0 - 1.0 / s;
  }

  static HeadFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
    bool computeMetrics = true,
    HeadFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('head_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);
    final scale = scaleOf(intensity);
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
          ? HeadFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: HeadMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              scale: scale,
              alpha: alpha,
            )
          : HeadFieldMetrics.skipped;
      return HeadFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
        center: runtime.center,
      );
    }

    final px = HeadMasks.landmarkPixels(face, imageSize);
    final faceWidth = HeadMasks.faceWidthOf(px);
    final center = HeadMasks.ovalCenter(px);
    final masks = HeadMasks.build(
      face: face,
      imageSize: imageSize,
      center: center ?? Offset(width * 0.5, height * 0.5),
      scaleMax: 1.0 + scaleRange,
      hullPadFaceWidth: hullPadFaceWidth,
      crownPadFaceWidth: crownPadFaceWidth,
      crownExtendFaceWidth: crownExtendFaceWidth,
      crownMarginPx: crownMarginPx,
      hairWingFaceWidth: hairWingFaceWidth,
    );
    final packed = _packUnitWeights(
      width: width,
      height: height,
      masks: masks,
      center: center,
      faceWidth: faceWidth,
      capRadius: _capRadius(px, center, faceWidth),
    );
    final field = DisplacementField.zeros(width: width, height: height);
    if (alpha.abs() > 1e-9) {
      _scaleActive(
        field: field,
        unitDx: packed.unitDx,
        unitDy: packed.unitDy,
        active: packed.active,
        alpha: alpha,
      );
    }

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
        ? HeadFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            scale: scale,
            alpha: alpha,
          )
        : HeadFieldMetrics.skipped;
    return HeadFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
      center: center,
    );
  }

  static double _capRadius(
    List<Offset?> px,
    Offset? center,
    double faceWidth,
  ) {
    if (center == null) {
      return 1;
    }
    var r = 1.0;
    void consider(Offset p) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      r = math.max(r, math.sqrt(dx * dx + dy * dy));
    }

    for (final id in const [
      10,
      152,
      58,
      288,
      103,
      332,
      67,
      297,
      109,
      338,
      21,
      251,
      323,
      454,
    ]) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        consider(p);
      }
    }
    final top = px.length > 10 ? px[10] : null;
    if (top != null) {
      final pad = math.max(6.0, crownPadFaceWidth * faceWidth);
      final room = math.max(0.0, top.dy - pad - crownMarginPx);
      final lift = math.min(room, crownExtendFaceWidth * faceWidth);
      if (lift > 1e-6) {
        consider(Offset(top.dx, top.dy - lift));
      }
    }
    final wing = hairWingFaceWidth * faceWidth;
    for (final id in HeadMasks.hairWingIds) {
      final p = id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      final sign = p.dx < center.dx ? -1.0 : 1.0;
      consider(Offset(p.dx + sign * wing, p.dy));
    }
    return (1.0 + scaleRange) * r;
  }

  static ({Float32List unitDx, Float32List unitDy, List<int> active})
      _packUnitWeights({
    required int width,
    required int height,
    required HeadMasks masks,
    required Offset? center,
    required double faceWidth,
    required double capRadius,
  }) {
    final falloff = math.max(12.0, falloffFaceWidth * faceWidth);
    final boundaryRamp = BoundaryFeather.insideActive(
      mask: masks.headActive,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: math.max(1.0, boundarySmoothFaceWidth * faceWidth),
    );
    final active = <int>[];
    final outDx = <double>[];
    final outDy = <double>[];
    if (center != null) {
      final pixelCount = width * height;
      for (var i = 0; i < pixelCount; i++) {
        if (masks.headActive[i] == 0) {
          continue;
        }
        final boundary = boundaryRamp[i];
        if (boundary <= 1e-6) {
          continue;
        }
        final x = (i % width) + 0.5;
        final y = (i ~/ width) + 0.5;
        final vx = x - center.dx;
        final vy = y - center.dy;
        final r = math.sqrt(vx * vx + vy * vy);
        final clamp = r > capRadius && r > 1e-9 ? capRadius / r : 1.0;
        active.add(i);
        outDx.add(vx * boundary * clamp);
        outDy.add(vy * boundary * clamp);
      }
    }
    return (
      unitDx: Float32List.fromList(outDx),
      unitDy: Float32List.fromList(outDy),
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
}
