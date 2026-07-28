import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/body_joint.dart';
import '../models/body_region.dart';
import '../models/body_frame_assets.dart';

/// Segmento de eixo anatômico usado para distância regional.
class RegionAxisSegment {
  final BodyRegion region;
  final Offset proximal;
  final Offset distal;
  final double halfWidthPx;

  const RegionAxisSegment({
    required this.region,
    required this.proximal,
    required this.distal,
    required this.halfWidthPx,
  }) : assert(halfWidthPx > 0);

  Offset get direction {
    final d = distal - proximal;
    final len = d.distance;
    if (len < 1e-6) {
      return Offset.zero;
    }
    return Offset(d.dx / len, d.dy / len);
  }

  Offset get normal {
    final d = direction;
    return Offset(-d.dy, d.dx);
  }
}

/// Distância (px), parâmetro ao longo do eixo e sinal lateral por pixel.
class RegionDistanceField {
  final Float32List distancePx;
  final Float32List axisT;
  final Float32List sideSign;
  final Float32List falloff;
  final int width;
  final int height;
  final Size imageSize;
  final Set<BodyRegion> regions;
  final List<RegionAxisSegment> segments;

  const RegionDistanceField({
    required this.distancePx,
    required this.axisT,
    required this.sideSign,
    required this.falloff,
    required this.width,
    required this.height,
    required this.imageSize,
    required this.regions,
    required this.segments,
  }) : assert(width >= 0 && height >= 0);

  bool get isEmpty => distancePx.isEmpty || width <= 0 || height <= 0;

  double sampleFalloff(double nx, double ny) =>
      _sample(falloff, nx, ny);

  double sampleDistancePx(double nx, double ny) =>
      _sample(distancePx, nx, ny);

  double sampleAxisT(double nx, double ny) => _sample(axisT, nx, ny);

  double sampleSideSign(double nx, double ny) => _sample(sideSign, nx, ny);

  double _sample(Float32List values, double nx, double ny) {
    if (isEmpty || values.length != width * height) {
      return 0;
    }
    final fx = (nx.clamp(0.0, 1.0) * (width - 1));
    final fy = (ny.clamp(0.0, 1.0) * (height - 1));
    final x0 = fx.floor().clamp(0, width - 1);
    final y0 = fy.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final tx = fx - x0;
    final ty = fy - y0;

    final v00 = values[y0 * width + x0];
    final v10 = values[y0 * width + x1];
    final v01 = values[y1 * width + x0];
    final v11 = values[y1 * width + x1];
    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }
}

/// Constrói [RegionDistanceField] a partir de landmarks / eixos semânticos.
class RegionDistanceFieldBuilder {
  const RegionDistanceFieldBuilder();

  RegionDistanceField build({
    required Size imageSize,
    required Set<BodyRegion> regions,
    required int width,
    required int height,
    BodyFrameAssets? assets,
    Map<BodyJoint, Offset>? landmarkPx,
    double halfWidthScale = 1,
  }) {
    if (width <= 0 || height <= 0 || regions.isEmpty) {
      return RegionDistanceField(
        distancePx: Float32List(0),
        axisT: Float32List(0),
        sideSign: Float32List(0),
        falloff: Float32List(0),
        width: 0,
        height: 0,
        imageSize: imageSize,
        regions: regions,
        segments: const [],
      );
    }

    final points = landmarkPx ?? _landmarksFromAssets(assets, imageSize);
    final segments = _segmentsForRegions(
      regions: regions,
      points: points,
      imageSize: imageSize,
      halfWidthScale: halfWidthScale,
    );

    final count = width * height;
    final distancePx = Float32List(count);
    final axisT = Float32List(count);
    final sideSign = Float32List(count);
    final falloff = Float32List(count);

    if (segments.isEmpty) {
      // Sem eixos: falloff uniforme no bounding box da imagem (conservador).
      for (var i = 0; i < count; i++) {
        distancePx[i] = 0;
        axisT[i] = 0.5;
        sideSign[i] = 0;
        falloff[i] = 0.35;
      }
      return RegionDistanceField(
        distancePx: distancePx,
        axisT: axisT,
        sideSign: sideSign,
        falloff: falloff,
        width: width,
        height: height,
        imageSize: imageSize,
        regions: regions,
        segments: segments,
      );
    }

    for (var y = 0; y < height; y++) {
      final ny = height == 1 ? 0.5 : y / (height - 1);
      final py = ny * imageSize.height;
      for (var x = 0; x < width; x++) {
        final nx = width == 1 ? 0.5 : x / (width - 1);
        final px = nx * imageSize.width;
        final point = Offset(px, py);
        final idx = y * width + x;

        var bestDist = double.infinity;
        var bestT = 0.5;
        var bestSide = 0.0;
        var bestFalloff = 0.0;

        for (final segment in segments) {
          final sample = _project(point, segment);
          if (sample.distance < bestDist) {
            bestDist = sample.distance;
            bestT = sample.t;
            bestSide = sample.side;
            bestFalloff = sample.falloff;
          } else if ((sample.distance - bestDist).abs() < 1e-3) {
            bestFalloff = math.max(bestFalloff, sample.falloff);
          }
        }

        distancePx[idx] = bestDist.isFinite ? bestDist : 0;
        axisT[idx] = bestT;
        sideSign[idx] = bestSide;
        falloff[idx] = bestFalloff;
      }
    }

    return RegionDistanceField(
      distancePx: distancePx,
      axisT: axisT,
      sideSign: sideSign,
      falloff: falloff,
      width: width,
      height: height,
      imageSize: imageSize,
      regions: regions,
      segments: segments,
    );
  }

  Map<BodyJoint, Offset> _landmarksFromAssets(
    BodyFrameAssets? assets,
    Size imageSize,
  ) {
    if (assets == null) {
      return const {};
    }
    return {
      for (final entry in assets.landmarks.entries)
        entry.key: Offset(
          entry.value.normalized.dx * imageSize.width,
          entry.value.normalized.dy * imageSize.height,
        ),
    };
  }

  List<RegionAxisSegment> _segmentsForRegions({
    required Set<BodyRegion> regions,
    required Map<BodyJoint, Offset> points,
    required Size imageSize,
    required double halfWidthScale,
  }) {
    final minDim = math.min(imageSize.width, imageSize.height);
    final segments = <RegionAxisSegment>[];

    Offset? p(BodyJoint joint) => points[joint];

    void add(
      BodyRegion region,
      BodyJoint a,
      BodyJoint b,
      double halfWidthFraction,
    ) {
      if (!regions.contains(region) &&
          !_regionAliasMatches(regions, region)) {
        return;
      }
      final pa = p(a);
      final pb = p(b);
      if (pa == null || pb == null) {
        return;
      }
      segments.add(
        RegionAxisSegment(
          region: region,
          proximal: pa,
          distal: pb,
          halfWidthPx: minDim * halfWidthFraction * halfWidthScale,
        ),
      );
    }

    // Torso / cintura: eixo medial ombro→quadril.
    if (_wantsTorsoAxis(regions)) {
      final ls = p(BodyJoint.leftShoulder);
      final rs = p(BodyJoint.rightShoulder);
      final lh = p(BodyJoint.leftHip);
      final rh = p(BodyJoint.rightHip);
      if (ls != null && rs != null && lh != null && rh != null) {
        final top = Offset((ls.dx + rs.dx) * 0.5, (ls.dy + rs.dy) * 0.5);
        final bottom = Offset((lh.dx + rh.dx) * 0.5, (lh.dy + rh.dy) * 0.5);
        final region = regions.contains(BodyRegion.waist)
            ? BodyRegion.waist
            : (regions.contains(BodyRegion.hip)
                ? BodyRegion.hip
                : BodyRegion.torso);
        segments.add(
          RegionAxisSegment(
            region: region,
            proximal: top,
            distal: bottom,
            halfWidthPx: minDim *
                (region == BodyRegion.waist ? 0.16 : 0.18) *
                halfWidthScale,
          ),
        );
      }
    }

    // Quadril: eixo horizontal entre coxofemorais.
    if (regions.contains(BodyRegion.hip) || regions.contains(BodyRegion.butt)) {
      final lh = p(BodyJoint.leftHip);
      final rh = p(BodyJoint.rightHip);
      if (lh != null && rh != null) {
        segments.add(
          RegionAxisSegment(
            region: BodyRegion.hip,
            proximal: lh,
            distal: rh,
            halfWidthPx: minDim * 0.10 * halfWidthScale,
          ),
        );
      }
    }

    add(BodyRegion.leftArm, BodyJoint.leftShoulder, BodyJoint.leftElbow, 0.07);
    add(
      BodyRegion.leftForearm,
      BodyJoint.leftElbow,
      BodyJoint.leftWrist,
      0.055,
    );
    add(
      BodyRegion.rightArm,
      BodyJoint.rightShoulder,
      BodyJoint.rightElbow,
      0.07,
    );
    add(
      BodyRegion.rightForearm,
      BodyJoint.rightElbow,
      BodyJoint.rightWrist,
      0.055,
    );
    add(BodyRegion.leftThigh, BodyJoint.leftHip, BodyJoint.leftKnee, 0.085);
    add(BodyRegion.leftCalf, BodyJoint.leftKnee, BodyJoint.leftAnkle, 0.07);
    add(BodyRegion.rightThigh, BodyJoint.rightHip, BodyJoint.rightKnee, 0.085);
    add(BodyRegion.rightCalf, BodyJoint.rightKnee, BodyJoint.rightAnkle, 0.07);
    add(BodyRegion.neck, BodyJoint.leftShoulder, BodyJoint.rightShoulder, 0.06);
    add(
      BodyRegion.shoulders,
      BodyJoint.leftShoulder,
      BodyJoint.rightShoulder,
      0.08,
    );

    return segments;
  }

  bool _wantsTorsoAxis(Set<BodyRegion> regions) {
    return regions.contains(BodyRegion.waist) ||
        regions.contains(BodyRegion.torso) ||
        regions.contains(BodyRegion.chest) ||
        regions.contains(BodyRegion.hip) ||
        regions.contains(BodyRegion.butt);
  }

  bool _regionAliasMatches(Set<BodyRegion> targets, BodyRegion candidate) {
    for (final target in targets) {
      if (target == candidate) {
        return true;
      }
      // Braço cobre antebraço e vice-versa para construção de eixos.
      if ((target == BodyRegion.leftArm || target == BodyRegion.leftForearm) &&
          (candidate == BodyRegion.leftArm ||
              candidate == BodyRegion.leftForearm)) {
        return true;
      }
      if ((target == BodyRegion.rightArm ||
              target == BodyRegion.rightForearm) &&
          (candidate == BodyRegion.rightArm ||
              candidate == BodyRegion.rightForearm)) {
        return true;
      }
      if ((target == BodyRegion.leftThigh || target == BodyRegion.leftCalf) &&
          (candidate == BodyRegion.leftThigh ||
              candidate == BodyRegion.leftCalf)) {
        return true;
      }
      if ((target == BodyRegion.rightThigh || target == BodyRegion.rightCalf) &&
          (candidate == BodyRegion.rightThigh ||
              candidate == BodyRegion.rightCalf)) {
        return true;
      }
    }
    return false;
  }

  ({double distance, double t, double side, double falloff}) _project(
    Offset point,
    RegionAxisSegment segment,
  ) {
    final ab = segment.distal - segment.proximal;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) {
      final dist = (point - segment.proximal).distance;
      final f = dist >= segment.halfWidthPx
          ? 0.0
          : _smoothstep(1.0 - dist / segment.halfWidthPx);
      return (distance: dist, t: 0.5, side: 0, falloff: f);
    }

    final t = (((point.dx - segment.proximal.dx) * ab.dx +
                (point.dy - segment.proximal.dy) * ab.dy) /
            len2)
        .clamp(0.0, 1.0);
    final closest = Offset(
      segment.proximal.dx + ab.dx * t,
      segment.proximal.dy + ab.dy * t,
    );
    final toPoint = point - closest;
    final dist = toPoint.distance;
    final n = segment.normal;
    final side = n == Offset.zero
        ? 0.0
        : (toPoint.dx * n.dx + toPoint.dy * n.dy).sign;
    final f = dist >= segment.halfWidthPx
        ? 0.0
        : _smoothstep(1.0 - dist / segment.halfWidthPx);
    return (distance: dist, t: t, side: side, falloff: f);
  }

  double _smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}
