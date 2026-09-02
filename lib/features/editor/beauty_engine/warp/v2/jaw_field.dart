import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/face_landmark.dart';
import '../../models/face_mesh_result.dart';
import 'boundary_feather.dart';
import 'displacement_field.dart';
import 'field_metrics.dart';
import 'region_catalog.dart';
import 'region_masks.dart';
import 'ridge_weight.dart';

class JawFieldBuild {
  const JawFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final RegionMasks masks;
  final FieldMetrics metrics;
}

/// Constrói o domínio geométrico e o campo jaw (só Δx). Sem RGBA, sem render.
abstract final class JawField {
  JawField._();

  /// Amplitude lab @ t=1, fracção da largura da face. Não usa ExtendedRoiConfig.
  static const amplitudeFaceWidth = 0.04;

  /// Largura da rampa na fronteira da máscara activa, fracção da face.
  static const falloffFaceWidth = 0.12;

  /// Rampa curta na pina. A orelha não entra na rampa longa: a 0.12 ela puxava
  /// a cauda do lado direito para um terço do lado esquerdo.
  static const earFalloffFaceWidth = 0.035;

  /// Dilatação do hull para os gônios ficarem no planalto (não na rampa).
  static const silhouettePadFaceWidth = 0.08;

  /// Crista da silhueta, de cima para baixo: cauda na lateral do rosto →
  /// ramo → gônio → curva → cauda para o mento. Não inverter a ordem: voltar
  /// atrás corta a crista. O peso interpola ao longo da polilinha, com pico no
  /// gônio. Substitui o `max` de gaussianas por landmark, que ondulava entre
  /// âncoras e fazia quina onde duas empatavam — o serrilhado do ramo 132→58.
  ///
  /// 234/93 (e 454/323) levam peso baixo de propósito: sem essa cauda o
  /// estreitamento acabava em ponta no 132, porque acima dele o pixel saía do
  /// domínio e o deslocamento caía de golpe para zero.
  static const curveLeft = [234, 93, 132, 58, 172, 136];
  static const curveRight = [454, 323, 361, 288, 397, 365];
  static const curveWeights = [0.05, 0.20, 0.85, 1.00, 0.90, 0.65];

  /// Lateral do rosto acima do ramo mandibular. Entra no hull para a cauda de
  /// peso baixo ter domínio onde actuar; sem isto o peso não tem efeito.
  static const taperLandmarks = {234, 93, 454, 323};

  /// Raio transversal da crista, fracção da face.
  static const sigmaAcrossFaceWidth = 0.08;

  /// Largura da troca de segmento na crista. Ver [RidgeWeight].
  static const ridgeBlendFaceWidth = 0.012;

  /// Borrão das rampas de fronteira. Ver [BoundaryFeather].
  static const boundarySmoothFaceWidth = 0.022;

  static JawFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('jaw_field_invalid_size: ${width}x$height');
    }

    final px = _landmarkPixels(face, imageSize);
    final masks = _buildMasks(px, width, height);
    final geometry = _geometry(px);
    final intensity = t.clamp(0.0, 1.0);
    final amplitude = intensity * amplitudeFaceWidth * geometry.faceWidth;

    final field = DisplacementField.zeros(width: width, height: height);
    if (intensity > 0 && amplitude > 0 && masks.count(masks.jawActive) > 0) {
      _applyNarrowing(
        field: field,
        masks: masks,
        px: px,
        midlineX: geometry.midlineX,
        amplitude: amplitude,
        falloff: math.max(12.0, falloffFaceWidth * geometry.faceWidth),
        earFalloff: math.max(6.0, earFalloffFaceWidth * geometry.faceWidth),
        sigmaAcross: math.max(8.0, sigmaAcrossFaceWidth * geometry.faceWidth),
        ridgeBlend: math.max(1.5, ridgeBlendFaceWidth * geometry.faceWidth),
        boundarySmooth: math.max(
          1.0,
          boundarySmoothFaceWidth * geometry.faceWidth,
        ),
      );
    }

    final extrema = _pairWidth(px, field, V2RegionCatalog.jawLandmarks);
    final gonions = _gonionWidth(px, field);
    final metrics = FieldMetrics.compute(
      field: field,
      masks: masks,
      faceWidth: geometry.faceWidth,
      jawAmplitude: amplitude,
      jawWidthBefore: extrema.before,
      jawWidthAfter: extrema.after,
      gonionWidthBefore: gonions.before,
      gonionWidthAfter: gonions.after,
      dxAtGonionLeft: gonions.dxLeft,
      dxAtGonionRight: gonions.dxRight,
    );
    return JawFieldBuild(field: field, masks: masks, metrics: metrics);
  }

  static List<Offset?> _landmarkPixels(FaceMeshResult face, Size imageSize) {
    final out = List<Offset?>.filled(FaceMeshResult.expectedLandmarkCount, null);
    for (final FaceLandmark lm in face.landmarks) {
      if (lm.index < 0 || lm.index >= out.length) {
        continue;
      }
      out[lm.index] = Offset(
        lm.normalized.dx * imageSize.width,
        lm.normalized.dy * imageSize.height,
      );
    }
    return out;
  }

  static List<Offset> _points(List<Offset?> px, Set<int> indices) {
    final out = <Offset>[];
    for (final id in indices) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        out.add(p);
      }
    }
    return out;
  }

  static RegionMasks _buildMasks(List<Offset?> px, int width, int height) {
    final oval = RegionMaskRaster.zeros(width, height);
    final jaw = RegionMaskRaster.zeros(width, height);
    final eyes = RegionMaskRaster.zeros(width, height);
    final brows = RegionMaskRaster.zeros(width, height);
    final nose = RegionMaskRaster.zeros(width, height);
    final mouth = RegionMaskRaster.zeros(width, height);
    final ears = RegionMaskRaster.zeros(width, height);
    final beard = RegionMaskRaster.zeros(width, height);

    final ovalRing = _points(px, V2RegionCatalog.faceOval);
    if (ovalRing.length >= 3) {
      RegionMaskRaster.fillPolygon(oval, width, height, ovalRing);
    }

    RegionMaskRaster.fillConvexHull(
      jaw,
      width,
      height,
      _points(px, {...V2RegionCatalog.jawLandmarks, ...taperLandmarks}),
    );
    final pad = math.max(8, (silhouettePadFaceWidth * _faceWidth(px)).round());
    RegionMaskRaster.dilate(jaw, width, height, pad);
    RegionMaskRaster.fillConvexHull(
      eyes,
      width,
      height,
      _points(px, V2RegionCatalog.eyes),
    );
    RegionMaskRaster.fillConvexHull(
      brows,
      width,
      height,
      _points(px, V2RegionCatalog.brows),
    );
    RegionMaskRaster.fillConvexHull(
      nose,
      width,
      height,
      _points(px, V2RegionCatalog.nose),
    );
    RegionMaskRaster.fillConvexHull(
      mouth,
      width,
      height,
      _points(px, V2RegionCatalog.lips),
    );

    // 323/454 estão no oval, não na pina: são a lateral do rosto, espelho de
    // 93/234. Disco centrado neles comia a silhueta do lado direito e travava
    // a cauda, o que deixava os dois lados assimétricos. Mesma solução já
    // validada no Cheekbones: trava a pina deslocada para fora do oval.
    final faceWidth = _faceWidth(px);
    final earRadius = 0.022 * faceWidth;
    final pinnaOut = 0.05 * faceWidth;
    final midlineX = _geometry(px).midlineX;
    for (final id in V2RegionCatalog.ears) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        final away = p.dx >= midlineX ? 1.0 : -1.0;
        RegionMaskRaster.fillDisk(
          ears,
          width,
          height,
          Offset(p.dx + away * pinnaOut, p.dy),
          earRadius,
        );
      }
    }

    _fillBeardProxy(
      beard: beard,
      oval: oval,
      px: px,
      width: width,
      height: height,
    );

    final faceCenter = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.orInto(faceCenter, eyes);
    RegionMaskRaster.orInto(faceCenter, nose);
    RegionMaskRaster.orInto(faceCenter, mouth);

    final protected = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.orInto(protected, eyes);
    RegionMaskRaster.orInto(protected, brows);
    RegionMaskRaster.orInto(protected, nose);
    RegionMaskRaster.orInto(protected, mouth);
    RegionMaskRaster.orInto(protected, faceCenter);
    RegionMaskRaster.orInto(protected, beard);
    RegionMaskRaster.orInto(protected, ears);

    final jawActive = RegionMaskRaster.zeros(width, height);
    for (var i = 0; i < jawActive.length; i++) {
      if (jaw[i] != 0 && protected[i] == 0) {
        jawActive[i] = 255;
      }
    }

    return RegionMasks(
      width: width,
      height: height,
      jaw: jaw,
      jawActive: jawActive,
      eyes: eyes,
      brows: brows,
      nose: nose,
      mouth: mouth,
      faceCenter: faceCenter,
      beard: beard,
      ears: ears,
      protected: protected,
      oval: oval,
    );
  }

  static void _fillBeardProxy({
    required Uint8List beard,
    required Uint8List oval,
    required List<Offset?> px,
    required int width,
    required int height,
  }) {
    final lips = _points(px, V2RegionCatalog.lips);
    final chin = V2RegionCatalog.chinTip < px.length
        ? px[V2RegionCatalog.chinTip]
        : null;
    if (lips.isEmpty || chin == null) {
      return;
    }
    var lipBottom = lips.first.dy;
    var lipMinX = lips.first.dx;
    var lipMaxX = lips.first.dx;
    for (final p in lips) {
      lipBottom = math.max(lipBottom, p.dy);
      lipMinX = math.min(lipMinX, p.dx);
      lipMaxX = math.max(lipMaxX, p.dx);
    }
    final y0 = lipBottom + 1;
    final y1 = chin.dy - 1;
    if (y1 <= y0) {
      return;
    }
    final x0 = lipMinX;
    final x1 = lipMaxX;
    final iy0 = y0.floor().clamp(0, height - 1);
    final iy1 = y1.ceil().clamp(0, height - 1);
    final ix0 = x0.floor().clamp(0, width - 1);
    final ix1 = x1.ceil().clamp(0, width - 1);
    for (var y = iy0; y <= iy1; y++) {
      for (var x = ix0; x <= ix1; x++) {
        final i = y * width + x;
        if (oval[i] == 0) {
          continue;
        }
        beard[i] = 255;
      }
    }
  }

  static double _faceWidth(List<Offset?> px) {
    final oval = _points(px, V2RegionCatalog.faceOval);
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

  static ({double faceWidth, double midlineX}) _geometry(List<Offset?> px) {
    final oval = _points(px, V2RegionCatalog.faceOval);
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

  static void _applyNarrowing({
    required DisplacementField field,
    required RegionMasks masks,
    required List<Offset?> px,
    required double midlineX,
    required double amplitude,
    required double falloff,
    required double earFalloff,
    required double sigmaAcross,
    required double ridgeBlend,
    required double boundarySmooth,
  }) {
    // A pina fica fora da rampa longa e ganha rampa própria: senão o disco da
    // orelha entra nos 0.12 e corta a cauda de um só lado.
    final pixelCount = field.pixelCount;
    final inactive = Uint8List(pixelCount);
    final earSeed = Uint8List(pixelCount);
    for (var i = 0; i < pixelCount; i++) {
      if (masks.jawActive[i] == 0 && masks.ears[i] == 0) {
        inactive[i] = 255;
      }
      if (masks.ears[i] != 0) {
        earSeed[i] = 255;
      }
    }
    final boundaryRamp = BoundaryFeather.awayFromInactive(
      mask: inactive,
      width: field.width,
      height: field.height,
      falloffPx: falloff,
      sigmaPx: boundarySmooth,
    );
    final earRamp = BoundaryFeather.awayFromInactive(
      mask: earSeed,
      width: field.width,
      height: field.height,
      falloffPx: earFalloff,
      sigmaPx: boundarySmooth,
    );
    final left = _curveRidge(px, curveLeft);
    final right = _curveRidge(px, curveRight);
    if (left.isEmpty && right.isEmpty) {
      return;
    }
    for (var i = 0; i < pixelCount; i++) {
      if (masks.jawActive[i] == 0) {
        continue;
      }
      final x = (i % field.width) + 0.5;
      final y = (i ~/ field.width) + 0.5;
      final boundary = boundaryRamp[i];
      final earBoundary = earRamp[i];
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
      final weight = boundary * earBoundary * ridge;
      if (weight <= 1e-6) {
        continue;
      }
      final toward = midlineX - x;
      if (toward.abs() < 1e-6) {
        continue;
      }
      field.dx[i] = toward.sign * amplitude * weight;
      field.dy[i] = 0;
    }
  }

  /// Polilinha da crista com um ponto médio entre âncoras consecutivas, para a
  /// distância ao segmento não cortar em curvas fechadas.
  static List<({Offset p, double weight})> _curveRidge(
    List<Offset?> px,
    List<int> ids,
  ) {
    final anchors = <({Offset p, double weight})>[];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        anchors.add((p: p, weight: curveWeights[i]));
      }
    }
    return RidgeWeight.densify(anchors);
  }

  static ({double before, double after}) _pairWidth(
    List<Offset?> px,
    DisplacementField field,
    Set<int> indices,
  ) {
    Offset? left;
    Offset? right;
    for (final id in indices) {
      final p = id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      if (left == null || p.dx < left.dx) {
        left = p;
      }
      if (right == null || p.dx > right.dx) {
        right = p;
      }
    }
    if (left == null || right == null) {
      return (before: 0, after: 0);
    }
    return (
      before: (right.dx - left.dx).abs(),
      after: (_displacedX(field, right) - _displacedX(field, left)).abs(),
    );
  }

  static ({double before, double after, double dxLeft, double dxRight})
      _gonionWidth(List<Offset?> px, DisplacementField field) {
    final left = V2RegionCatalog.gonionLeft < px.length
        ? px[V2RegionCatalog.gonionLeft]
        : null;
    final right = V2RegionCatalog.gonionRight < px.length
        ? px[V2RegionCatalog.gonionRight]
        : null;
    if (left == null || right == null) {
      return (before: 0, after: 0, dxLeft: 0, dxRight: 0);
    }
    final dxL = _sampleDx(field, left);
    final dxR = _sampleDx(field, right);
    return (
      before: (right.dx - left.dx).abs(),
      after: ((right.dx + dxR) - (left.dx + dxL)).abs(),
      dxLeft: dxL,
      dxRight: dxR,
    );
  }

  static double _sampleDx(DisplacementField field, Offset p) {
    final x = p.dx.round().clamp(0, field.width - 1);
    final y = p.dy.round().clamp(0, field.height - 1);
    return field.dx[field.indexOf(x, y)];
  }

  static double _displacedX(DisplacementField field, Offset p) =>
      p.dx + _sampleDx(field, p);
}
