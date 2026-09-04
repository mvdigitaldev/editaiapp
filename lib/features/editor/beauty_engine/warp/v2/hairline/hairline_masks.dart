import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Máscaras do Hairline. Não altera [RegionMasks] (contrato Jaw).
class HairlineMasks {
  HairlineMasks({
    required this.width,
    required this.height,
    required this.hairline,
    required this.hairlineActive,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.cheeks,
    required this.jawDomain,
    required this.temples,
    required this.protected,
    required this.oval,
  });

  final int width;
  final int height;
  final Uint8List hairline;
  final Uint8List hairlineActive;
  final Uint8List eyes;
  final Uint8List brows;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List faceCenter;
  final Uint8List ears;
  final Uint8List cheeks;
  final Uint8List jawDomain;
  final Uint8List temples;
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

  static HairlineMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required Set<int> hullLandmarks,
    required Set<int> cheekLandmarks,
    required Set<int> jawDomainLandmarks,
    required Set<int> templeLandmarks,
    required double hullPadFaceWidth,
    List<Offset> extraHullPoints = const [],
    List<Offset> regionRing = const [],
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = _faceWidth(px);

    final oval = RegionMaskRaster.zeros(width, height);
    final hairline = RegionMaskRaster.zeros(width, height);
    final eyes = RegionMaskRaster.zeros(width, height);
    final brows = RegionMaskRaster.zeros(width, height);
    final nose = RegionMaskRaster.zeros(width, height);
    final mouth = RegionMaskRaster.zeros(width, height);
    final ears = RegionMaskRaster.zeros(width, height);
    final cheeks = RegionMaskRaster.zeros(width, height);
    final jawDomain = RegionMaskRaster.zeros(width, height);
    final temples = RegionMaskRaster.zeros(width, height);

    final ovalRing = _points(px, V2RegionCatalog.faceOval);
    if (ovalRing.length >= 3) {
      RegionMaskRaster.fillPolygon(oval, width, height, ovalRing);
    }

    if (regionRing.length >= 3) {
      RegionMaskRaster.fillPolygon(hairline, width, height, regionRing);
    } else {
      RegionMaskRaster.fillConvexHull(
        hairline,
        width,
        height,
        [..._points(px, hullLandmarks), ...extraHullPoints],
      );
    }
    final pad = math.max(6, (hullPadFaceWidth * faceWidth).round());
    RegionMaskRaster.dilate(hairline, width, height, pad);

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

    final earRadius = 0.06 * faceWidth;
    for (final id in V2RegionCatalog.ears) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(ears, width, height, p, earRadius);
      }
    }

    final cheekRadius = 0.06 * faceWidth;
    for (final id in cheekLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(cheeks, width, height, p, cheekRadius);
      }
    }

    final jawRadius = 0.06 * faceWidth;
    for (final id in jawDomainLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(jawDomain, width, height, p, jawRadius);
      }
    }

    // Só métrica — não entra em protected (disco nas têmporas isola um pico).
    final templeRadius = 0.035 * faceWidth;
    for (final id in templeLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(temples, width, height, p, templeRadius);
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
    RegionMaskRaster.orInto(protected, cheeks);
    RegionMaskRaster.orInto(protected, jawDomain);

    final hairlineActive = RegionMaskRaster.zeros(width, height);
    for (var i = 0; i < hairlineActive.length; i++) {
      if (hairline[i] != 0 && protected[i] == 0) {
        hairlineActive[i] = 255;
      }
    }

    return HairlineMasks(
      width: width,
      height: height,
      hairline: hairline,
      hairlineActive: hairlineActive,
      eyes: eyes,
      brows: brows,
      nose: nose,
      mouth: mouth,
      faceCenter: faceCenter,
      ears: ears,
      cheeks: cheeks,
      jawDomain: jawDomain,
      temples: temples,
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
