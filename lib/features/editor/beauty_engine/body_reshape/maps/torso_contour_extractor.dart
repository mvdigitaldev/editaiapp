import 'dart:math' as math;
import 'dart:ui';

import '../models/body_frame_assets.dart';
import '../models/body_joint.dart';
import '../models/person_matte.dart';
import 'torso_contour_profile.dart';

/// Extrai bordas densas da silhueta do torso a partir do [PersonMatte].
class TorsoContourExtractor {
  const TorsoContourExtractor({
    this.bandCount = 28,
    this.alphaThreshold = 0.45,
    this.maxWidthJumpFraction = 0.28,
    this.minWidthFraction = 0.04,
  });

  final int bandCount;
  final double alphaThreshold;
  final double maxWidthJumpFraction;
  final double minWidthFraction;

  TorsoContourProfile? extract({
    required BodyFrameAssets assets,
    required Size imageSize,
  }) {
    final matte = assets.personMatte;
    final leftShoulder = assets.landmark(BodyJoint.leftShoulder);
    final rightShoulder = assets.landmark(BodyJoint.rightShoulder);
    final leftHip = assets.landmark(BodyJoint.leftHip);
    final rightHip = assets.landmark(BodyJoint.rightHip);
    if (matte == null ||
        matte.isEmpty ||
        leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return null;
    }

    final topMid = Offset(
      ((leftShoulder.normalized.dx + rightShoulder.normalized.dx) * 0.5) *
          imageSize.width,
      ((leftShoulder.normalized.dy + rightShoulder.normalized.dy) * 0.5) *
          imageSize.height,
    );
    final bottomMid = Offset(
      ((leftHip.normalized.dx + rightHip.normalized.dx) * 0.5) *
          imageSize.width,
      ((leftHip.normalized.dy + rightHip.normalized.dy) * 0.5) *
          imageSize.height,
    );
    final span = bottomMid.dy - topMid.dy;
    if (span < 8) {
      return null;
    }

    final raw = <TorsoContourBand>[];
    for (var i = 0; i < bandCount; i++) {
      final t = bandCount == 1 ? 0.5 : i / (bandCount - 1);
      final y = topMid.dy + span * t;
      final band = _scanBand(
        matte: matte,
        imageSize: imageSize,
        y: y,
        t: t,
        midlineX: topMid.dx + (bottomMid.dx - topMid.dx) * t,
      );
      if (band != null) {
        raw.add(band);
      }
    }
    if (raw.length < 4) {
      return null;
    }

    final smoothed = _smoothBands(raw, imageSize.width);
    final withContamination = _markArmContamination(
      bands: smoothed,
      assets: assets,
      imageSize: imageSize,
    );

    var confidenceSum = 0.0;
    var usable = 0;
    var contaminated = false;
    for (final band in withContamination) {
      if (band.rejected) {
        contaminated = true;
        continue;
      }
      confidenceSum += band.confidence;
      usable++;
    }
    if (usable < 3) {
      return null;
    }

    return TorsoContourProfile(
      bands: withContamination,
      topMid: topMid,
      bottomMid: bottomMid,
      imageSize: imageSize,
      meanConfidence: confidenceSum / usable,
      hasArmContamination: contaminated,
    );
  }

  TorsoContourBand? _scanBand({
    required PersonMatte matte,
    required Size imageSize,
    required double y,
    required double t,
    required double midlineX,
  }) {
    final ny = (y / imageSize.height).clamp(0.0, 1.0);
    final minWidth = imageSize.width * minWidthFraction;

    var leftX = -1.0;
    for (var x = 0; x < matte.width; x++) {
      final nx = x / math.max(matte.width - 1, 1);
      if (matte.sampleNormalized(nx, ny) >= alphaThreshold) {
        leftX = nx * imageSize.width;
        break;
      }
    }
    if (leftX < 0) {
      return null;
    }

    var rightX = -1.0;
    for (var x = matte.width - 1; x >= 0; x--) {
      final nx = x / math.max(matte.width - 1, 1);
      if (matte.sampleNormalized(nx, ny) >= alphaThreshold) {
        rightX = nx * imageSize.width;
        break;
      }
    }
    if (rightX < 0 || rightX - leftX < minWidth) {
      return null;
    }

    // Preferir o componente conectado que contém a midline do torso.
    final clipped = _clipToMidlineComponent(
      matte: matte,
      imageSize: imageSize,
      y: y,
      ny: ny,
      leftX: leftX,
      rightX: rightX,
      midlineX: midlineX,
    );

    final alphaLeft = matte.sampleNormalized(
      (clipped.$1 / imageSize.width).clamp(0.0, 1.0),
      ny,
    );
    final alphaRight = matte.sampleNormalized(
      (clipped.$2 / imageSize.width).clamp(0.0, 1.0),
      ny,
    );

    return TorsoContourBand(
      t: t,
      y: y,
      leftX: clipped.$1,
      rightX: clipped.$2,
      confidence: ((alphaLeft + alphaRight) * 0.5).clamp(0.0, 1.0),
    );
  }

  (double, double) _clipToMidlineComponent({
    required PersonMatte matte,
    required Size imageSize,
    required double y,
    required double ny,
    required double leftX,
    required double rightX,
    required double midlineX,
  }) {
    final midNx = (midlineX / imageSize.width).clamp(0.0, 1.0);
    if (matte.sampleNormalized(midNx, ny) < alphaThreshold) {
      return (leftX, rightX);
    }

    // Expandir a partir da midline até achar as bordas do componente central.
    var l = midlineX;
    var r = midlineX;
    final step = math.max(1.0, imageSize.width / math.max(matte.width, 1));
    while (l > leftX) {
      final next = l - step;
      final nx = (next / imageSize.width).clamp(0.0, 1.0);
      if (matte.sampleNormalized(nx, ny) < alphaThreshold) {
        break;
      }
      l = next;
    }
    while (r < rightX) {
      final next = r + step;
      final nx = (next / imageSize.width).clamp(0.0, 1.0);
      if (matte.sampleNormalized(nx, ny) < alphaThreshold) {
        break;
      }
      r = next;
    }
    if (r - l < imageSize.width * minWidthFraction) {
      return (leftX, rightX);
    }
    return (l, r);
  }

  List<TorsoContourBand> _smoothBands(
    List<TorsoContourBand> bands,
    double imageWidth,
  ) {
    if (bands.length < 3) {
      return bands;
    }

    final maxJump = imageWidth * maxWidthJumpFraction;
    final result = <TorsoContourBand>[];
    for (var i = 0; i < bands.length; i++) {
      final prev = i > 0 ? bands[i - 1] : null;
      final next = i + 1 < bands.length ? bands[i + 1] : null;
      final current = bands[i];

      var left = current.leftX;
      var right = current.rightX;
      var rejected = current.rejected;
      var confidence = current.confidence;

      if (prev != null && next != null) {
        left = (prev.leftX + current.leftX + next.leftX) / 3.0;
        right = (prev.rightX + current.rightX + next.rightX) / 3.0;
      }

      if (prev != null) {
        final widthJump = ((right - left) - prev.width).abs();
        if (widthJump > maxJump) {
          // Limita saltos abruptos (braço/objeto anexado).
          left = prev.leftX * 0.65 + left * 0.35;
          right = prev.rightX * 0.65 + right * 0.35;
          rejected = true;
          confidence *= 0.4;
        }
      }

      if (right - left < imageWidth * minWidthFraction) {
        rejected = true;
      }

      result.add(
        current.copyWith(
          leftX: left,
          rightX: right,
          rejected: rejected,
          confidence: confidence.clamp(0.0, 1.0),
        ),
      );
    }
    return result;
  }

  List<TorsoContourBand> _markArmContamination({
    required List<TorsoContourBand> bands,
    required BodyFrameAssets assets,
    required Size imageSize,
  }) {
    final armJoints = <Offset>[
      for (final joint in const [
        BodyJoint.leftElbow,
        BodyJoint.rightElbow,
        BodyJoint.leftWrist,
        BodyJoint.rightWrist,
      ])
        if (assets.landmark(joint) != null)
          Offset(
            assets.landmark(joint)!.normalized.dx * imageSize.width,
            assets.landmark(joint)!.normalized.dy * imageSize.height,
          ),
    ];
    if (armJoints.isEmpty) {
      return bands;
    }

    // Só marca contaminação quando o braço invade o miolo do torso
    // (ex.: braços cruzados sobre a barriga), não quando fica na borda lateral.
    return [
      for (final band in bands)
        () {
          final inset = band.halfWidth * 0.28;
          final innerLeft = band.leftX + inset;
          final innerRight = band.rightX - inset;
          if (innerRight <= innerLeft) {
            return band;
          }
          var hit = false;
          for (final joint in armJoints) {
            if ((joint.dy - band.y).abs() > band.width * 0.35) {
              continue;
            }
            if (joint.dx > innerLeft && joint.dx < innerRight) {
              hit = true;
              break;
            }
          }
          if (!hit) {
            return band;
          }
          return band.copyWith(
            rejected: true,
            confidence: band.confidence * 0.35,
          );
        }(),
    ];
  }
}
