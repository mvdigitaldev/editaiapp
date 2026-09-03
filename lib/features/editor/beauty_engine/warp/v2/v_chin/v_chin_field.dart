import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import '../ridge_weight.dart';
import 'v_chin_masks.dart';
import 'v_chin_metrics.dart';

class VChinFieldBuild {
  const VChinFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final VChinMasks masks;
  final VChinFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dx` por lado.
class VChinFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  double ampScale = 1;
  Float32List? unitWeight;
  Int8List? sign;
  Uint8List? useLeft;
  List<int>? active;
  DisplacementField? field;
  VChinMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitWeight != null &&
        sign != null &&
        useLeft != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Constrói o campo V Chin (só Δx, para a midline). Sem RGBA, sem render.
///
/// Crista 148→176→149 / 377→400→378. Não importa Chin/Jaw/Cheekbones.
abstract final class VChinField {
  VChinField._();

  static const primaryLeft = 148;
  static const primaryRight = 377;
  static const chinTip = 152;

  static const curveLeft = [148, 176, 149, 150, 136];
  static const curveRight = [377, 400, 378, 379, 365];
  static const curveWeights = [1.00, 0.78, 0.55, 0.32, 0.14];

  static const hullLandmarks = {
    152, 148, 176, 149, 150, 136, 377, 400, 378, 379, 365,
  };
  static const chinTipLandmarks = {152};
  static const jawDomainLandmarks = {58, 288, 132, 361};

  static const amplitudeFaceWidth = 0.080;
  static const falloffFaceWidth = 0.12;
  static const hullPadFaceWidth = 0.06;
  static const sigmaAcrossFaceWidth = 0.11;
  static const midBlendFaceWidth = 0.11;

  /// Largura da troca de segmento na crista. Ver [RidgeWeight]: sem isto o peso
  /// dá um degrau na medial axis e, com a amplitude deste efeito, o campo
  /// inverte (`minDetJ` −0,40 a t=1).
  static const ridgeBlendFaceWidth = 0.012;

  /// Borrão da rampa de fronteira. Ver [BoundaryFeather].
  static const boundarySmoothFaceWidth = 0.022;

  static VChinFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    VChinFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('v_chin_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amplitudeMpLeft = -signedRight * runtime.ampScale;
      final amplitudeMpRight = -signedLeft * runtime.ampScale;
      _scaleActive(
        field: runtime.field!,
        unitWeight: runtime.unitWeight!,
        sign: runtime.sign!,
        useLeft: runtime.useLeft!,
        active: runtime.active!,
        amplitudeMpLeft: amplitudeMpLeft,
        amplitudeMpRight: amplitudeMpRight,
      );
      final amplitude =
          math.max(amplitudeMpLeft.abs(), amplitudeMpRight.abs());
      final metrics = computeMetrics
          ? VChinFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: VChinMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              vChinAmplitude: amplitude,
              primaryLeft: primaryLeft,
              primaryRight: primaryRight,
              chinTip: chinTip,
              gonionLeft: V2RegionCatalog.gonionLeft,
              gonionRight: V2RegionCatalog.gonionRight,
            )
          : VChinFieldMetrics.skipped;
      return VChinFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = VChinMasks.landmarkPixels(face, imageSize);
    final geometry = _geometry(px);
    final masks = VChinMasks.build(
      face: face,
      imageSize: imageSize,
      hullLandmarks: hullLandmarks,
      jawDomainLandmarks: jawDomainLandmarks,
      chinTipLandmarks: chinTipLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final ampScale = amplitudeFaceWidth * geometry.faceWidth;
    // Meitu: esquerda do slider (t<0) = V para dentro. Foto esquerda = cadeia MP direita.
    final amplitudeMpLeft = -signedRight * ampScale;
    final amplitudeMpRight = -signedLeft * ampScale;
    final amplitude = math.max(amplitudeMpLeft.abs(), amplitudeMpRight.abs());
    final packed = _packUnitWeights(
      width: width,
      height: height,
      masks: masks,
      px: px,
      midlineX: geometry.midlineX,
      faceWidth: geometry.faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    if (amplitude > 1e-6) {
      _scaleActive(
        field: field,
        unitWeight: packed.unitWeight,
        sign: packed.sign,
        useLeft: packed.useLeft,
        active: packed.active,
        amplitudeMpLeft: amplitudeMpLeft,
        amplitudeMpRight: amplitudeMpRight,
      );
    }

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = geometry.faceWidth
        ..ampScale = ampScale
        ..unitWeight = packed.unitWeight
        ..sign = packed.sign
        ..useLeft = packed.useLeft
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? VChinFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: geometry.faceWidth,
            vChinAmplitude: amplitude.abs(),
            primaryLeft: primaryLeft,
            primaryRight: primaryRight,
            chinTip: chinTip,
            gonionLeft: V2RegionCatalog.gonionLeft,
            gonionRight: V2RegionCatalog.gonionRight,
          )
        : VChinFieldMetrics.skipped;
    return VChinFieldBuild(field: field, masks: masks, metrics: metrics);
  }

  static ({double faceWidth, double midlineX}) _geometry(List<Offset?> px) {
    final oval = <Offset>[];
    for (final id in V2RegionCatalog.faceOval) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        oval.add(p);
      }
    }
    if (oval.isEmpty) {
      return (faceWidth: 1.0, midlineX: 0);
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    var sumX = 0.0;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      sumX += p.dx;
    }
    return (
      faceWidth: math.max(maxX - minX, 1.0),
      midlineX: sumX / oval.length,
    );
  }

  static ({
    Float32List unitWeight,
    Int8List sign,
    Uint8List useLeft,
    List<int> active,
  }) _packUnitWeights({
    required int width,
    required int height,
    required VChinMasks masks,
    required List<Offset?> px,
    required double midlineX,
    required double faceWidth,
  }) {
    final left = Ridge.of(_curveRidge(px, curveLeft));
    final right = Ridge.of(_curveRidge(px, curveRight));
    final sigmaAcross = math.max(6.0, sigmaAcrossFaceWidth * faceWidth);
    final ridgeBlend = math.max(1.5, ridgeBlendFaceWidth * faceWidth);
    final falloff = math.max(12.0, falloffFaceWidth * faceWidth);
    final midBlend = math.max(8.0, midBlendFaceWidth * faceWidth);
    final boundaryRamp = BoundaryFeather.insideActive(
      mask: masks.chinActive,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: math.max(1.0, boundarySmoothFaceWidth * faceWidth),
    );
    final pixelCount = width * height;
    final active = <int>[];
    final weights = <double>[];
    final signs = <int>[];
    final leftFlags = <int>[];
    for (var i = 0; i < pixelCount; i++) {
      if (masks.chinActive[i] == 0) {
        continue;
      }
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      final toward = midlineX - x;
      if (toward.abs() < 1e-6) {
        continue;
      }
      // A crista é o passo caro do laço: só se avalia depois de a fronteira,
      // que é uma leitura, mostrar que o pixel não sai já a zero.
      final boundary = boundaryRamp[i];
      if (boundary <= 1e-6) {
        continue;
      }
      final ridge = RidgeWeight.stronger(
        a: left,
        b: right,
        x: x,
        y: y,
        sigmaAcross: sigmaAcross,
        blendPx: ridgeBlend,
      );
      final mpLeft = ridge.aWins;
      final pad = ridge.weight;
      final midGate = math.min(1.0, toward.abs() / midBlend);
      final weight = pad * boundary * midGate;
      if (weight <= 1e-6) {
        continue;
      }
      active.add(i);
      weights.add(weight);
      signs.add(toward.sign.toInt());
      leftFlags.add(mpLeft ? 1 : 0);
    }
    return (
      unitWeight: Float32List.fromList(weights),
      sign: Int8List.fromList(signs),
      useLeft: Uint8List.fromList(leftFlags),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitWeight,
    required Int8List sign,
    required Uint8List useLeft,
    required List<int> active,
    required double amplitudeMpLeft,
    required double amplitudeMpRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      final amp = useLeft[k] != 0 ? amplitudeMpLeft : amplitudeMpRight;
      field.dx[i] = sign[k] * amp * unitWeight[k];
      field.dy[i] = 0;
    }
  }

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
