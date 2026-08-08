import 'dart:math' as math;
import 'dart:ui';

import '../../filters/face/face_filter_pipeline.dart';
import '../../filters/face/face_warp_utils.dart';
import 'anatomical_intent.dart';
import 'anatomical_zone.dart';
import 'face_model_specification.dart';
import 'pilot_warp_displacement.dart';

/// Converte sliders → [AnatomicalIntent] conforme Face Model Spec.
abstract final class AnatomicalIntentFactory {
  static List<AnatomicalIntent> build({
    required Map<String, double> parameters,
    required FaceAnatomyContext context,
  }) {
    final intents = <AnatomicalIntent>[];
    var priority = 0;

    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      final raw = (parameters[key] ?? 0).clamp(0.0, 1.0);
      if (raw <= 1e-6) {
        continue;
      }
      final spec = FaceModelSpecification.forKey(key);
      if (spec == null) {
        continue;
      }

      final magnitude = _easeOutCubic(raw);
      final mode = _modeFor(key);
      final zones = {...spec.primaryZones, ...spec.freeZones};
      final axis = _axisFor(key, context);

      intents.add(
        AnatomicalIntent(
          toolKey: key,
          primaryZone: spec.primaryZones.first,
          mode: mode,
          magnitude: magnitude,
          rawIntensity: raw,
          axis: axis,
          affectedZones: zones,
          priority: priority++,
        ),
      );

      if (context.linkEyes && _bilateralEyeKeys.contains(key)) {
        // Simetria E/D já coberta pelas zonas eyeLeft+eyeRight na spec.
      }
    }

    return intents;
  }

  static const _bilateralEyeKeys = {
    'eye_scale',
    'eye_distance',
    'eye_height',
    'eye_rotation',
    'double_eyelid',
  };

  static double _easeOutCubic(double t) {
    final x = t.clamp(0.0, 1.0);
    return 1 - math.pow(1 - x, 3).toDouble();
  }

  static DeformationMode _modeFor(String key) {
    if (PilotWarpDisplacement.pilotToolKeys.contains(key)) {
      return DeformationMode.pilot;
    }
    return DeformationMode.radialInward;
  }

  static Offset _axisFor(String key, FaceAnatomyContext context) {
    switch (key) {
      case 'eye_distance':
      case 'mouth_width':
        return const Offset(1, 0);
      case 'eye_height':
      case 'double_eyelid':
        return const Offset(0, -1);
      case 'smile':
        return Offset(0.35, -1).directionVector;
      case 'nose_length':
      case 'nose_height':
      case 'nose_bridge':
        final axis = FaceWarpUtils.noseAxisCenter(context.mesh);
        final center = FaceWarpUtils.faceCenter(
              context.face,
              context.imageSize,
            ) ??
            Offset(
              context.imageSize.width * 0.5,
              context.imageSize.height * 0.5,
            );
        final dir = axis - center;
        if (dir.distance < 1e-6) {
          return const Offset(0, 1);
        }
        return Offset(dir.dx, dir.dy) / dir.distance;
      default:
        return Offset.zero;
    }
  }
}

extension on Offset {
  Offset get directionVector {
    final len = distance;
    if (len < 1e-12) {
      return Offset.zero;
    }
    return this / len;
  }
}
