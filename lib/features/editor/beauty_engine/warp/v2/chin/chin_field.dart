import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import '../ridge_weight.dart';
import 'chin_masks.dart';
import 'chin_metrics.dart';

class ChinFieldBuild {
  const ChinFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final ChinMasks masks;
  final ChinFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dy`.
class ChinFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitWeight;
  List<int>? active;
  DisplacementField? field;
  ChinMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitWeight != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Constrói o campo chin (só Δy). Sem RGBA, sem render, sem produto.
///
/// `t ∈ [-1, 1]`: t>0 encurta (152 sobe); t<0 alonga (152 desce); t=0 identidade.
/// Crista no oval do mento até perto da mandíbula (172/397). Sem max(gaussianas).
abstract final class ChinField {
  ChinField._();

  /// Handle principal de métrica (MediaPipe mento).
  static const primaryHandles = {152};

  /// Oval esquerdo: mento → perto da mandíbula. Para em 172, não no gônio 58.
  static const curveLeft = [152, 148, 176, 149, 150, 136, 172];

  /// Oval direito: mento → perto da mandíbula. Para em 397, não no gônio 288.
  static const curveRight = [152, 377, 400, 378, 379, 365, 397];

  /// Pesos na crista (mesmo comprimento que [curveLeft] / [curveRight]).
  static const curveWeights = [1.00, 0.90, 0.78, 0.60, 0.40, 0.22, 0.08];

  /// Hull activo: curva do queixo até 172/397. Sem 58/288.
  static const hullLandmarks = {
    152, 148, 176, 149, 150, 136, 172,
    377, 400, 378, 379, 365, 397,
  };

  /// Entalhe oval (acima do gônio) — hard-zero. Não é o slider Jaw.
  static const jawNotchLandmarks = {132, 361};

  static Set<int> get jawDomainLandmarks => jawNotchLandmarks;

  static const amplitudeFaceWidth = 0.07;
  static const falloffFaceWidth = 0.12;
  static const hullPadFaceWidth = 0.07;
  static const sigmaAcrossFaceWidth = 0.08;

  /// Largura da troca de segmento na crista. Ver [RidgeWeight]: sem isto o peso
  /// dá um degrau na medial axis e o campo inverte (`minDetJ` −0,046 a t=1).
  static const ridgeBlendFaceWidth = 0.012;

  /// Borrão da rampa de fronteira. Ver [BoundaryFeather].
  static const boundarySmoothFaceWidth = 0.022;

  static ChinFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
    bool computeMetrics = true,
    ChinFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('chin_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amplitude =
          intensity.abs() * amplitudeFaceWidth * runtime.faceWidth;
      final signedAmplitude = -intensity.sign * amplitude;
      _scaleActive(
        field: runtime.field!,
        unitWeight: runtime.unitWeight!,
        active: runtime.active!,
        signedAmplitude: signedAmplitude,
      );
      final metrics = computeMetrics
          ? ChinFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: ChinMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              chinAmplitude: amplitude,
              primaryHandle:
                  primaryHandles.isEmpty ? 152 : primaryHandles.first,
              gonionLeft: V2RegionCatalog.gonionLeft,
              gonionRight: V2RegionCatalog.gonionRight,
            )
          : ChinFieldMetrics.skipped;
      return ChinFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = ChinMasks.landmarkPixels(face, imageSize);
    final masks = ChinMasks.build(
      face: face,
      imageSize: imageSize,
      hullLandmarks: hullLandmarks,
      jawDomainLandmarks: jawDomainLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final faceWidth = _faceWidth(px);
    final amplitude = intensity.abs() * amplitudeFaceWidth * faceWidth;
    final signedAmplitude = -intensity.sign * amplitude;
    final packed = _packUnitWeights(
      width: width,
      height: height,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    if (intensity.abs() > 1e-6 && amplitude > 0) {
      _scaleActive(
        field: field,
        unitWeight: packed.weights,
        active: packed.active,
        signedAmplitude: signedAmplitude,
      );
    }

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitWeight = packed.weights
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final primary = primaryHandles.isEmpty ? 152 : primaryHandles.first;
    final metrics = computeMetrics
        ? ChinFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            chinAmplitude: amplitude,
            primaryHandle: primary,
            gonionLeft: V2RegionCatalog.gonionLeft,
            gonionRight: V2RegionCatalog.gonionRight,
          )
        : ChinFieldMetrics.skipped;
    return ChinFieldBuild(field: field, masks: masks, metrics: metrics);
  }

  static double _faceWidth(List<Offset?> px) {
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

  static ({Float32List weights, List<int> active}) _packUnitWeights({
    required int width,
    required int height,
    required ChinMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final left = _curveRidge(px, curveLeft);
    final right = _curveRidge(px, curveRight);
    final falloff = math.max(12.0, falloffFaceWidth * faceWidth);
    final boundaryRamp = BoundaryFeather.insideActive(
      mask: masks.chinActive,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: math.max(1.0, boundarySmoothFaceWidth * faceWidth),
    );
    final sigmaAcross = math.max(8.0, sigmaAcrossFaceWidth * faceWidth);
    final ridgeBlend = math.max(1.5, ridgeBlendFaceWidth * faceWidth);
    final active = <int>[];
    final weights = <double>[];
    if (left.length >= 2 || right.length >= 2) {
      final pixelCount = width * height;
      for (var i = 0; i < pixelCount; i++) {
        if (masks.chinActive[i] == 0) {
          continue;
        }
        final x = (i % width) + 0.5;
        final y = (i ~/ width) + 0.5;
        final boundary = boundaryRamp[i];
        final ridge = math.max(
          RidgeWeight.at(
            nodes: left,
            x: x,
            y: y,
            sigmaAcross: sigmaAcross,
            blendPx: ridgeBlend,
          ),
          RidgeWeight.at(
            nodes: right,
            x: x,
            y: y,
            sigmaAcross: sigmaAcross,
            blendPx: ridgeBlend,
          ),
        );
        final weight = boundary * ridge;
        if (weight <= 1e-6) {
          continue;
        }
        active.add(i);
        weights.add(weight);
      }
    }
    return (
      weights: Float32List.fromList(weights),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitWeight,
    required List<int> active,
    required double signedAmplitude,
  }) {
    for (var k = 0; k < active.length; k++) {
      field.dy[active[k]] = signedAmplitude * unitWeight[k];
    }
  }

  /// Polilinha com pontos médios — evita vales de `max(gaussianas)` na curva.
  static List<RidgeNode> _curveRidge(List<Offset?> px, List<int> ids) {
    final anchors = <RidgeNode>[];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        anchors.add((p: p, weight: curveWeights[i]));
      }
    }
    return RidgeWeight.densify(anchors);
  }
}
