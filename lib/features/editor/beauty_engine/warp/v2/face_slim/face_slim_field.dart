import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import 'face_slim_masks.dart';
import 'face_slim_metrics.dart';

class FaceSlimFieldBuild {
  const FaceSlimFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final FaceSlimMasks masks;
  final FaceSlimFieldMetrics metrics;
}

/// Constrói o campo Face Slim. Sem RGBA, sem render, sem produto.
///
/// O oval só limita o domínio (`slimActive`). Direcção e envelope vêm da
/// spline mandibular (landmarks), não da normal do oval nem de um gate em Y.
abstract final class FaceSlimField {
  FaceSlimField._();

  /// Primários vigentes. 123/352 foram os candidatos iniciais; 352 cai no
  /// disco da orelha em p01, por isso o direito passou a 411 (bochecha R).
  /// São sondas de largura da bochecha, não picos de um kernel Lorentziano.
  static const primaryLeft = 123;
  static const primaryRight = 411;
  static const primaryHandles = {primaryLeft, primaryRight};

  /// Resto das bochechas — sem domínio Jaw/Chin.
  static const leftCheekLandmarks = {
    116,
    123,
    147,
    187,
    207,
    206,
    203,
    142,
    126,
    217,
  };
  static const rightCheekLandmarks = {
    345,
    352,
    411,
    425,
    427,
    436,
    426,
    423,
    266,
    371,
  };

  static const secondaryHandles = {
    116,
    147,
    187,
    207,
    206,
    203,
    142,
    126,
    217,
    345,
    352,
    425,
    427,
    436,
    426,
    423,
    266,
    371,
  };

  static Set<int> get leftHullLandmarks => leftCheekLandmarks;
  static Set<int> get rightHullLandmarks => rightCheekLandmarks;

  /// Domínio primário Jaw — hard-zero no Field Face Slim.
  static const jawDomainPrimary = {58, 288, 132, 361};

  /// Secundários Jaw — hard-zero no Field Face Slim.
  static const jawDomainSecondary = {172, 136, 365, 397};

  static Set<int> get jawDomainLandmarks => {
        ...jawDomainPrimary,
        ...jawDomainSecondary,
      };

  /// Domínio Chin — hard-zero no Field Face Slim.
  static const chinDomainLandmarks = {152, 148, 176, 149, 377, 400, 378};

  static const gonionLeft = 58;
  static const gonionRight = 288;
  static const chinTip = 152;

  static const amplitudeFaceWidth = 0.04;
  static const hullPadFaceWidth = 0.05;

  /// Zigoma → perto do mento. Define tangente/normal; não é kernel de handles.
  static const leftJawChain = [127, 234, 93, 132, 58, 172, 136, 150, 149];
  static const rightJawChain = [356, 454, 323, 361, 288, 397, 365, 379, 378];

  static FaceSlimFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('face_slim_field_invalid_size: ${width}x$height');
    }

    final px = FaceSlimMasks.landmarkPixels(face, imageSize);
    final masks = FaceSlimMasks.build(
      face: face,
      imageSize: imageSize,
      leftHullLandmarks: leftHullLandmarks,
      rightHullLandmarks: rightHullLandmarks,
      jawDomainLandmarks: jawDomainLandmarks,
      chinDomainLandmarks: chinDomainLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final faceWidth = _faceWidth(px);
    final intensity = t.clamp(0.0, 1.0);
    final amplitude = intensity * amplitudeFaceWidth * faceWidth;

    final field = DisplacementField.zeros(width: width, height: height);
    if (intensity > 0 && amplitude > 0 && masks.count(masks.slimActive) > 0) {
      _applyNarrowing(
        field: field,
        masks: masks,
        px: px,
        faceWidth: faceWidth,
        amplitude: amplitude,
      );
    }

    final metrics = FaceSlimFieldMetrics.compute(
      field: field,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
      slimAmplitude: amplitude,
      primaryLeft: primaryLeft,
      primaryRight: primaryRight,
      gonionLeft: gonionLeft,
      gonionRight: gonionRight,
      chinTip: chinTip,
    );
    return FaceSlimFieldBuild(field: field, masks: masks, metrics: metrics);
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

  static double _midlineX(List<Offset?> px, double faceWidth) {
    final oval = <Offset>[];
    for (final id in V2RegionCatalog.faceOval) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        oval.add(p);
      }
    }
    if (oval.isEmpty) {
      return faceWidth * 0.5;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return (minX + maxX) * 0.5;
  }

  /// Preenche `slimActive`. Direcção = normal interior da spline mandibular.
  /// Intensidade = fade da máscara × envelope C¹ no comprimento de arco.
  /// O oval só limita o domínio.
  static void _applyNarrowing({
    required DisplacementField field,
    required FaceSlimMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double amplitude,
  }) {
    final midX = _midlineX(px, faceWidth);
    final chains = [
      _sampleJawSpline(px, leftJawChain, midX, gonionLeft, faceWidth),
      _sampleJawSpline(px, rightJawChain, midX, gonionRight, faceWidth),
    ].where((c) => c.length >= 2).toList();
    if (chains.isEmpty) {
      return;
    }
    final edgeLayers = math.max(8, (0.045 * faceWidth).round());
    final edgeFade = _onionFade(
      masks.slimActive,
      field.width,
      field.height,
      edgeLayers,
    );

    for (var i = 0; i < field.pixelCount; i++) {
      if (masks.slimActive[i] == 0) {
        continue;
      }
      final x = (i % field.width) + 0.5;
      final y = (i ~/ field.width) + 0.5;
      final hit = _projectOnJaw(chains, x, y);
      if (hit == null) {
        continue;
      }
      final arcGate = _arcEnvelope(hit.s, hit.sGonion);
      final weight = edgeFade[i] * arcGate;
      if (weight <= 1e-6) {
        continue;
      }
      final mag = amplitude * weight;
      field.dx[i] = hit.nx * mag;
      field.dy[i] = hit.ny * mag;
    }
  }

  static List<_JawVertex> _sampleJawSpline(
    List<Offset?> px,
    List<int> chain,
    double midX,
    int gonionId,
    double faceWidth,
  ) {
    final pts = <Offset>[];
    Offset? gonionPt;
    for (final id in chain) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      pts.add(p);
      if (id == gonionId) {
        gonionPt = p;
      }
    }
    if (pts.length < 2) {
      return const [];
    }
    final dense = <Offset>[];
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      for (var k = 0; k < 16; k++) {
        dense.add(_catmull(p0, p1, p2, p3, k / 16));
      }
    }
    dense.add(pts.last);

    final seg = <double>[0];
    var total = 0.0;
    for (var i = 1; i < dense.length; i++) {
      total += (dense[i] - dense[i - 1]).distance;
      seg.add(total);
    }
    if (total < 1e-6) {
      return const [];
    }

    var sGonion = 0.72;
    if (gonionPt != null) {
      var bestI = 0;
      var bestD = 1e12;
      for (var i = 0; i < dense.length; i++) {
        final d = (dense[i] - gonionPt).distanceSquared;
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      sGonion = (seg[bestI] / total).clamp(0.15, 0.95);
      // O disco hard-zero do gônio tem raio ~0.055*faceWidth. O bump C¹
      // tem de chegar a 0 antes desse disco, senão o furo vira quina.
      final margin = (0.07 * faceWidth / total).clamp(0.08, 0.28);
      sGonion = (sGonion - margin).clamp(0.18, 0.9);
    }

    final out = <_JawVertex>[];
    for (var i = 0; i < dense.length; i++) {
      final prev = i == 0 ? dense[i] : dense[i - 1];
      final next = i + 1 == dense.length ? dense[i] : dense[i + 1];
      var tx = next.dx - prev.dx;
      var ty = next.dy - prev.dy;
      final tlen = math.sqrt(tx * tx + ty * ty);
      if (tlen < 1e-6) {
        continue;
      }
      tx /= tlen;
      ty /= tlen;
      var nx = ty;
      var ny = -tx;
      final toward = midX - dense[i].dx;
      if (nx * toward < 0) {
        nx = -nx;
        ny = -ny;
      }
      out.add(
        _JawVertex(
          p: dense[i],
          nx: nx,
          ny: ny,
          s: seg[i] / total,
          sGonion: sGonion,
        ),
      );
    }
    return out;
  }

  static Offset _catmull(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return Offset(
      0.5 *
          (2 * p1.dx +
              (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
      0.5 *
          (2 * p1.dy +
              (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
    );
  }

  static _JawHit? _projectOnJaw(
    List<List<_JawVertex>> chains,
    double x,
    double y,
  ) {
    _JawHit? best;
    var bestD = 1e12;
    for (final chain in chains) {
      for (var i = 0; i < chain.length - 1; i++) {
        final a = chain[i];
        final b = chain[i + 1];
        final abx = b.p.dx - a.p.dx;
        final aby = b.p.dy - a.p.dy;
        final ab2 = abx * abx + aby * aby;
        if (ab2 < 1e-12) {
          continue;
        }
        var t = ((x - a.p.dx) * abx + (y - a.p.dy) * aby) / ab2;
        t = t.clamp(0.0, 1.0);
        final qx = a.p.dx + abx * t;
        final qy = a.p.dy + aby * t;
        final dx = x - qx;
        final dy = y - qy;
        final d = dx * dx + dy * dy;
        if (d >= bestD) {
          continue;
        }
        bestD = d;
        var nx = a.nx + (b.nx - a.nx) * t;
        var ny = a.ny + (b.ny - a.ny) * t;
        final nlen = math.sqrt(nx * nx + ny * ny);
        if (nlen < 1e-6) {
          nx = a.nx;
          ny = a.ny;
        } else {
          nx /= nlen;
          ny /= nlen;
        }
        best = _JawHit(
          nx: nx,
          ny: ny,
          s: a.s + (b.s - a.s) * t,
          sGonion: a.sGonion,
        );
      }
    }
    return best;
  }

  /// C¹ no arco zigoma → gônio. Sem patamar: o meio da bochecha puxa mais
  /// do que as extremidades, para uma silhueta em C mesmo quando a spline é reta.
  static double _arcEnvelope(double s, double sGonion) {
    if (s <= 0 || s >= sGonion || sGonion <= 1e-6) {
      return 0;
    }
    final u = (s / sGonion).clamp(0.0, 1.0);
    final sine = math.sin(math.pi * u);
    return sine * sine;
  }

  /// Rampa de fronteira por camadas de erosão (não é o chamfer do Chin/Jaw).
  static List<double> _onionFade(
    Uint8List active,
    int width,
    int height,
    int layers,
  ) {
    final fade = List<double>.filled(active.length, 0);
    final remaining = Uint8List.fromList(active);
    var alive = 0;
    for (final v in remaining) {
      if (v != 0) {
        alive++;
      }
    }
    var layer = 0;
    while (alive > 0 && layer < layers) {
      layer++;
      final border = <int>[];
      for (var i = 0; i < remaining.length; i++) {
        if (remaining[i] == 0) {
          continue;
        }
        final x = i % width;
        final y = i ~/ width;
        final exposed = (x > 0 && remaining[i - 1] == 0) ||
            (x + 1 < width && remaining[i + 1] == 0) ||
            (y > 0 && remaining[i - width] == 0) ||
            (y + 1 < height && remaining[i + width] == 0);
        if (exposed) {
          border.add(i);
        }
      }
      if (border.isEmpty) {
        for (var i = 0; i < remaining.length; i++) {
          if (remaining[i] != 0) {
            fade[i] = 1;
            remaining[i] = 0;
            alive--;
          }
        }
        break;
      }
      final t = layer / layers;
      for (final i in border) {
        fade[i] = t;
        remaining[i] = 0;
        alive--;
      }
    }
    for (var i = 0; i < remaining.length; i++) {
      if (remaining[i] != 0) {
        fade[i] = 1;
      }
    }
    return fade;
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    if (x <= edge0) {
      return 0;
    }
    if (x >= edge1) {
      return 1;
    }
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

class _JawVertex {
  const _JawVertex({
    required this.p,
    required this.nx,
    required this.ny,
    required this.s,
    required this.sGonion,
  });

  final Offset p;
  final double nx;
  final double ny;
  final double s;
  final double sGonion;
}

class _JawHit {
  const _JawHit({
    required this.nx,
    required this.ny,
    required this.s,
    required this.sGonion,
  });

  final double nx;
  final double ny;
  final double s;
  final double sGonion;
}
