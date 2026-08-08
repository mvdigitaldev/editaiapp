import 'package:editaiapp/features/editor/beauty_engine/filters/color/color_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pipeline = ColorFilterPipeline();

  group('ColorFilterPipeline', () {
    test('hasActiveColor detecta parâmetro não zero', () {
      expect(pipeline.hasActiveColor(const {}), isFalse);
      expect(
        pipeline.hasActiveColor(const {'exposure': 0.2}),
        isTrue,
      );
      expect(
        pipeline.hasActiveColor(const {'face_slim': 0.5}),
        isFalse,
      );
    });

    test('buildColorStages retorna colorGrade shader', () {
      final stages = pipeline.buildColorStages(
        parameters: const {'saturation': 0.3},
      );
      expect(stages, hasLength(1));
      expect(stages.first.shaderName, RenderShaders.colorGrade);
    });

    test('extractTuneParams mapeia keys flat', () {
      final tune = pipeline.extractTuneParams(const {
        'exposure': 0.1,
        'vignette': -0.2,
        'face_slim': 1,
      });
      expect(tune.exposure, 0.1);
      expect(tune.vignette, -0.2);
      expect(tune.brightness, 0);
    });
  });
}
