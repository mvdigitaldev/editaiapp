/// Parâmetros de cor (subset compartilhado entre beauty_engine e manual_editor).
class FilterTuneParams {
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double temperature;

  const FilterTuneParams({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.temperature = 0,
  });

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'exposure': exposure,
        'temperature': temperature,
      };

  factory FilterTuneParams.fromJson(Map<String, dynamic> json) {
    return FilterTuneParams(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
    );
  }

  bool get isEmpty =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      exposure == 0 &&
      temperature == 0;
}

/// Preset de filtro LUT + cor para o editor manual (estilo Lightroom).
class FilterPreset {
  final String id;
  final String name;
  final String? lutAssetPath;
  final double lutIntensity;
  final FilterTuneParams tune;
  final bool isBundled;

  const FilterPreset({
    required this.id,
    required this.name,
    this.lutAssetPath,
    this.lutIntensity = 1,
    this.tune = const FilterTuneParams(),
    this.isBundled = false,
  });

  bool get hasLut => lutAssetPath != null && lutAssetPath!.isNotEmpty;

  bool get hasColorAdjustments => !tune.isEmpty || hasLut;
}
