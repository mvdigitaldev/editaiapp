import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import '../ridge_weight.dart';
import 'v_shape_masks.dart';
import 'v_shape_metrics.dart';

class VShapeFieldBuild {
  const VShapeFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final VShapeMasks masks;
  final VShapeFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dx` por lado.
class VShapeFieldRuntime {
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
  VShapeMasks? masks;

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

/// Constrói o campo V Shape (só Δx, silhueta externa). Sem RGBA, sem render.
///
/// Crista no oval: 58→172→136 / 288→397→365. Sem gaussiana à parte.
/// Não importa V Chin/Chin/Jaw/Cheekbones.
abstract final class VShapeField {
  VShapeField._();

  static const primaryLeft = 172;
  static const primaryRight = 397;
  static const chinTip = 152;
  static const innerLeft = 148;
  static const innerRight = 377;

  /// Ordem do oval, de cima para baixo: cauda na lateral do rosto → gónio →
  /// pico na curva da mandíbula → cauda para o mento. Não voltar atrás: isso
  /// corta a crista (fold / corte seco).
  ///
  /// A crista era só `58 → 172 → 136` com `0.20 → 1.00 → 0.62`, e caía a um
  /// quinto no gónio. Somada ao Jaw, que na silhueta é um planalto, dava um
  /// bico: com ambos no extremo, 23,5 px no 172 contra 14 px nos vizinhos.
  /// As duas caudas espalham o efeito pela silhueta com pouca intensidade em
  /// vez de o concentrar num arco de 35 px.
  static const curveLeft = [93, 132, 58, 172, 136, 150];
  static const curveRight = [323, 361, 288, 397, 365, 379];
  static const curveWeights = [0.06, 0.28, 0.68, 1.00, 0.86, 0.45];

  static const hullLandmarks = {172, 136, 58, 397, 365, 288, 152};
  static const chinTipLandmarks = {152};
  static const innerPadLandmarks = {148, 176, 149, 377, 400, 378};

  /// Onde as caudas actuam. Sem isto o peso baixo não tem domínio e a extensão
  /// da crista não muda nada.
  static const taperLandmarks = {132, 361, 93, 323, 150, 379};

  /// Régua da zona do Jaw. Já não corta o campo — ver [VShapeMasks.build] — mas
  /// as métricas continuam a medi-la para se saber quanto lá entra.
  static const metricJawLandmarks = {132, 361};

  static const amplitudeFaceWidth = 0.055;
  static const falloffFaceWidth = 0.16;
  static const hullPadFaceWidth = 0.09;
  static const sigmaAcrossFaceWidth = 0.13;
  static const midBlendFaceWidth = 0.10;
  static const innerNotchFaceWidth = 0.038;
  static const tipNotchFaceWidth = 0.028;

  /// Largura da troca de segmento na crista. Ver [RidgeWeight].
  static const ridgeBlendFaceWidth = 0.012;

  /// Borrão da rampa de fronteira. Ver [BoundaryFeather]: sem isto a medial
  /// axis do domínio imprime um vinco diagonal na bochecha.
  static const boundarySmoothFaceWidth = 0.022;

  static VShapeFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    VShapeFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('v_shape_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amplitudeMpLeft = signedRight * runtime.ampScale;
      final amplitudeMpRight = signedLeft * runtime.ampScale;
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
          ? VShapeFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: VShapeMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              vShapeAmplitude: amplitude,
              primaryLeft: primaryLeft,
              primaryRight: primaryRight,
              innerLeft: innerLeft,
              innerRight: innerRight,
              chinTip: chinTip,
              gonionLeft: V2RegionCatalog.gonionLeft,
              gonionRight: V2RegionCatalog.gonionRight,
            )
          : VShapeFieldMetrics.skipped;
      return VShapeFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = VShapeMasks.landmarkPixels(face, imageSize);
    final geometry = _geometry(px);
    final masks = VShapeMasks.build(
      face: face,
      imageSize: imageSize,
      hullLandmarks: hullLandmarks,
      jawDomainLandmarks: metricJawLandmarks,
      taperLandmarks: taperLandmarks,
      chinTipLandmarks: chinTipLandmarks,
      innerPadLandmarks: innerPadLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final ampScale = amplitudeFaceWidth * geometry.faceWidth;
    // Meitu: direita do slider (t>0) = V para dentro. Foto esquerda = cadeia MP direita.
    final amplitudeMpLeft = signedRight * ampScale;
    final amplitudeMpRight = signedLeft * ampScale;
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
        ? VShapeFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: geometry.faceWidth,
            vShapeAmplitude: amplitude.abs(),
            primaryLeft: primaryLeft,
            primaryRight: primaryRight,
            innerLeft: innerLeft,
            innerRight: innerRight,
            chinTip: chinTip,
            gonionLeft: V2RegionCatalog.gonionLeft,
            gonionRight: V2RegionCatalog.gonionRight,
          )
        : VShapeFieldMetrics.skipped;
    return VShapeFieldBuild(field: field, masks: masks, metrics: metrics);
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
    required VShapeMasks masks,
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
    final innerNotch = math.max(6.0, innerNotchFaceWidth * faceWidth);
    final tipNotch = math.max(5.0, tipNotchFaceWidth * faceWidth);
    final innerPts = _points(px, innerPadLandmarks);
    final tipPts = _points(px, chinTipLandmarks);
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
      final innerGate = _notchGate(innerPts, x, y, innerNotch);
      final tipGate = _notchGate(tipPts, x, y, tipNotch);
      final weight = pad * boundary * midGate * innerGate * tipGate;
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

  static List<({Offset p, double weight})> _curveRidge(
    List<Offset?> px,
    List<int> ids,
  ) {
    final anchors = <({Offset p, double weight})>[];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        anchors.add((p: p, weight: curveWeights[i]));
      }
    }
    return RidgeWeight.densify(anchors);
  }

  static List<Offset> _points(List<Offset?> px, Set<int> ids) {
    final out = <Offset>[];
    for (final id in ids) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        out.add(p);
      }
    }
    return out;
  }

  static double _notchGate(List<Offset> notches, double x, double y, double radius) {
    if (radius < 1e-6 || notches.isEmpty) {
      return 1;
    }
    var gate = 1.0;
    for (final p in notches) {
      final ddx = x - p.dx;
      final ddy = y - p.dy;
      final t = math.sqrt(ddx * ddx + ddy * ddy) / radius;
      if (t >= 1) {
        continue;
      }
      final s = t * t * (3 - 2 * t);
      if (s < gate) {
        gate = s;
      }
    }
    return gate;
  }

}
