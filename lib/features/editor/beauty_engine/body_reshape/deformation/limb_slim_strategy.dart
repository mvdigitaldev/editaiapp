import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Estreita braços/pernas em direção ao eixo ósseo do segmento.
class LimbSlimStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const LimbSlimStrategy({
    this.armShiftFraction = 0.028,
    this.legShiftFraction = 0.032,
  });

  final double armShiftFraction;
  final double legShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.armSlim,
        BodyAdjustmentType.legSlim,
      };

  @override
  void apply({
    required RegionDeformationContext context,
    required Float32List deltas,
  }) {
    final intensity = context.intensity;
    if (intensity <= 0) {
      return;
    }

    final isArm = context.adjustment.type == BodyAdjustmentType.armSlim;
    final shiftFraction = isArm ? armShiftFraction : legShiftFraction;
    final shiftPx = context.imageSize.width * shiftFraction * intensity;
    final halfWidth = context.imageSize.width * (isArm ? 0.07 : 0.085);

    final segments = isArm ? _armSegments(context) : _legSegments(context);
    if (segments.isEmpty) {
      return;
    }

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      if (!_isLimbRegion(region, isArm: isArm)) {
        continue;
      }
      if (!context.regionMatches(region) &&
          !_compatibleLimbRegion(region, context.adjustment.regions)) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      var bestFalloff = 0.0;
      var bestInward = Offset.zero;

      for (final segment in segments) {
        if (!_segmentTouchesRegion(segment.region, region)) {
          continue;
        }
        final falloff = falloffAlongAxis(
          point: point,
          a: segment.proximal,
          b: segment.distal,
          halfWidth: halfWidth * segment.widthScale,
        );
        if (falloff <= bestFalloff) {
          continue;
        }
        final inward = inwardNormalTowardAxis(
          point: point,
          a: segment.proximal,
          b: segment.distal,
        );
        if (inward == Offset.zero) {
          continue;
        }
        bestFalloff = falloff;
        bestInward = inward;
      }

      if (bestFalloff <= 0 || bestInward == Offset.zero) {
        continue;
      }

      final w = bestFalloff * softVertexWeight(mesh.weights[i]);
      accumulateDelta(
        deltas,
        i,
        bestInward.dx * shiftPx,
        bestInward.dy * shiftPx,
        w,
      );
    }
  }

  List<_LimbSegment> _armSegments(RegionDeformationContext context) {
    final segments = <_LimbSegment>[];
    void add(
      BodyRegion region,
      BodyJoint proximal,
      BodyJoint distal, {
      double widthScale = 1,
    }) {
      final a = context.landmarkPx(proximal);
      final b = context.landmarkPx(distal);
      if (a == null || b == null) {
        return;
      }
      segments.add(
        _LimbSegment(
          region: region,
          proximal: a,
          distal: b,
          widthScale: widthScale,
        ),
      );
    }

    add(BodyRegion.leftArm, BodyJoint.leftShoulder, BodyJoint.leftElbow);
    add(
      BodyRegion.leftForearm,
      BodyJoint.leftElbow,
      BodyJoint.leftWrist,
      widthScale: 0.85,
    );
    add(BodyRegion.rightArm, BodyJoint.rightShoulder, BodyJoint.rightElbow);
    add(
      BodyRegion.rightForearm,
      BodyJoint.rightElbow,
      BodyJoint.rightWrist,
      widthScale: 0.85,
    );
    return segments;
  }

  List<_LimbSegment> _legSegments(RegionDeformationContext context) {
    final segments = <_LimbSegment>[];
    void add(
      BodyRegion region,
      BodyJoint proximal,
      BodyJoint distal, {
      double widthScale = 1,
    }) {
      final a = context.landmarkPx(proximal);
      final b = context.landmarkPx(distal);
      if (a == null || b == null) {
        return;
      }
      segments.add(
        _LimbSegment(
          region: region,
          proximal: a,
          distal: b,
          widthScale: widthScale,
        ),
      );
    }

    add(BodyRegion.leftThigh, BodyJoint.leftHip, BodyJoint.leftKnee);
    add(
      BodyRegion.leftCalf,
      BodyJoint.leftKnee,
      BodyJoint.leftAnkle,
      widthScale: 0.75,
    );
    add(BodyRegion.rightThigh, BodyJoint.rightHip, BodyJoint.rightKnee);
    add(
      BodyRegion.rightCalf,
      BodyJoint.rightKnee,
      BodyJoint.rightAnkle,
      widthScale: 0.75,
    );
    return segments;
  }

  bool _isLimbRegion(BodyRegion region, {required bool isArm}) {
    if (isArm) {
      return region == BodyRegion.leftArm ||
          region == BodyRegion.rightArm ||
          region == BodyRegion.leftForearm ||
          region == BodyRegion.rightForearm;
    }
    return region == BodyRegion.leftThigh ||
        region == BodyRegion.rightThigh ||
        region == BodyRegion.leftCalf ||
        region == BodyRegion.rightCalf;
  }

  bool _compatibleLimbRegion(BodyRegion region, Set<BodyRegion> targets) {
    for (final target in targets) {
      if (_segmentTouchesRegion(target, region) ||
          _segmentTouchesRegion(region, target)) {
        return true;
      }
    }
    return false;
  }

  bool _segmentTouchesRegion(BodyRegion segment, BodyRegion vertex) {
    if (segment == vertex) {
      return true;
    }
    return switch (segment) {
      BodyRegion.leftArm =>
        vertex == BodyRegion.leftArm || vertex == BodyRegion.leftForearm,
      BodyRegion.leftForearm =>
        vertex == BodyRegion.leftArm || vertex == BodyRegion.leftForearm,
      BodyRegion.rightArm =>
        vertex == BodyRegion.rightArm || vertex == BodyRegion.rightForearm,
      BodyRegion.rightForearm =>
        vertex == BodyRegion.rightArm || vertex == BodyRegion.rightForearm,
      BodyRegion.leftThigh =>
        vertex == BodyRegion.leftThigh || vertex == BodyRegion.leftCalf,
      BodyRegion.leftCalf =>
        vertex == BodyRegion.leftThigh || vertex == BodyRegion.leftCalf,
      BodyRegion.rightThigh =>
        vertex == BodyRegion.rightThigh || vertex == BodyRegion.rightCalf,
      BodyRegion.rightCalf =>
        vertex == BodyRegion.rightThigh || vertex == BodyRegion.rightCalf,
      _ => false,
    };
  }
}

class _LimbSegment {
  final BodyRegion region;
  final Offset proximal;
  final Offset distal;
  final double widthScale;

  const _LimbSegment({
    required this.region,
    required this.proximal,
    required this.distal,
    this.widthScale = 1,
  });
}
