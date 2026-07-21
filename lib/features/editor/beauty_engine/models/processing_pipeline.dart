import 'beauty_preset.dart';

/// Pipeline de efeitos a aplicar numa imagem.
class ProcessingPipeline {
  final BeautyPreset? preset;
  final Map<String, double> overrides;

  const ProcessingPipeline({
    this.preset,
    this.overrides = const {},
  });

  Map<String, double> get effectiveParameters {
    final base = preset?.toParameterMap() ?? const <String, double>{};
    return {...base, ...overrides};
  }
}
