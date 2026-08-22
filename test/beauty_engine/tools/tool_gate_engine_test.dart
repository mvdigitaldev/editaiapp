import 'package:editaiapp/features/editor/beauty_engine/quality/face_quality_context.dart';
import 'package:editaiapp/features/editor/beauty_engine/tools/tool_gate_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = ToolGateEngine();

  FaceQualityContext blurrySmallFace() {
    return FaceQualityContext(
      metrics: const FaceQualityMetrics(
        hasFace: true,
        faceWidthPx: 120,
        faceHeightPx: 140,
        blurVariance: 30,
        noiseLevel: 0.1,
      ),
      score: const FaceQualityScore(
        sharpness: 0.2,
        lighting: 0.7,
        pose: 0.8,
        integrity: 0.45,
      ),
    );
  }

  group('ToolGateEngine', () {
    test('skin_smooth reduzido em foto borrada', () {
      final plan = engine.evaluate(blurrySmallFace());
      final d = plan.decisionFor('skin_smooth');
      expect(d.isReduced, isTrue);
      expect(d.applySliderValue(1.0), lessThan(0.6));
    });

    test('remove_acne desabilitado em rosto minúsculo', () {
      final ctx = FaceQualityContext(
        metrics: const FaceQualityMetrics(
          hasFace: true,
          faceWidthPx: 100,
          faceHeightPx: 120,
        ),
        score: const FaceQualityScore(
          sharpness: 0.8,
          lighting: 0.8,
          pose: 0.9,
          integrity: 0.3,
        ),
      );
      final d = engine.evaluate(ctx).decisionFor('remove_acne');
      expect(d.isDisabled, isTrue);
    });

    test('warp desabilitado sem rosto', () {
      final plan = engine.evaluate(FaceQualityContext.empty);
      expect(plan.decisionFor('jaw').isDisabled, isTrue);
    });

    test('applyToParameters respeita caps', () {
      final plan = engine.evaluate(blurrySmallFace());
      final out = plan.applyToParameters(const {'skin_smooth': 1.0});
      expect(out['skin_smooth'], lessThan(1.0));
    });
  });
}
