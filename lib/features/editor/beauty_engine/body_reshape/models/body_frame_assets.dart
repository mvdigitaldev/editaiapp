import 'dart:ui';

import 'background_analysis.dart';
import 'body_joint.dart';
import 'body_part_segmentation.dart';
import 'occlusion_map.dart';
import 'person_matte.dart';
import '../providers/vision_capabilities.dart';

/// Dados semânticos de uma pessoa necessários para planejar a deformação.
class BodyFrameAssets {
  final Map<BodyJoint, BodyLandmark> landmarks;
  final Rect boundingBox;
  final bool isPartial;
  final String providerId;
  final double confidence;
  final VisionCapabilities capabilities;
  final PersonMatte? personMatte;
  final BodyPartSegmentation? partSegmentation;
  final OcclusionMap? occlusionMap;
  final BackgroundAnalysis? backgroundAnalysis;

  const BodyFrameAssets({
    required this.landmarks,
    required this.boundingBox,
    required this.providerId,
    required this.capabilities,
    this.isPartial = false,
    this.confidence = 1,
    this.personMatte,
    this.partSegmentation,
    this.occlusionMap,
    this.backgroundAnalysis,
  }) : assert(confidence >= 0 && confidence <= 1);

  BodyLandmark? landmark(BodyJoint joint) => landmarks[joint];

  bool get hasOcclusionEvidence =>
      (occlusionMap != null && !occlusionMap!.isEmpty) ||
      (partSegmentation != null && !partSegmentation!.isEmpty);

  bool containsAll(Iterable<BodyJoint> joints) {
    return joints.every(landmarks.containsKey);
  }

  double confidenceFor(Iterable<BodyJoint> joints) {
    var total = 0.0;
    var count = 0;
    for (final joint in joints) {
      final point = landmarks[joint];
      if (point == null) {
        return 0;
      }
      total += point.confidence;
      count++;
    }
    return count == 0 ? confidence : total / count;
  }

  BodyFrameAssets copyWith({
    Map<BodyJoint, BodyLandmark>? landmarks,
    Rect? boundingBox,
    bool? isPartial,
    String? providerId,
    double? confidence,
    VisionCapabilities? capabilities,
    PersonMatte? personMatte,
    BodyPartSegmentation? partSegmentation,
    OcclusionMap? occlusionMap,
    BackgroundAnalysis? backgroundAnalysis,
  }) {
    return BodyFrameAssets(
      landmarks: landmarks ?? this.landmarks,
      boundingBox: boundingBox ?? this.boundingBox,
      isPartial: isPartial ?? this.isPartial,
      providerId: providerId ?? this.providerId,
      confidence: confidence ?? this.confidence,
      capabilities: capabilities ?? this.capabilities,
      personMatte: personMatte ?? this.personMatte,
      partSegmentation: partSegmentation ?? this.partSegmentation,
      occlusionMap: occlusionMap ?? this.occlusionMap,
      backgroundAnalysis: backgroundAnalysis ?? this.backgroundAnalysis,
    );
  }
}
