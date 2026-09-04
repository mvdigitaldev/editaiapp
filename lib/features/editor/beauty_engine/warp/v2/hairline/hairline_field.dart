import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import '../ridge_weight.dart';
import 'hairline_masks.dart';
import 'hairline_metrics.dart';

class HairlineFieldBuild {
  const HairlineFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final HairlineMasks masks;
  final HairlineFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dx`/`dy`.
/// `unitDx`/`unitDy` = `w · (p − q)` com `q` na linha do cabelo.
class HairlineFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitDx;
  Float32List? unitDy;
  List<int>? active;
  DisplacementField? field;
  HairlineMasks? masks;

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

/// Constrói o campo hairline. Sem RGBA, sem render.
///
/// `t ∈ [-1, 1]`: t<0 infla (para fora da linha); t>0 desincha (para a linha).
/// A linha L não se move: `D = −sign(t) · |t| · k · w · (p − q)`, `q ∈ L`.
/// Só o lado do cabelo (para lá de L, visto do 9). Sem max(gaussianas).
abstract final class HairlineField {
  HairlineField._();

  static const primaryHandles = {10};

  /// Arco da linha do cabelo, têmpora a têmpora. Em L, D = 0.
  static const lineIds = [21, 103, 67, 109, 10, 338, 297, 332, 251];

  /// Peso ao longo de L: pico no 10, cauda nas têmporas (não é Temple).
  static const lineWeights = [
    0.15,
    0.55,
    0.75,
    0.92,
    1.00,
    0.92,
    0.75,
    0.55,
    0.15,
  ];

  /// Fallback se a banda degenerar. Sem 9/151 — a testa não entra no domínio.
  static const hullLandmarks = {
    10, 338, 297, 332, 251, 109, 67, 103, 21, 54,
  };

  static const cheekLandmarks = {123, 352};

  static const jawDomainLandmarks = {152, 58, 288};

  /// Só métrica. Sem disco em protected.
  static const templeLandmarks = {21, 162, 127, 251, 389, 356};

  /// Factor de escala (adimensional). Não é amplitude em px.
  static const scaleFactor = 0.10;
  static const falloffFaceWidth = 0.16;
  static const hullPadFaceWidth = 0.10;
  /// Tecto da banda do cabelo (o 10 fica 170–290 px abaixo do cap).
  static const crownExtendFaceWidth = 0.70;
  static const crownMarginPx = 8.0;
  static const ridgeBlendFaceWidth = 0.012;
  static const boundarySmoothFaceWidth = 0.022;

  static HairlineFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
    bool computeMetrics = true,
    HairlineFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('hairline_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final signedScale = -intensity.sign * intensity.abs() * scaleFactor;
      _scaleActive(
        field: runtime.field!,
        unitDx: runtime.unitDx!,
        unitDy: runtime.unitDy!,
        active: runtime.active!,
        signedScale: signedScale,
      );
      final amplitude = intensity.abs() * scaleFactor * runtime.faceWidth;
      final metrics = computeMetrics
          ? HairlineFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: HairlineMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              hairlineAmplitude: amplitude,
              primaryHandle:
                  primaryHandles.isEmpty ? 10 : primaryHandles.first,
              templeLandmarks: templeLandmarks,
              crown: crownApex(
                HairlineMasks.landmarkPixels(face, imageSize),
                runtime.faceWidth,
              ),
            )
          : HairlineFieldMetrics.skipped;
      return HairlineFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = HairlineMasks.landmarkPixels(face, imageSize);
    final faceWidth = faceWidthOf(px);
    final masks = HairlineMasks.build(
      face: face,
      imageSize: imageSize,
      hullLandmarks: hullLandmarks,
      cheekLandmarks: cheekLandmarks,
      jawDomainLandmarks: jawDomainLandmarks,
      templeLandmarks: templeLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
      extraHullPoints: _crownPoints(px, faceWidth),
      regionRing: _hairBand(px, faceWidth),
    );
    final signedScale = -intensity.sign * intensity.abs() * scaleFactor;
    final amplitude = intensity.abs() * scaleFactor * faceWidth;
    final packed = _packUnitWeights(
      width: width,
      height: height,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    if (intensity.abs() > 1e-6) {
      _scaleActive(
        field: field,
        unitDx: packed.unitDx,
        unitDy: packed.unitDy,
        active: packed.active,
        signedScale: signedScale,
      );
    }

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitDx = packed.unitDx
        ..unitDy = packed.unitDy
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final primary = primaryHandles.isEmpty ? 10 : primaryHandles.first;
    final metrics = computeMetrics
        ? HairlineFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            hairlineAmplitude: amplitude,
            primaryHandle: primary,
            templeLandmarks: templeLandmarks,
            crown: crownApex(px, faceWidth),
          )
        : HairlineFieldMetrics.skipped;
    return HairlineFieldBuild(field: field, masks: masks, metrics: metrics);
  }

  static double faceWidthOf(List<Offset?> px) {
    final oval = <Offset>[];
    for (final id in V2RegionCatalog.faceOval) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        oval.add(p);
      }
    }
    if (oval.isEmpty) {
      return 1.0;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return math.max(maxX - minX, 1.0);
  }

  /// Interior da testa, só para o lado do cabelo. Não é origem do campo.
  static Offset? _interior(List<Offset?> px) {
    for (final id in const [9, 151]) {
      if (id < px.length && px[id] != null) {
        return px[id];
      }
    }
    return null;
  }

  static ({Float32List unitDx, Float32List unitDy, List<int> active})
      _packUnitWeights({
    required int width,
    required int height,
    required HairlineMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final line = Ridge.of(_hairlineRidge(px));
    final interior = _interior(px);
    final falloff = math.max(12.0, falloffFaceWidth * faceWidth);
    final boundaryRamp = BoundaryFeather.insideActive(
      mask: masks.hairlineActive,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: math.max(1.0, boundarySmoothFaceWidth * faceWidth),
    );
    final ridgeBlend = math.max(1.5, ridgeBlendFaceWidth * faceWidth);
    final active = <int>[];
    final outDx = <double>[];
    final outDy = <double>[];
    if (interior != null && !line.isEmpty) {
      final pixelCount = width * height;
      for (var i = 0; i < pixelCount; i++) {
        if (masks.hairlineActive[i] == 0) {
          continue;
        }
        final boundary = boundaryRamp[i];
        if (boundary <= 1e-6) {
          continue;
        }
        final x = (i % width) + 0.5;
        final y = (i ~/ width) + 0.5;
        final hit = RidgeWeight.project(
          ridge: line,
          x: x,
          y: y,
          blendPx: ridgeBlend,
        );
        final vx = x - hit.qx;
        final vy = y - hit.qy;
        if (vx * vx + vy * vy < 1.0) {
          continue;
        }
        final away = vx * (hit.qx - interior.dx) + vy * (hit.qy - interior.dy);
        if (away <= 0) {
          continue;
        }
        final along = hit.alongWeight;
        if (along <= 1e-6) {
          continue;
        }
        final weight = boundary * along;
        if (weight <= 1e-6) {
          continue;
        }
        active.add(i);
        outDx.add(vx * weight);
        outDy.add(vy * weight);
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
    required double signedScale,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = signedScale * unitDx[k];
      field.dy[i] = signedScale * unitDy[k];
    }
  }

  static double crownExtendPx(List<Offset?> px, double faceWidth) {
    final top = px.length > 10 ? px[10] : null;
    if (top == null) {
      return 0;
    }
    final pad = math.max(6.0, hullPadFaceWidth * faceWidth);
    final room = math.max(0.0, top.dy - pad - crownMarginPx);
    return math.min(room, crownExtendFaceWidth * faceWidth);
  }

  static Offset? crownApex(List<Offset?> px, double faceWidth) {
    final top = px.length > 10 ? px[10] : null;
    if (top == null) {
      return null;
    }
    return Offset(top.dx, top.dy - crownExtendPx(px, faceWidth));
  }

  static List<Offset> _crownPoints(List<Offset?> px, double faceWidth) {
    final lift = crownExtendPx(px, faceWidth);
    if (lift <= 1e-6) {
      return const [];
    }
    final out = <Offset>[];
    for (final id in const [103, 67, 109, 10, 338, 297, 332]) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        out.add(Offset(p.dx, p.dy - lift));
      }
    }
    return out;
  }

  /// Banda do cabelo: arco da linha + o mesmo arco levantado ao cap.
  static List<Offset> _hairBand(List<Offset?> px, double faceWidth) {
    final lift = crownExtendPx(px, faceWidth);
    if (lift <= 1e-6) {
      return const [];
    }
    const lower = [21, 103, 67, 109, 10, 338, 297, 332, 251];
    const upper = [332, 297, 338, 10, 109, 67, 103];
    final ring = <Offset>[];
    for (final id in lower) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        ring.add(p);
      }
    }
    for (final id in upper) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        ring.add(Offset(p.dx, p.dy - lift));
      }
    }
    return ring.length >= 3 ? ring : const [];
  }

  static List<RidgeNode> _hairlineRidge(List<Offset?> px) {
    final anchors = <RidgeNode>[];
    for (var i = 0; i < lineIds.length; i++) {
      final id = lineIds[i];
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        anchors.add((p: p, weight: lineWeights[i]));
      }
    }
    return RidgeWeight.densify(anchors);
  }
}
