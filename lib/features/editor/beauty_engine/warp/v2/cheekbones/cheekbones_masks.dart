import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Crista no oval: polilinha com peso monótono. Não é MLS.
class CheekbonesMalarPad {
  const CheekbonesMalarPad({
    required this.center,
    required this.rx,
    required this.ry,
    required this.innerFrac,
    required this.leftSide,
    required this.handles,
    required this.sigma,
    required this.sigmaAlong,
    required this.sigmaAcross,
    required this.axisX,
    required this.axisY,
  });

  final Offset center;
  final double rx;
  final double ry;
  final double innerFrac;
  final bool leftSide;
  final List<({Offset p, double weight})> handles;
  final double sigma;
  final double sigmaAlong;
  final double sigmaAcross;
  final double axisX;
  final double axisY;

  /// Envelope: distância à polilinha do oval (sem vales de max(gaussianas)).
  double weight(double x, double y) {
    if (sigmaAcross < 1e-6 || handles.isEmpty) {
      return 0;
    }
    if (handles.length == 1) {
      final ddx = x - handles.first.p.dx;
      final ddy = y - handles.first.p.dy;
      final g = handles.first.weight *
          math.exp(-(ddx * ddx + ddy * ddy) / (2 * sigmaAcross * sigmaAcross));
      return g > 1.0 ? 1.0 : g;
    }
    var bestD2 = double.infinity;
    var bestW = 0.0;
    for (var i = 0; i < handles.length - 1; i++) {
      final a = handles[i];
      final b = handles[i + 1];
      final abx = b.p.dx - a.p.dx;
      final aby = b.p.dy - a.p.dy;
      final len2 = abx * abx + aby * aby;
      var t = 0.0;
      if (len2 > 1e-12) {
        t = ((x - a.p.dx) * abx + (y - a.p.dy) * aby) / len2;
        t = t.clamp(0.0, 1.0);
      }
      final px = a.p.dx + abx * t;
      final py = a.p.dy + aby * t;
      final dx = x - px;
      final dy = y - py;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        bestW = a.weight + (b.weight - a.weight) * t;
      }
    }
    final g = bestW *
        math.exp(-bestD2 / (2 * sigmaAcross * sigmaAcross));
    return g > 1.0 ? 1.0 : g;
  }

  /// Caixa fora da qual [weight] não pode passar [threshold].
  ///
  /// O peso é o do ponto da crista mais próximo, amortecido por
  /// `exp(−d² / 2σ²)`. Como esse peso nunca passa o maior dos handles, o valor
  /// é limitado por `maxW · exp(−dCaixa² / 2σ²)`, e além do raio onde esse
  /// limite cai abaixo do limiar não há nada a marcar. Avaliar o envelope na
  /// imagem inteira para o descartar depois custava mais de 100 ms.
  ({double left, double top, double right, double bottom})? supportBox(
    double threshold,
  ) {
    if (handles.isEmpty || sigmaAcross < 1e-6 || threshold <= 0) {
      return null;
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    var maxWeight = 0.0;
    for (final h in handles) {
      if (h.p.dx < left) left = h.p.dx;
      if (h.p.dx > right) right = h.p.dx;
      if (h.p.dy < top) top = h.p.dy;
      if (h.p.dy > bottom) bottom = h.p.dy;
      if (h.weight > maxWeight) maxWeight = h.weight;
    }
    if (maxWeight <= threshold) {
      return null;
    }
    final radius = sigmaAcross * math.sqrt(2 * math.log(maxWeight / threshold));
    return (
      left: left - radius,
      top: top - radius,
      right: right + radius,
      bottom: bottom + radius,
    );
  }

  Map<String, Object> toJson() => {
        'hypothesis': 'oval_ridge',
        'center': [center.dx, center.dy],
        'rx': rx,
        'ry': ry,
        'innerFrac': innerFrac,
        'leftSide': leftSide,
        'sigma': sigma,
        'sigmaAlong': sigmaAlong,
        'sigmaAcross': sigmaAcross,
        'handleCount': handles.length,
      };

  /// Crista no oval 234→93→132→58 (e espelho). Sem max(gaussianas) — isso fazia S.
  /// 323/454 estão no oval: não são cadeado da silhueta.
  static CheekbonesMalarPad? fromHandles({
    required Offset? orbitLower,
    required Offset? ovalUpper,
    required Offset? ovalMid,
    required Offset? jawNotch,
    required Offset? gonion,
    required Offset? lateral,
    required bool leftSide,
    required double faceWidth,
  }) {
    final sigmaAlong = math.max(8.0, 0.16 * faceWidth);
    final sigmaAcross = math.max(6.0, 0.09 * faceWidth);
    final ridge = <({Offset p, double weight})>[];
    final eyeGuard = 0.10 * faceWidth;

    void add(Offset? p, double weight) {
      if (p == null) {
        return;
      }
      if (orbitLower != null && (p - orbitLower).distance < eyeGuard) {
        return;
      }
      ridge.add((p: p, weight: weight));
    }

    add(ovalUpper, 0.80);
    if (ovalUpper != null && ovalMid != null) {
      add(
        Offset(
          ovalUpper.dx * 0.5 + ovalMid.dx * 0.5,
          ovalUpper.dy * 0.5 + ovalMid.dy * 0.5,
        ),
        0.75,
      );
    }
    add(ovalMid, 0.70);
    if (ovalMid != null && jawNotch != null) {
      add(
        Offset(
          ovalMid.dx * 0.5 + jawNotch.dx * 0.5,
          ovalMid.dy * 0.5 + jawNotch.dy * 0.5,
        ),
        0.59,
      );
    }
    add(jawNotch, 0.48);
    if (jawNotch != null && gonion != null) {
      add(
        Offset(
          jawNotch.dx * 0.5 + gonion.dx * 0.5,
          jawNotch.dy * 0.5 + gonion.dy * 0.5,
        ),
        0.35,
      );
    }
    add(gonion, 0.22);
    if (ridge.length < 2) {
      ridge.clear();
      add(lateral, 0.80);
      add(jawNotch, 0.48);
      add(gonion, 0.22);
    }
    if (ridge.length < 2) {
      return null;
    }
    var cx = 0.0;
    var cy = 0.0;
    for (final h in ridge) {
      cx += h.p.dx;
      cy += h.p.dy;
    }
    final n = ridge.length.toDouble();
    final alongFrom = ridge.first.p;
    final alongTo = ridge.last.p;
    final adx = alongTo.dx - alongFrom.dx;
    final ady = alongTo.dy - alongFrom.dy;
    final alen = math.sqrt(adx * adx + ady * ady);
    final axisX = alen > 1e-6 ? adx / alen : 0.0;
    final axisY = alen > 1e-6 ? ady / alen : 1.0;
    final support = 2.2 * sigmaAlong;
    return CheekbonesMalarPad(
      center: Offset(cx / n, cy / n),
      rx: support,
      ry: support,
      innerFrac: 0.0,
      leftSide: leftSide,
      handles: ridge,
      sigma: sigmaAlong,
      sigmaAlong: sigmaAlong,
      sigmaAcross: sigmaAcross,
      axisX: axisX,
      axisY: axisY,
    );
  }
}

/// Máscaras do Cheekbones. Não altera [RegionMasks] (contrato Jaw).
class CheekbonesMasks {
  CheekbonesMasks({
    required this.width,
    required this.height,
    required this.cheek,
    required this.cheekActive,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.jawDomain,
    required this.chinDomain,
    required this.protected,
    required this.softProtected,
    required this.oval,
  });

  final int width;
  final int height;
  final Uint8List cheek;
  final Uint8List cheekActive;
  final Uint8List eyes;
  final Uint8List brows;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List faceCenter;
  final Uint8List ears;
  final Uint8List jawDomain;
  final Uint8List chinDomain;
  final Uint8List protected;
  /// Rampa de bordo: nariz/boca/chin. Olhos e sobrancelhas ficam só em hard-zero.
  /// Orelha é hard-zero no apply, sem rampa (o disco 454 comia o malar direito).
  /// Gônio não entra: a cauda malar precisa de peso residual no ângulo.
  final Uint8List softProtected;
  final Uint8List oval;

  int get pixelCount => width * height;

  /// Envelope malar a partir do qual o pixel entra na região da bochecha.
  static const _cheekThreshold = 0.04;

  int count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }

  static CheekbonesMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required Set<int> jawDomainLandmarks,
    required Set<int> chinDomainLandmarks,
    required CheekbonesMalarPad? leftPad,
    required CheekbonesMalarPad? rightPad,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final geom = _faceGeom(px);
    final faceWidth = geom.faceWidth;
    final midlineX = geom.midlineX;

    final oval = RegionMaskRaster.zeros(width, height);
    final cheek = RegionMaskRaster.zeros(width, height);
    final eyes = RegionMaskRaster.zeros(width, height);
    final brows = RegionMaskRaster.zeros(width, height);
    final nose = RegionMaskRaster.zeros(width, height);
    final mouth = RegionMaskRaster.zeros(width, height);
    final ears = RegionMaskRaster.zeros(width, height);
    final jawDomain = RegionMaskRaster.zeros(width, height);
    final chinDomain = RegionMaskRaster.zeros(width, height);

    final ovalRing = _points(px, V2RegionCatalog.faceOval);
    if (ovalRing.length >= 3) {
      RegionMaskRaster.fillPolygon(oval, width, height, ovalRing);
    }

    // `max(esquerdo, direito) > limiar` é o mesmo que marcar o que cada um
    // passa, e cada um só o pode passar dentro da sua caixa de suporte.
    for (final pad in [leftPad, rightPad]) {
      final box = pad?.supportBox(_cheekThreshold);
      if (pad == null || box == null) {
        continue;
      }
      final x0 = box.left.floor().clamp(0, width - 1);
      final y0 = box.top.floor().clamp(0, height - 1);
      final x1 = box.right.ceil().clamp(0, width - 1);
      final y1 = box.bottom.ceil().clamp(0, height - 1);
      for (var y = y0; y <= y1; y++) {
        final row = y * width;
        for (var x = x0; x <= x1; x++) {
          if (cheek[row + x] != 0) {
            continue;
          }
          if (pad.weight(x + 0.5, y + 0.5) > _cheekThreshold) {
            cheek[row + x] = 255;
          }
        }
      }
    }

    RegionMaskRaster.fillConvexHull(
      eyes,
      width,
      height,
      _points(px, V2RegionCatalog.eyes),
    );
    RegionMaskRaster.dilate(
      eyes,
      width,
      height,
      (0.03 * faceWidth).round().clamp(3, 18),
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

    final earRadius = 0.022 * faceWidth;
    final pinnaOut = 0.05 * faceWidth;
    for (final id in V2RegionCatalog.ears) {
      final p = id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      final away = p.dx >= midlineX ? 1.0 : -1.0;
      final pinna = Offset(p.dx + away * pinnaOut, p.dy);
      RegionMaskRaster.fillDisk(ears, width, height, pinna, earRadius);
    }
    final jawChinRadius = 0.04 * faceWidth;
    for (final id in jawDomainLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(jawDomain, width, height, p, jawChinRadius);
      }
    }
    for (final id in chinDomainLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(chinDomain, width, height, p, jawChinRadius);
      }
    }

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
    RegionMaskRaster.orInto(protected, chinDomain);

    final softProtected = RegionMaskRaster.zeros(width, height);
    RegionMaskRaster.orInto(softProtected, nose);
    RegionMaskRaster.orInto(softProtected, mouth);
    RegionMaskRaster.orInto(softProtected, chinDomain);

    final cheekActive = RegionMaskRaster.zeros(width, height);
    for (var i = 0; i < cheekActive.length; i++) {
      if (cheek[i] != 0 && protected[i] == 0) {
        cheekActive[i] = 255;
      }
    }

    return CheekbonesMasks(
      width: width,
      height: height,
      cheek: cheek,
      cheekActive: cheekActive,
      eyes: eyes,
      brows: brows,
      nose: nose,
      mouth: mouth,
      faceCenter: faceCenter,
      ears: ears,
      jawDomain: jawDomain,
      chinDomain: chinDomain,
      protected: protected,
      softProtected: softProtected,
      oval: oval,
    );
  }

  static List<Offset?> landmarkPixels(FaceMeshResult face, Size imageSize) {
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

  static ({double faceWidth, double midlineX}) _faceGeom(List<Offset?> px) {
    final oval = _points(px, V2RegionCatalog.faceOval);
    if (oval.isEmpty) {
      return (faceWidth: 1.0, midlineX: 0);
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return (
      faceWidth: math.max(maxX - minX, 1.0),
      midlineX: (minX + maxX) / 2,
    );
  }
}
