import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/face_quality_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List solidImage(int width, int height, int gray) {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = gray;
      rgba[i + 1] = gray;
      rgba[i + 2] = gray;
      rgba[i + 3] = 255;
    }
    return rgba;
  }

  FaceMeshResult syntheticFace() {
    final landmarks = <FaceLandmark>[
      for (var i = 0; i < 478; i++)
        FaceLandmark(
          index: i,
          normalized: Offset(0.5, 0.5),
          visibility: 1,
        ),
    ];
    return FaceMeshResult(
      landmarks: landmarks,
      boundingBox: const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8),
      confidence: 0.95,
    );
  }

  group('FaceQualityAssessment', () {
    test('foto uniforme tem sharpness baixo', () {
      final ctx = FaceQualityAssessment.assess(
        rgba: solidImage(64, 64, 128),
        width: 64,
        height: 64,
        face: syntheticFace(),
      );
      expect(ctx.score.sharpness, lessThan(0.2));
    });

    test('foto com ruído aumenta noiseLevel vs uniforme', () {
      const w = 64;
      const h = 64;
      final clean = solidImage(w, h, 128);
      final noisy = Uint8List.fromList(clean);
      // Perturba região central (patch de bochecha simulada).
      for (var y = 24; y < 40; y++) {
        for (var x = 24; x < 40; x++) {
          final i = (y * w + x) * 4;
          noisy[i] = (128 + (x + y) % 40).clamp(0, 255);
        }
      }
      final cleanCtx = FaceQualityAssessment.assess(
        rgba: clean,
        width: w,
        height: h,
        face: syntheticFace(),
      );
      final noisyCtx = FaceQualityAssessment.assess(
        rgba: noisy,
        width: w,
        height: h,
        face: syntheticFace(),
      );
      expect(noisyCtx.metrics.noiseLevel, greaterThan(cleanCtx.metrics.noiseLevel));
    });

    test('sem rosto integridade baixa', () {
      final ctx = FaceQualityAssessment.assess(
        rgba: solidImage(32, 32, 100),
        width: 32,
        height: 32,
      );
      expect(ctx.metrics.hasFace, isFalse);
      expect(ctx.score.integrity, lessThan(0.5));
    });
  });
}
