/// Parâmetros de ajuste de cor estilo Lightroom (grade completa).
class TuneParams {
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double temperature;
  final double tint;
  final double vibrance;
  final double hue;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double fade;
  final double sharpness;
  final double luminance;
  final double vignette;
  final double gamma;

  const TuneParams({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.temperature = 0,
    this.tint = 0,
    this.vibrance = 0,
    this.hue = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.fade = 0,
    this.sharpness = 0,
    this.luminance = 0,
    this.vignette = 0,
    this.gamma = 0,
  });

  bool get isEmpty =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      exposure == 0 &&
      temperature == 0 &&
      tint == 0 &&
      vibrance == 0 &&
      hue == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      whites == 0 &&
      blacks == 0 &&
      fade == 0 &&
      sharpness == 0 &&
      luminance == 0 &&
      vignette == 0 &&
      gamma == 0;

  TuneParams copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? temperature,
    double? tint,
    double? vibrance,
    double? hue,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? fade,
    double? sharpness,
    double? luminance,
    double? vignette,
    double? gamma,
  }) {
    return TuneParams(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      exposure: exposure ?? this.exposure,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      vibrance: vibrance ?? this.vibrance,
      hue: hue ?? this.hue,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      fade: fade ?? this.fade,
      sharpness: sharpness ?? this.sharpness,
      luminance: luminance ?? this.luminance,
      vignette: vignette ?? this.vignette,
      gamma: gamma ?? this.gamma,
    );
  }

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'exposure': exposure,
        'temperature': temperature,
        'tint': tint,
        'vibrance': vibrance,
        'hue': hue,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'fade': fade,
        'sharpness': sharpness,
        'luminance': luminance,
        'vignette': vignette,
        'gamma': gamma,
      };

  factory TuneParams.fromJson(Map<String, dynamic> json) {
    return TuneParams(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0,
      vibrance: (json['vibrance'] as num?)?.toDouble() ?? 0,
      hue: (json['hue'] as num?)?.toDouble() ?? 0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0,
      whites: (json['whites'] as num?)?.toDouble() ?? 0,
      blacks: (json['blacks'] as num?)?.toDouble() ?? 0,
      fade: (json['fade'] as num?)?.toDouble() ?? 0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0,
      luminance: (json['luminance'] as num?)?.toDouble() ?? 0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0,
      gamma: (json['gamma'] as num?)?.toDouble() ?? 0,
    );
  }
}
