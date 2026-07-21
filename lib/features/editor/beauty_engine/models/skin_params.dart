/// Parâmetros de pele e makeup (Sprint 17).
class SkinParams {
  final double smooth;
  final double whitening;
  final double acne;
  final double wrinkles;
  final double darkCircles;
  final double teethWhitening;
  final double blush;
  final double contour;
  final double eyebrows;
  final double eyelashes;

  const SkinParams({
    this.smooth = 0,
    this.whitening = 0,
    this.acne = 0,
    this.wrinkles = 0,
    this.darkCircles = 0,
    this.teethWhitening = 0,
    this.blush = 0,
    this.contour = 0,
    this.eyebrows = 0,
    this.eyelashes = 0,
  });

  Map<String, dynamic> toJson() => {
        'smooth': smooth,
        'whitening': whitening,
        'acne': acne,
        'wrinkles': wrinkles,
        'darkCircles': darkCircles,
        'teethWhitening': teethWhitening,
        'blush': blush,
        'contour': contour,
        'eyebrows': eyebrows,
        'eyelashes': eyelashes,
      };

  factory SkinParams.fromJson(Map<String, dynamic> json) {
    return SkinParams(
      smooth: (json['smooth'] as num?)?.toDouble() ?? 0,
      whitening: (json['whitening'] as num?)?.toDouble() ?? 0,
      acne: (json['acne'] as num?)?.toDouble() ?? 0,
      wrinkles: (json['wrinkles'] as num?)?.toDouble() ?? 0,
      darkCircles: (json['darkCircles'] as num?)?.toDouble() ?? 0,
      teethWhitening: (json['teethWhitening'] as num?)?.toDouble() ?? 0,
      blush: (json['blush'] as num?)?.toDouble() ?? 0,
      contour: (json['contour'] as num?)?.toDouble() ?? 0,
      eyebrows: (json['eyebrows'] as num?)?.toDouble() ?? 0,
      eyelashes: (json['eyelashes'] as num?)?.toDouble() ?? 0,
    );
  }
}
