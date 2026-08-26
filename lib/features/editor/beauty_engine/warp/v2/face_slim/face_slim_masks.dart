import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Máscaras do Face Slim. Não altera [RegionMasks] (contrato Jaw).
class FaceSlimMasks {
  FaceSlimMasks({
    required this.width,
    required this.height,
    required this.slim,
    required this.slimActive,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.jawDomain,
    required this.chinDomain,
    required this.protected,
    required this.oval,
  });

  final int width;
  final int height;
  final Uint8List slim;
  final Uint8List slimActive;
  final Uint8List eyes;
  final Uint8List brows;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List faceCenter;
  final Uint8List ears;
  final Uint8List jawDomain;
  final Uint8List chinDomain;
  final Uint8List protected;
  final Uint8List oval;

  int get pixelCount => width * height;

  int count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }

  /// Hull / handles vêm do módulo Face Slim (ajustáveis na Sprint A).
  static FaceSlimMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required Set<int> leftHullLandmarks,
    required Set<int> rightHullLandmarks,
    required Set<int> jawDomainLandmarks,
    required Set<int> chinDomainLandmarks,
    required double hullPadFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = _faceWidth(px);

    final oval = RegionMaskRaster.zeros(width, height);
    final slim = RegionMaskRaster.zeros(width, height);
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

    final bandWidth = math.max(8, (0.10 * faceWidth).round());
    final silhouette = _silhouetteBand(oval, width, height, bandWidth);
    _clipVertical(
      silhouette,
      width,
      height,
      _zoneTop(px, faceWidth),
      _zoneBottom(px, faceWidth),
    );
    _clipCenter(silhouette, width, height, px, 0.22 * faceWidth);
    RegionMaskRaster.orInto(slim, silhouette);
    final pad = math.max(3, (hullPadFaceWidth * 0.4 * faceWidth).round());
    RegionMaskRaster.dilate(slim, width, height, pad);
    if (slim.every((v) => v == 0)) {
      RegionMaskRaster.fillConvexHull(
        slim,
        width,
        height,
        _points(px, {...leftHullLandmarks, ...rightHullLandmarks}),
      );
    }

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

    final earRadius = 0.055 * faceWidth;
    for (final id in V2RegionCatalog.ears) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(ears, width, height, p, earRadius);
      }
    }

    final jawRadius = 0.055 * faceWidth;
    for (final id in jawDomainLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(jawDomain, width, height, p, jawRadius);
      }
    }

    final chinRadius = 0.055 * faceWidth;
    for (final id in chinDomainLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(chinDomain, width, height, p, chinRadius);
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
    RegionMaskRaster.orInto(protected, ears);
    RegionMaskRaster.orInto(protected, jawDomain);
    RegionMaskRaster.orInto(protected, chinDomain);

    final slimActive = RegionMaskRaster.zeros(width, height);
    for (var i = 0; i < slimActive.length; i++) {
      if (slim[i] != 0 && protected[i] == 0) {
        slimActive[i] = 255;
      }
    }

    return FaceSlimMasks(
      width: width,
      height: height,
      slim: slim,
      slimActive: slimActive,
      eyes: eyes,
      brows: brows,
      nose: nose,
      mouth: mouth,
      faceCenter: faceCenter,
      ears: ears,
      jawDomain: jawDomain,
      chinDomain: chinDomain,
      protected: protected,
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

  /// Faixa interior do oval: pixéis da cara a menos de [bandWidth] da
  /// silhueta. Liga as bochechas ao contorno, sem preencher o miolo.
  static Uint8List _silhouetteBand(
    Uint8List oval,
    int width,
    int height,
    int bandWidth,
  ) {
    final exterior = Uint8List(oval.length);
    for (var i = 0; i < oval.length; i++) {
      exterior[i] = oval[i] == 0 ? 255 : 0;
    }
    RegionMaskRaster.dilate(exterior, width, height, bandWidth);
    final band = RegionMaskRaster.zeros(width, height);
    for (var i = 0; i < oval.length; i++) {
      if (oval[i] != 0 && exterior[i] != 0) {
        band[i] = 255;
      }
    }
    return band;
  }

  static void _clipVertical(
    Uint8List mask,
    int width,
    int height,
    double yTop,
    double yBot,
  ) {
    for (var y = 0; y < height; y++) {
      final cy = y + 0.5;
      if (cy >= yTop && cy <= yBot) {
        continue;
      }
      final row = y * width;
      for (var x = 0; x < width; x++) {
        mask[row + x] = 0;
      }
    }
  }

  static void _clipCenter(
    Uint8List mask,
    int width,
    int height,
    List<Offset?> px,
    double halfGap,
  ) {
    final oval = _points(px, V2RegionCatalog.faceOval);
    if (oval.isEmpty) {
      return;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    final midX = (minX + maxX) * 0.5;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final x = (i % width) + 0.5;
      if ((x - midX).abs() < halfGap) {
        mask[i] = 0;
      }
    }
  }

  /// Abaixo dos olhos / arco zigomático.
  static double _zoneTop(List<Offset?> px, double faceWidth) {
    final eyes = _points(px, V2RegionCatalog.eyes);
    if (eyes.isEmpty) {
      return 0;
    }
    var maxY = eyes.first.dy;
    for (final p in eyes) {
      maxY = math.max(maxY, p.dy);
    }
    return maxY - 0.02 * faceWidth;
  }

  /// Termina junto do mento; o disco do Chin continua a proteger o 152.
  static double _zoneBottom(List<Offset?> px, double faceWidth) {
    final chin = 152 < px.length ? px[152] : null;
    if (chin == null) {
      return 1e9;
    }
    return chin.dy - 0.08 * faceWidth;
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
}
