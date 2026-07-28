import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/image_source.dart';
import '../models/body_frame_assets.dart';
import '../models/body_joint.dart';
import '../models/body_part_segmentation.dart';
import '../models/occlusion_map.dart';
import '../providers/occlusion_provider.dart';
import '../providers/vision_capabilities.dart';
import 'occlusion_map.dart';

/// Infere oclusão conservadora a partir de pose/partes — sem ML de oclusão.
///
/// Segurança > recall: mãos/braços/cabelo sobre torso geram máscara explícita.
class ConservativeOcclusionProvider implements OcclusionProvider {
  const ConservativeOcclusionProvider({
    this.mapWidth = 64,
    this.mapHeight = 96,
    this.handRadiusFraction = 0.07,
    this.armRadiusFraction = 0.055,
    this.hairRadiusFraction = 0.09,
  });

  final int mapWidth;
  final int mapHeight;
  final double handRadiusFraction;
  final double armRadiusFraction;
  final double hairRadiusFraction;

  @override
  String get id => 'conservative_occlusion';

  @override
  VisionCapabilities get capabilities => const VisionCapabilities(
        occlusionMap: true,
      );

  /// Sem assets embutidos no [ImageSource]; use [inferFromAssets].
  @override
  Future<OcclusionMap?> detect(ImageSource source) async => null;

  /// Gera mapa a partir de landmarks e, se houver, segmentação por partes.
  OcclusionField? inferFromAssets(
    BodyFrameAssets assets, {
    Size? imageSize,
  }) {
    final size = imageSize ??
        Size(
          math.max(assets.boundingBox.width, 0.01),
          math.max(assets.boundingBox.height, 0.01),
        );
    // Operamos em espaço normalizado [0,1] com mapa discreto.
    final width = mapWidth;
    final height = mapHeight;
    // Mantém size disponível para callers futuros / telemetria.
    assert(size.width > 0 && size.height > 0);
    final weights = Uint8List(width * height);
    final kinds = Uint8List(width * height);
    final present = <OccluderKind>{};
    final minDim = math.min(width, height).toDouble();

    void stamp(Offset normalized, OccluderKind kind, double radiusFrac) {
      final cx = (normalized.dx.clamp(0.0, 1.0) * (width - 1));
      final cy = (normalized.dy.clamp(0.0, 1.0) * (height - 1));
      final radius = math.max(2.0, minDim * radiusFrac);
      final r2 = radius * radius;
      final x0 = math.max(0, (cx - radius).floor());
      final x1 = math.min(width - 1, (cx + radius).ceil());
      final y0 = math.max(0, (cy - radius).floor());
      final y1 = math.min(height - 1, (cy + radius).ceil());
      final code = OcclusionField.codeFor(kind);
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final dx = x - cx;
          final dy = y - cy;
          final d2 = dx * dx + dy * dy;
          if (d2 > r2) {
            continue;
          }
          final w = ((1.0 - math.sqrt(d2) / radius) * 255).round().clamp(0, 255);
          final idx = y * width + x;
          if (w > weights[idx]) {
            weights[idx] = w;
            kinds[idx] = code;
          }
        }
      }
      present.add(kind);
    }

    Offset? px(BodyJoint joint) {
      final landmark = assets.landmark(joint);
      if (landmark == null || landmark.confidence < 0.35) {
        return null;
      }
      return landmark.normalized;
    }

    final leftShoulder = px(BodyJoint.leftShoulder);
    final rightShoulder = px(BodyJoint.rightShoulder);
    final leftHip = px(BodyJoint.leftHip);
    final rightHip = px(BodyJoint.rightHip);
    final torso = _torsoRect(leftShoulder, rightShoulder, leftHip, rightHip);

    // Mãos/punhos sobre torso → oclusores de cintura/barriga.
    final leftWrist = px(BodyJoint.leftWrist);
    final rightWrist = px(BodyJoint.rightWrist);
    if (leftWrist != null && torso != null && _nearOrInside(torso, leftWrist)) {
      stamp(leftWrist, OccluderKind.leftHand, handRadiusFraction);
    }
    if (rightWrist != null &&
        torso != null &&
        _nearOrInside(torso, rightWrist)) {
      stamp(rightWrist, OccluderKind.rightHand, handRadiusFraction);
    }

    // Antebraços cruzando o tronco.
    final leftElbow = px(BodyJoint.leftElbow);
    final rightElbow = px(BodyJoint.rightElbow);
    if (leftElbow != null &&
        leftWrist != null &&
        torso != null &&
        (_nearOrInside(torso, leftElbow) || _segmentCrosses(torso, leftElbow, leftWrist))) {
      stamp(
        Offset(
          (leftElbow.dx + leftWrist.dx) * 0.5,
          (leftElbow.dy + leftWrist.dy) * 0.5,
        ),
        OccluderKind.leftArm,
        armRadiusFraction,
      );
    }
    if (rightElbow != null &&
        rightWrist != null &&
        torso != null &&
        (_nearOrInside(torso, rightElbow) ||
            _segmentCrosses(torso, rightElbow, rightWrist))) {
      stamp(
        Offset(
          (rightElbow.dx + rightWrist.dx) * 0.5,
          (rightElbow.dy + rightWrist.dy) * 0.5,
        ),
        OccluderKind.rightArm,
        armRadiusFraction,
      );
    }

    // Cabelo aproximado acima dos ombros (nariz/orelhas).
    final nose = px(BodyJoint.nose);
    final leftEar = px(BodyJoint.leftEar);
    final rightEar = px(BodyJoint.rightEar);
    if (leftShoulder != null && rightShoulder != null) {
      final shoulderY = (leftShoulder.dy + rightShoulder.dy) * 0.5;
      final head = nose ??
          (leftEar != null && rightEar != null
              ? Offset(
                  (leftEar.dx + rightEar.dx) * 0.5,
                  (leftEar.dy + rightEar.dy) * 0.5,
                )
              : null);
      if (head != null && head.dy < shoulderY) {
        stamp(
          Offset(head.dx, head.dy - 0.04),
          OccluderKind.hair,
          hairRadiusFraction,
        );
      }
    }

    // Segmentação por partes, se disponível.
    final parts = assets.partSegmentation;
    if (parts != null && !parts.isEmpty) {
      _stampFromParts(parts, weights, kinds, present, width, height);
    }

    if (present.isEmpty) {
      return null;
    }

    var maxW = 0;
    for (final w in weights) {
      if (w > maxW) maxW = w;
    }
    final confidence = (0.45 + 0.55 * (maxW / 255.0) * assets.confidence)
        .clamp(0.0, 1.0);

    return OcclusionField.fromMap(
      OcclusionMap(
        weights: weights,
        width: width,
        height: height,
        providerId: id,
        confidence: confidence,
      ),
      kindCodes: kinds,
      presentKinds: present,
      reason: 'conservative_pose_parts_occlusion',
    );
  }

  Rect? _torsoRect(
    Offset? leftShoulder,
    Offset? rightShoulder,
    Offset? leftHip,
    Offset? rightHip,
  ) {
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return null;
    }
    final left = math.min(leftShoulder.dx, leftHip.dx) - 0.04;
    final right = math.max(rightShoulder.dx, rightHip.dx) + 0.04;
    final top = math.min(leftShoulder.dy, rightShoulder.dy) - 0.02;
    final bottom = math.max(leftHip.dy, rightHip.dy) + 0.06;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool _nearOrInside(Rect torso, Offset p) {
    final inflated = torso.inflate(0.04);
    return inflated.contains(p);
  }

  bool _segmentCrosses(Rect torso, Offset a, Offset b) {
    // Amostra pontos do segmento.
    for (var i = 0; i <= 4; i++) {
      final t = i / 4.0;
      final p = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      if (torso.contains(p)) {
        return true;
      }
    }
    return false;
  }

  void _stampFromParts(
    BodyPartSegmentation parts,
    Uint8List weights,
    Uint8List kinds,
    Set<OccluderKind> present,
    int width,
    int height,
  ) {
    for (var y = 0; y < height; y++) {
      final sy = ((y + 0.5) / height * parts.height).floor().clamp(0, parts.height - 1);
      for (var x = 0; x < width; x++) {
        final sx = ((x + 0.5) / width * parts.width).floor().clamp(0, parts.width - 1);
        final code = parts.labels[sy * parts.width + sx];
        if (code < 0 || code >= BodyPartLabel.values.length) {
          continue;
        }
        final label = BodyPartLabel.values[code];
        final kind = switch (label) {
          BodyPartLabel.leftHand => OccluderKind.leftHand,
          BodyPartLabel.rightHand => OccluderKind.rightHand,
          BodyPartLabel.leftArm ||
          BodyPartLabel.leftForearm =>
            OccluderKind.leftArm,
          BodyPartLabel.rightArm ||
          BodyPartLabel.rightForearm =>
            OccluderKind.rightArm,
          BodyPartLabel.hair => OccluderKind.hair,
          _ => null,
        };
        if (kind == null) {
          continue;
        }
        final idx = y * width + x;
        const w = 220;
        if (w > weights[idx]) {
          weights[idx] = w;
          kinds[idx] = OcclusionField.codeFor(kind);
        }
        present.add(kind);
      }
    }
  }
}
