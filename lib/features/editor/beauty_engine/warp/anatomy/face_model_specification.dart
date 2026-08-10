import '../../filters/face/face_filter_pipeline.dart';
import 'anatomical_zone.dart';

/// Especificação normativa de uma ferramenta warp facial (V3).
class FaceToolSpecification {
  const FaceToolSpecification({
    required this.parameterKey,
    required this.primaryZones,
    required this.freeZones,
    required this.rigidZones,
    required this.semiRigidZones,
    this.maxDisplacementFse,
    this.maxScale,
    this.minScale,
    this.maxRotationDegrees,
    this.invariantId,
  });

  final String parameterKey;
  final Set<AnatomicalZone> primaryZones;
  final Set<AnatomicalZone> freeZones;
  final Set<AnatomicalZone> rigidZones;
  final Set<AnatomicalZone> semiRigidZones;

  /// Deslocamento máximo em fração da face short edge (FSE).
  final double? maxDisplacementFse;

  /// Escala máxima (ferramentas de scale).
  final double? maxScale;

  /// Escala mínima.
  final double? minScale;

  /// Rotação máxima em graus.
  final double? maxRotationDegrees;

  /// Referência cruzada em `13-visual-quality-targets.md` (ex.: B1, B5).
  final String? invariantId;
}

/// Tabelas estáticas da Face Model Specification (Sprint 31).
abstract final class FaceModelSpecification {
  static const sharedRigid = {
    AnatomicalZone.oralCavity,
  };

  static const sharedEyeRigid = {
    AnatomicalZone.eyeLeft,
    AnatomicalZone.eyeRight,
  };

  static const sharedMouthRigid = {
    AnatomicalZone.oralCavity,
    AnatomicalZone.upperLip,
    AnatomicalZone.lowerLip,
    AnatomicalZone.mouthCorner,
  };

  static const _headSizeFreeZones = {
    AnatomicalZone.skullContour,
    AnatomicalZone.forehead,
    AnatomicalZone.templeLeft,
    AnatomicalZone.templeRight,
    AnatomicalZone.browLeft,
    AnatomicalZone.browRight,
    AnatomicalZone.eyeLeft,
    AnatomicalZone.eyeRight,
    AnatomicalZone.noseRoot,
    AnatomicalZone.noseDorsum,
    AnatomicalZone.noseTip,
    AnatomicalZone.noseAlae,
    AnatomicalZone.cheekLeft,
    AnatomicalZone.cheekRight,
    AnatomicalZone.jawLeft,
    AnatomicalZone.jawRight,
    AnatomicalZone.chin,
    AnatomicalZone.upperLip,
    AnatomicalZone.lowerLip,
    AnatomicalZone.mouthCorner,
    AnatomicalZone.philtrum,
  };

  static const toolSpecifications = {
    'face_slim': FaceToolSpecification(
      parameterKey: 'face_slim',
      primaryZones: {
        AnatomicalZone.skullContour,
        AnatomicalZone.cheekLeft,
        AnatomicalZone.cheekRight,
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
        AnatomicalZone.templeLeft,
        AnatomicalZone.templeRight,
      },
      freeZones: {
        AnatomicalZone.skullContour,
        AnatomicalZone.cheekLeft,
        AnatomicalZone.cheekRight,
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
        AnatomicalZone.templeLeft,
        AnatomicalZone.templeRight,
      },
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
        AnatomicalZone.browLeft,
        AnatomicalZone.browRight,
        AnatomicalZone.forehead,
        AnatomicalZone.philtrum,
        AnatomicalZone.chin,
      },
      semiRigidZones: {
        AnatomicalZone.skullContour,
      },
      maxDisplacementFse: 0.08,
      invariantId: 'B1',
    ),
    'narrow_face': FaceToolSpecification(
      parameterKey: 'narrow_face',
      primaryZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      freeZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
      },
      semiRigidZones: {
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
        AnatomicalZone.templeLeft,
        AnatomicalZone.templeRight,
      },
      maxDisplacementFse: 0.06,
    ),
    'v_face': FaceToolSpecification(
      parameterKey: 'v_face',
      primaryZones: {
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
        AnatomicalZone.chin,
      },
      freeZones: {
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
        AnatomicalZone.chin,
      },
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
      },
      semiRigidZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      maxDisplacementFse: 0.05,
    ),
    'jaw': FaceToolSpecification(
      parameterKey: 'jaw',
      primaryZones: {AnatomicalZone.jawLeft, AnatomicalZone.jawRight},
      freeZones: {AnatomicalZone.jawLeft, AnatomicalZone.jawRight},
      rigidZones: {
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
      },
      semiRigidZones: {AnatomicalZone.chin},
      maxDisplacementFse: 0.07,
      invariantId: 'B3',
    ),
    'chin': FaceToolSpecification(
      parameterKey: 'chin',
      primaryZones: {AnatomicalZone.chin},
      freeZones: {AnatomicalZone.chin},
      rigidZones: {AnatomicalZone.lowerLip, AnatomicalZone.oralCavity},
      semiRigidZones: {AnatomicalZone.jawLeft, AnatomicalZone.jawRight},
      maxDisplacementFse: 0.06,
      invariantId: 'B4',
    ),
    'cheekbone': FaceToolSpecification(
      parameterKey: 'cheekbone',
      primaryZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      freeZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
      },
      semiRigidZones: {AnatomicalZone.templeLeft, AnatomicalZone.templeRight},
      maxDisplacementFse: 0.05,
    ),
    'forehead': FaceToolSpecification(
      parameterKey: 'forehead',
      primaryZones: {AnatomicalZone.forehead},
      freeZones: {AnatomicalZone.forehead},
      rigidZones: {AnatomicalZone.browLeft, AnatomicalZone.browRight},
      semiRigidZones: {AnatomicalZone.templeLeft, AnatomicalZone.templeRight},
      maxDisplacementFse: 0.05,
    ),
    'temple': FaceToolSpecification(
      parameterKey: 'temple',
      primaryZones: {AnatomicalZone.templeLeft, AnatomicalZone.templeRight},
      freeZones: {AnatomicalZone.templeLeft, AnatomicalZone.templeRight},
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
      },
      semiRigidZones: {AnatomicalZone.forehead},
      maxDisplacementFse: 0.04,
    ),
    'head_size': FaceToolSpecification(
      parameterKey: 'head_size',
      primaryZones: {AnatomicalZone.skullContour},
      freeZones: _headSizeFreeZones,
      rigidZones: {},
      semiRigidZones: {AnatomicalZone.forehead, AnatomicalZone.browLeft, AnatomicalZone.browRight},
      minScale: 1.0,
      maxScale: 1.12,
    ),
    'nose_slim': FaceToolSpecification(
      parameterKey: 'nose_slim',
      primaryZones: {AnatomicalZone.noseAlae, AnatomicalZone.noseDorsum},
      freeZones: {AnatomicalZone.noseAlae, AnatomicalZone.noseDorsum},
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
        AnatomicalZone.cheekLeft,
        AnatomicalZone.cheekRight,
      },
      semiRigidZones: {AnatomicalZone.noseRoot, AnatomicalZone.noseTip},
      maxDisplacementFse: 0.08,
      invariantId: 'B2',
    ),
    'nose_length': FaceToolSpecification(
      parameterKey: 'nose_length',
      primaryZones: {AnatomicalZone.noseDorsum, AnatomicalZone.noseTip},
      freeZones: {AnatomicalZone.noseDorsum, AnatomicalZone.noseTip},
      rigidZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
      },
      semiRigidZones: {AnatomicalZone.noseAlae},
      maxDisplacementFse: 0.05,
    ),
    'nose_height': FaceToolSpecification(
      parameterKey: 'nose_height',
      primaryZones: {AnatomicalZone.noseRoot, AnatomicalZone.noseDorsum},
      freeZones: {AnatomicalZone.noseRoot, AnatomicalZone.noseDorsum},
      rigidZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      semiRigidZones: {AnatomicalZone.noseTip},
      maxDisplacementFse: 0.04,
    ),
    'nose_tip': FaceToolSpecification(
      parameterKey: 'nose_tip',
      primaryZones: {AnatomicalZone.noseTip},
      freeZones: {AnatomicalZone.noseTip},
      rigidZones: {AnatomicalZone.noseDorsum, AnatomicalZone.noseRoot},
      semiRigidZones: {AnatomicalZone.noseAlae},
      maxDisplacementFse: 0.05,
    ),
    'nose_bridge': FaceToolSpecification(
      parameterKey: 'nose_bridge',
      primaryZones: {AnatomicalZone.noseRoot, AnatomicalZone.noseDorsum},
      freeZones: {AnatomicalZone.noseRoot, AnatomicalZone.noseDorsum},
      rigidZones: {AnatomicalZone.noseTip, AnatomicalZone.noseAlae},
      semiRigidZones: {},
      maxDisplacementFse: 0.06,
    ),
    'eye_scale': FaceToolSpecification(
      parameterKey: 'eye_scale',
      primaryZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      freeZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      rigidZones: {
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
        AnatomicalZone.mouthCorner,
        AnatomicalZone.oralCavity,
        AnatomicalZone.cheekLeft,
        AnatomicalZone.cheekRight,
      },
      semiRigidZones: {AnatomicalZone.browLeft, AnatomicalZone.browRight},
      minScale: 1.0,
      maxScale: 1.26,
      invariantId: 'B5',
    ),
    'eye_distance': FaceToolSpecification(
      parameterKey: 'eye_distance',
      primaryZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      freeZones: {
        AnatomicalZone.eyeLeft,
        AnatomicalZone.eyeRight,
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
      },
      rigidZones: {
        AnatomicalZone.noseTip,
        AnatomicalZone.noseAlae,
      },
      semiRigidZones: {
        AnatomicalZone.noseRoot,
        AnatomicalZone.noseDorsum,
        AnatomicalZone.browLeft,
        AnatomicalZone.browRight,
      },
      maxDisplacementFse: 0.04,
    ),
    'eye_height': FaceToolSpecification(
      parameterKey: 'eye_height',
      primaryZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      freeZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      rigidZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      semiRigidZones: {AnatomicalZone.browLeft, AnatomicalZone.browRight},
      maxDisplacementFse: 0.03,
    ),
    'eye_rotation': FaceToolSpecification(
      parameterKey: 'eye_rotation',
      primaryZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      freeZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      rigidZones: {},
      semiRigidZones: {AnatomicalZone.browLeft, AnatomicalZone.browRight},
      maxRotationDegrees: 3,
    ),
    'double_eyelid': FaceToolSpecification(
      parameterKey: 'double_eyelid',
      primaryZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      freeZones: {AnatomicalZone.eyeLeft, AnatomicalZone.eyeRight},
      rigidZones: {},
      semiRigidZones: {AnatomicalZone.browLeft, AnatomicalZone.browRight},
      maxDisplacementFse: 0.02,
    ),
    'lip_thickness': FaceToolSpecification(
      parameterKey: 'lip_thickness',
      primaryZones: {AnatomicalZone.upperLip, AnatomicalZone.lowerLip},
      freeZones: {AnatomicalZone.upperLip, AnatomicalZone.lowerLip},
      rigidZones: {AnatomicalZone.oralCavity},
      semiRigidZones: {AnatomicalZone.philtrum, AnatomicalZone.chin},
      maxDisplacementFse: 0.04,
      invariantId: 'B6',
    ),
    'mouth_width': FaceToolSpecification(
      parameterKey: 'mouth_width',
      primaryZones: {
        AnatomicalZone.mouthCorner,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
      },
      freeZones: {
        AnatomicalZone.mouthCorner,
        AnatomicalZone.upperLip,
        AnatomicalZone.lowerLip,
      },
      rigidZones: {AnatomicalZone.oralCavity},
      semiRigidZones: {AnatomicalZone.jawLeft, AnatomicalZone.jawRight},
      maxDisplacementFse: 0.05,
    ),
    'smile': FaceToolSpecification(
      parameterKey: 'smile',
      primaryZones: {AnatomicalZone.mouthCorner, AnatomicalZone.upperLip},
      freeZones: {AnatomicalZone.mouthCorner, AnatomicalZone.upperLip},
      rigidZones: {AnatomicalZone.oralCavity, AnatomicalZone.jawLeft, AnatomicalZone.jawRight},
      semiRigidZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      maxDisplacementFse: 0.04,
    ),
  };

  static FaceToolSpecification? forKey(String parameterKey) =>
      toolSpecifications[parameterKey];

  static bool coversAllWarpTools() {
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      if (!toolSpecifications.containsKey(key)) {
        return false;
      }
    }
    return true;
  }
}
