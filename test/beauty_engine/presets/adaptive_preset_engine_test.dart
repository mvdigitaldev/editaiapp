import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/skin_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tune_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/adaptive_preset_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/face_quality_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = AdaptivePresetEngine();

  const preset = BeautyPreset(
    id: 'bundled_beauty',
    name: 'Beleza',
    tune: TuneParams(temperature: 0.2),
    skin: SkinParams(smooth: 0.8),
    face: FaceParams(faceSlim: 0.5),
  );

  group('AdaptivePresetEngine', () {
    test('foto borrada reduz skin_smooth vs foto nítida', () {
      const sharp = FaceQualityContext(
        metrics: FaceQualityMetrics(hasFace: true, faceWidthPx: 400),
        score: FaceQualityScore(
          sharpness: 0.9,
          lighting: 0.9,
          pose: 0.9,
          integrity: 0.9,
        ),
      );
      const blurry = FaceQualityContext(
        metrics: FaceQualityMetrics(hasFace: true, faceWidthPx: 400),
        score: FaceQualityScore(
          sharpness: 0.2,
          lighting: 0.7,
          pose: 0.8,
          integrity: 0.7,
        ),
      );

      final sharpOut = engine.modulate(preset: preset, quality: sharp);
      final blurryOut = engine.modulate(preset: preset, quality: blurry);

      expect(blurryOut['skin_smooth']!, lessThan(sharpOut['skin_smooth']!));
    });

    test('foto quente reduz temperatura adicionada', () {
      const warm = FaceQualityContext(
        metrics: FaceQualityMetrics(hasFace: true, wbWarmth: 0.6),
        score: FaceQualityScore(
          sharpness: 0.8,
          lighting: 0.8,
          pose: 0.8,
          integrity: 0.8,
        ),
      );
      const neutral = FaceQualityContext(
        metrics: FaceQualityMetrics(hasFace: true, wbWarmth: 0),
        score: FaceQualityScore(
          sharpness: 0.8,
          lighting: 0.8,
          pose: 0.8,
          integrity: 0.8,
        ),
      );

      final warmOut = engine.modulate(preset: preset, quality: warm);
      final neutralOut = engine.modulate(preset: preset, quality: neutral);

      expect(warmOut['temperature']!.abs(), lessThan(neutralOut['temperature']!.abs()));
    });
  });
}
