import '../models/face_mesh_result.dart';
import '../segment/face_parts_segmentation.dart';

/// Métricas brutas determinísticas (cap. 7) — 1× por foto no load.
class FaceQualityMetrics {
  const FaceQualityMetrics({
    this.faceWidthPx = 0,
    this.faceHeightPx = 0,
    this.blurVariance = 0,
    this.noiseLevel = 0,
    this.highlightClipRatio = 0,
    this.shadowClipRatio = 0,
    this.wbWarmth = 0,
    this.compressionScore = 0,
    this.yawAsymmetry = 0,
    this.pitchEstimate = 0,
    this.landmarkConfidenceMean = 1,
    this.occlusionRatio = 0,
    this.hasFace = false,
    this.hasSkinSegmentation = false,
  });

  final double faceWidthPx;
  final double faceHeightPx;
  final double blurVariance;
  final double noiseLevel;
  final double highlightClipRatio;
  final double shadowClipRatio;
  final double wbWarmth;
  final double compressionScore;
  final double yawAsymmetry;
  final double pitchEstimate;
  final double landmarkConfidenceMean;
  final double occlusionRatio;
  final bool hasFace;
  final bool hasSkinSegmentation;

  double get faceShortEdgePx =>
      faceWidthPx <= 0 || faceHeightPx <= 0
          ? 0
          : faceWidthPx < faceHeightPx
              ? faceWidthPx
              : faceHeightPx;
}

/// Scores agregados 0..1 por dimensão (cap. 7).
class FaceQualityScore {
  const FaceQualityScore({
    required this.sharpness,
    required this.lighting,
    required this.pose,
    required this.integrity,
  });

  final double sharpness;
  final double lighting;
  final double pose;
  final double integrity;

  double get overall =>
      (sharpness * 0.3 + lighting * 0.25 + pose * 0.2 + integrity * 0.25)
          .clamp(0, 1);
}

/// Contexto imutável de qualidade por foto — alimenta gating e presets.
class FaceQualityContext {
  const FaceQualityContext({
    required this.metrics,
    required this.score,
    this.face,
    this.faceParts,
  });

  final FaceQualityMetrics metrics;
  final FaceQualityScore score;
  final FaceMeshResult? face;
  final FacePartsSegmentation? faceParts;

  static const empty = FaceQualityContext(
    metrics: FaceQualityMetrics(),
    score: FaceQualityScore(
      sharpness: 0.5,
      lighting: 0.5,
      pose: 0.5,
      integrity: 0,
    ),
  );
}
