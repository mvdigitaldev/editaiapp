import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_landmark.dart';
import '../../../models/face_mesh_result.dart';
import '../region_catalog.dart';
import '../region_masks.dart';

/// Máscaras do Head. Não altera [RegionMasks] (contrato Jaw).
/// Olhos e boca não são hard-zero: andam com a cabeça.
class HeadMasks {
  HeadMasks({
    required this.width,
    required this.height,
    required this.head,
    required this.headActive,
    required this.oval,
  });

  final int width;
  final int height;
  final Uint8List head;
  final Uint8List headActive;
  final Uint8List oval;

  int get pixelCount => width * height;

  int count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }

  static HeadMasks build({
    required FaceMeshResult face,
    required Size imageSize,
    required Offset center,
    required double scaleMax,
    required double hullPadFaceWidth,
    required double crownPadFaceWidth,
    required double crownExtendFaceWidth,
    required double crownMarginPx,
    required double hairWingFaceWidth,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    final px = landmarkPixels(face, imageSize);
    final faceWidth = faceWidthOf(px);

    final oval = RegionMaskRaster.zeros(width, height);
    final ovalRing = _points(px, V2RegionCatalog.faceOval);
    if (ovalRing.length >= 3) {
      RegionMaskRaster.fillPolygon(oval, width, height, ovalRing);
    }

    final base = <Offset>[
      ...ovalRing,
      ..._crownPoints(
        px,
        faceWidth,
        crownPadFaceWidth: crownPadFaceWidth,
        crownExtendFaceWidth: crownExtendFaceWidth,
        crownMarginPx: crownMarginPx,
      ),
      ..._points(px, V2RegionCatalog.ears),
      ..._hairWingPoints(
        px,
        center,
        hairWingFaceWidth * faceWidth,
        width: width,
        height: height,
        margin: math.max(2.0, crownMarginPx),
      ),
    ];
    final support = <Offset>[...base];
    final margin = math.max(2.0, crownMarginPx);
    for (final p in base) {
      final grown = Offset(
        center.dx + scaleMax * (p.dx - center.dx),
        center.dy + scaleMax * (p.dy - center.dy),
      );
      support.add(
        Offset(
          grown.dx.clamp(margin, width - 1 - margin),
          grown.dy.clamp(margin, height - 1 - margin),
        ),
      );
    }

    final head = RegionMaskRaster.zeros(width, height);
    if (support.length >= 3) {
      RegionMaskRaster.fillConvexHull(head, width, height, support);
    }
    final pad = math.max(6, (hullPadFaceWidth * faceWidth).round());
    RegionMaskRaster.dilate(head, width, height, pad);

    return HeadMasks(
      width: width,
      height: height,
      head: head,
      headActive: head,
      oval: oval,
    );
  }

  static List<Offset?> landmarkPixels(FaceMeshResult face, Size imageSize) {
    final out =
        List<Offset?>.filled(FaceMeshResult.expectedLandmarkCount, null);
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

  static double faceWidthOf(List<Offset?> px) {
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

  static Offset? ovalCenter(List<Offset?> px) {
    final oval = _points(px, V2RegionCatalog.faceOval);
    if (oval.isEmpty) {
      return null;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    var minY = oval.first.dy;
    var maxY = oval.first.dy;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Offset((minX + maxX) * 0.5, (minY + maxY) * 0.5);
  }

  /// Têmpora → orelha → gónio. O mesh não tem a silhueta do cabelo.
  static const hairWingIds = [
    21,
    162,
    127,
    234,
    93,
    132,
    58,
    172,
    251,
    389,
    356,
    454,
    323,
    361,
    288,
    397,
  ];

  static List<Offset> _hairWingPoints(
    List<Offset?> px,
    Offset center,
    double wing, {
    required int width,
    required int height,
    required double margin,
  }) {
    if (wing <= 1e-6) {
      return const [];
    }
    final out = <Offset>[];
    for (final id in hairWingIds) {
      final p = id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      final sign = p.dx < center.dx ? -1.0 : 1.0;
      out.add(
        Offset(
          (p.dx + sign * wing).clamp(margin, width - 1 - margin),
          p.dy.clamp(margin, height - 1 - margin),
        ),
      );
    }
    return out;
  }

  static List<Offset> _crownPoints(
    List<Offset?> px,
    double faceWidth, {
    required double crownPadFaceWidth,
    required double crownExtendFaceWidth,
    required double crownMarginPx,
  }) {
    final top = px.length > 10 ? px[10] : null;
    if (top == null) {
      return const [];
    }
    final pad = math.max(6.0, crownPadFaceWidth * faceWidth);
    final room = math.max(0.0, top.dy - pad - crownMarginPx);
    final lift = math.min(room, crownExtendFaceWidth * faceWidth);
    if (lift <= 1e-6) {
      return const [];
    }
    final out = <Offset>[];
    for (final id in const [103, 67, 109, 10, 338, 297, 332]) {
      final p = id < px.length ? px[id] : null;
      if (p != null) {
        out.add(Offset(p.dx, p.dy - lift));
      }
    }
    return out;
  }
}
