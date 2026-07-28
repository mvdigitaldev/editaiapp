/// Parâmetros corporais (sliders 0..1).
class BodyParams {
  final double waistSlim;
  final double hip;
  final double bodySlim;
  final double legLength;
  final double legSlim;
  final double armSlim;
  final double neckSlim;
  final double shoulderWidth;
  final double headSize;

  const BodyParams({
    this.waistSlim = 0,
    this.hip = 0,
    this.bodySlim = 0,
    this.legLength = 0,
    this.legSlim = 0,
    this.armSlim = 0,
    this.neckSlim = 0,
    this.shoulderWidth = 0,
    this.headSize = 0,
  });

  Map<String, dynamic> toJson() => {
        'waistSlim': waistSlim,
        'hip': hip,
        'bodySlim': bodySlim,
        'legLength': legLength,
        'legSlim': legSlim,
        'armSlim': armSlim,
        'neckSlim': neckSlim,
        'shoulderWidth': shoulderWidth,
        'headSize': headSize,
      };

  /// Chaves consumidas pelos pipelines de edição e presets.
  Map<String, double> toParameterMap() => {
        'waist_slim': waistSlim,
        'hip': hip,
        'body_slim': bodySlim,
        'leg_length': legLength,
        'leg_slim': legSlim,
        'arm_slim': armSlim,
        'neck_slim': neckSlim,
        'shoulder_width': shoulderWidth,
        'head_size': headSize,
      };

  factory BodyParams.fromJson(Map<String, dynamic> json) {
    return BodyParams(
      waistSlim: (json['waistSlim'] as num?)?.toDouble() ?? 0,
      hip: (json['hip'] as num?)?.toDouble() ?? 0,
      bodySlim: (json['bodySlim'] as num?)?.toDouble() ?? 0,
      legLength: (json['legLength'] as num?)?.toDouble() ?? 0,
      legSlim: (json['legSlim'] as num?)?.toDouble() ?? 0,
      armSlim: (json['armSlim'] as num?)?.toDouble() ?? 0,
      neckSlim: (json['neckSlim'] as num?)?.toDouble() ?? 0,
      shoulderWidth: (json['shoulderWidth'] as num?)?.toDouble() ?? 0,
      headSize: (json['headSize'] as num?)?.toDouble() ?? 0,
    );
  }
}
