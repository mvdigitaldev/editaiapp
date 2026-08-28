import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Máscaras do V Shape. Não altera [RegionMasks] (contrato Jaw).
class VShapeMasks {
  VShapeMasks({
    required this.width,
    required this.height,
    required this.chin,
    required this.chinActive,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.jawDomain,
    required this.chinTip,
    required this.innerPad,
    required this.protected,
  });

  final int width;
  final int height;
  final Uint8List chin;
  final Uint8List chinActive;
  final Uint8List eyes;
  final Uint8List brows;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List faceCenter;
  final Uint8List ears;
  final Uint8List jawDomain;
  final Uint8List chinTip;
  final Uint8List innerPad;
  final Uint8List protected;

  int get pixelCount => width * height;

  int count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }

  static VShapeMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required Set<int> hullLandmarks,
    required Set<int> jawDomainLandmarks,
    required Set<int> chinTipLandmarks,
    required Set<int> innerPadLandmarks,
    required double hullPadFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = _faceWidth(px);

    final chin = RegionMaskRaster.zeros(width, height);
    final eyes = RegionMaskRaster.zeros(width, height);
    final brows = RegionMaskRaster.zeros(width, height);
    final nose = RegionMaskRaster.zeros(width, height);
    final mouth = RegionMaskRaster.zeros(width, height);
    final ears = RegionMaskRaster.zeros(width, height);
    final jawDomain = RegionMaskRaster.zeros(width, height);
    final chinTip = RegionMaskRaster.zeros(width, height);
    final innerPad = RegionMaskRaster.zeros(width, height);

    RegionMaskRaster.fillConvexHull(chin, width, height, _points(px, hullLandmarks));
    final pad = math.max(6, (hullPadFaceWidth * faceWidth).round());
    RegionMaskRaster.dilate(chin, width, height, pad);

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

    final jawRadius = 0.06 * faceWidth;
    for (final id in jawDomainLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(jawDomain, width, height, p, jawRadius);
      }
    }

    final tipRadius = 0.018 * faceWidth;
    for (final id in chinTipLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(chinTip, width, height, p, tipRadius);
      }
    }

    final innerRadius = 0.022 * faceWidth;
    for (final id in innerPadLandmarks) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        RegionMaskRaster.fillDisk(innerPad, width, height, p, innerRadius);
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

    final chinActive = RegionMaskRaster.zeros(width, height);
    for (var i = 0; i < chinActive.length; i++) {
      if (chin[i] != 0 && protected[i] == 0) {
        chinActive[i] = 255;
      }
    }

    return VShapeMasks(
      width: width,
      height: height,
      chin: chin,
      chinActive: chinActive,
      eyes: eyes,
      brows: brows,
      nose: nose,
      mouth: mouth,
      faceCenter: faceCenter,
      ears: ears,
      jawDomain: jawDomain,
      chinTip: chinTip,
      innerPad: innerPad,
      protected: protected,
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
