/// Parâmetros de ajuste de cor (Lightroom-style).
class TuneParams {
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double temperature;

  const TuneParams({
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

  factory TuneParams.fromJson(Map<String, dynamic> json) {
    return TuneParams(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
    );
  }
}
