import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import 'cheekbones_masks.dart';
import 'cheekbones_metrics.dart';

class CheekbonesFieldBuild {
  const CheekbonesFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
    required this.leftPad,
    required this.rightPad,
  });

  final DisplacementField field;
  final CheekbonesMasks masks;
  final CheekbonesFieldMetrics metrics;
  final CheekbonesMalarPad? leftPad;
  final CheekbonesMalarPad? rightPad;
}

/// Constrói o campo cheekbones (só Δx, para a midline). Sem RGBA, sem render.
///
/// Hipótese H: crista no oval (234→93→132→58). Não é MLS. Não é A1/A2.
abstract final class CheekbonesField {
  CheekbonesField._();

  /// Primários de métrica (largura malar). Não são o centro do plateau.
  /// 352 é o espelho de 123. 411 é o espelho de 187 (bolbo baixo) — não usar.
  static const primaryLeft = 123;
  static const primaryRight = 352;

  /// Pálpebra inferior — âncora superior. O centro do pad NÃO fica aqui.
  static const orbitLowerLeft = 145;
  static const orbitLowerRight = 374;
  static const lateralLeft = 116;
  static const lateralRight = 345;
  static const midCheekLeft = 147;
  static const midCheekRight = 376;
  static const earLeft = 323;
  static const earRight = 454;
  /// Oval na junta orelha–bochecha. 323/454 são o mesmo sítio à direita.
  static const ovalUpperLeft = 234;
  static const ovalUpperRight = 454;
  static const ovalMidLeft = 93;
  static const ovalMidRight = 323;

  /// Paragem inferior — não é handle (evita o bolbo baixo). 411 espelha 187.
  static const lowerStopLeft = 187;
  static const lowerStopRight = 411;
  static const sulcusLeft = 203;
  static const sulcusRight = 423;
  /// Entalhe oval entre maçã e gônio. Sem isto o contorno faz S (vale no max das gaussianas).
  static const jawNotchLeft = 132;
  static const jawNotchRight = 361;

  /// Domínio Jaw — hard-zero. IDs copiados; não importa JawField.
  static const jawDomainPrimary = {58, 288, 132, 361};
  static const jawDomainSecondary = {172, 136, 365, 397};

  static Set<int> get jawDomainLandmarks => {
        ...jawDomainPrimary,
        ...jawDomainSecondary,
      };

  /// Domínio Chin — hard-zero. IDs copiados; não importa ChinField.
  static const chinDomainLandmarks = {152, 148, 176, 149, 377, 400, 378};

  static const gonionLeft = 58;
  static const gonionRight = 288;
  static const chinTip = 152;

  /// Semente de Lab. Não é contrato; calibrável sem mudar arquitectura.
  /// 0.04 saturava um buraco na eminência (t=1). Meitu puxa ~metade disso.
  static const amplitudeFaceWidth = 0.022;
  /// Rampa a partir de nariz/boca/chin. Olhos são hard-zero.
  /// Orelha: pina deslocada para fora do oval — 323/454 são silhueta, não cadeado.
  /// Gônio não é hard-zero: cauda leve no ângulo mandibular.
  static const falloffFaceWidth = 0.12;
  /// Rampa curta na orelha: evita fold sem comer o malar (0.12 comia o lado direito).
  static const earFalloffFaceWidth = 0.035;

  static CheekbonesFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('cheekbones_field_invalid_size: ${width}x$height');
    }

    final px = CheekbonesMasks.landmarkPixels(face, imageSize);
    final geometry = _geometry(px);
    final leftPad = CheekbonesMalarPad.fromHandles(
      orbitLower: _at(px, orbitLowerLeft),
      ovalUpper: _at(px, ovalUpperLeft),
      ovalMid: _at(px, ovalMidLeft),
      jawNotch: _at(px, jawNotchLeft),
      gonion: _at(px, gonionLeft),
      lateral: _at(px, lateralLeft),
      leftSide: true,
      faceWidth: geometry.faceWidth,
    );
    final rightPad = CheekbonesMalarPad.fromHandles(
      orbitLower: _at(px, orbitLowerRight),
      ovalUpper: _at(px, ovalUpperRight),
      ovalMid: _at(px, ovalMidRight),
      jawNotch: _at(px, jawNotchRight),
      gonion: _at(px, gonionRight),
      lateral: _at(px, lateralRight),
      leftSide: false,
      faceWidth: geometry.faceWidth,
    );
    final masks = CheekbonesMasks.build(
      face: face,
      imageSize: imageSize,
      jawDomainLandmarks: jawDomainLandmarks,
      chinDomainLandmarks: chinDomainLandmarks,
      leftPad: leftPad,
      rightPad: rightPad,
    );
    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);
    final ampScale = amplitudeFaceWidth * geometry.faceWidth;
    // Foto esquerda = malar MediaPipe direito; foto direita = malar MediaPipe esquerdo.
    final amplitudeMpLeft = signedRight * ampScale;
    final amplitudeMpRight = signedLeft * ampScale;
    final amplitude = math.max(amplitudeMpLeft.abs(), amplitudeMpRight.abs());

    final field = DisplacementField.zeros(width: width, height: height);
    if (amplitude > 1e-6 && masks.count(masks.cheekActive) > 0) {
      _applyDisplacement(
        field: field,
        masks: masks,
        leftPad: leftPad,
        rightPad: rightPad,
        midlineX: geometry.midlineX,
        amplitudeMpLeft: amplitudeMpLeft,
        amplitudeMpRight: amplitudeMpRight,
        falloff: math.max(12.0, falloffFaceWidth * geometry.faceWidth),
        earFalloff: math.max(6.0, earFalloffFaceWidth * geometry.faceWidth),
      );
    }

    final metrics = CheekbonesFieldMetrics.compute(
      field: field,
      masks: masks,
      px: px,
      faceWidth: geometry.faceWidth,
      cheekAmplitude: amplitude.abs(),
      primaryLeft: primaryLeft,
      primaryRight: primaryRight,
      gonionLeft: gonionLeft,
      gonionRight: gonionRight,
      chinTip: chinTip,
    );
    return CheekbonesFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
      leftPad: leftPad,
      rightPad: rightPad,
    );
  }

  static Offset? _at(List<Offset?> px, int id) {
    if (id < 0 || id >= px.length) {
      return null;
    }
    return px[id];
  }

  static ({double faceWidth, double midlineX, List<Offset> oval}) _geometry(
    List<Offset?> px,
  ) {
    final oval = <Offset>[];
    for (final id in V2RegionCatalog.faceOval) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        oval.add(p);
      }
    }
    if (oval.isEmpty) {
      return (faceWidth: 1.0, midlineX: 0, oval: const <Offset>[]);
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
      oval: oval,
    );
  }

  static void _applyDisplacement({
    required DisplacementField field,
    required CheekbonesMasks masks,
    required CheekbonesMalarPad? leftPad,
    required CheekbonesMalarPad? rightPad,
    required double midlineX,
    required double amplitudeMpLeft,
    required double amplitudeMpRight,
    required double falloff,
    required double earFalloff,
  }) {
    final inactive = Uint8List(field.pixelCount);
    final earSeed = Uint8List(field.pixelCount);
    for (var i = 0; i < inactive.length; i++) {
      if (masks.cheekActive[i] == 0 && masks.ears[i] == 0) {
        inactive[i] = 255;
      }
      if (masks.ears[i] != 0) {
        earSeed[i] = 255;
      }
    }
    final dist = _distanceToProtected(
      inactive,
      field.width,
      field.height,
    );
    final distEar = _distanceToProtected(
      earSeed,
      field.width,
      field.height,
    );
    for (var i = 0; i < field.pixelCount; i++) {
      if (masks.cheekActive[i] == 0 || masks.ears[i] != 0) {
        continue;
      }
      final x = (i % field.width) + 0.5;
      final y = (i ~/ field.width) + 0.5;
      final wL = leftPad?.weight(x, y) ?? 0;
      final wR = rightPad?.weight(x, y) ?? 0;
      final useLeft = wL >= wR;
      final pad = useLeft ? wL : wR;
      final amp = useLeft ? amplitudeMpLeft : amplitudeMpRight;
      final boundary = math.min(1.0, dist[i] / falloff);
      final earBoundary = math.min(1.0, distEar[i] / earFalloff);
      final weight = pad * boundary * earBoundary;
      if (weight <= 1e-6 || amp.abs() <= 1e-6) {
        continue;
      }
      final toward = midlineX - x;
      if (toward.abs() < 1e-6) {
        continue;
      }
      field.dx[i] = toward.sign * amp * weight;
      field.dy[i] = 0;
    }
  }

  static Float32List _distanceToProtected(
    Uint8List protected,
    int width,
    int height,
  ) {
    const inf = 1e8;
    final dist = Float32List(width * height);
    for (var i = 0; i < dist.length; i++) {
      dist[i] = protected[i] != 0 ? 0 : inf;
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        if (x > 0) {
          dist[i] = math.min(dist[i], dist[i - 1] + 1);
        }
        if (y > 0) {
          dist[i] = math.min(dist[i], dist[i - width] + 1);
        }
      }
    }
    for (var y = height - 1; y >= 0; y--) {
      for (var x = width - 1; x >= 0; x--) {
        final i = y * width + x;
        if (x + 1 < width) {
          dist[i] = math.min(dist[i], dist[i + 1] + 1);
        }
        if (y + 1 < height) {
          dist[i] = math.min(dist[i], dist[i + width] + 1);
        }
      }
    }
    return dist;
  }
}
