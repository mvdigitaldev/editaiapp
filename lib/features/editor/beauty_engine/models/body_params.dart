/// Parâmetros corporais (sliders 0..1).
///
/// Campos novos (Sprint 12) têm default 0 — presets antigos continuam válidos.
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
  final double chestExpand;
  final double bellyReduce;
  final double buttExpand;
  final double height;
  final double shoulderReduce;
  final double armUpperSlim;
  final double armForearmSlim;
  final double legThighSlim;
  final double legCalfSlim;

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
    this.chestExpand = 0,
    this.bellyReduce = 0,
    this.buttExpand = 0,
    this.height = 0,
    this.shoulderReduce = 0,
    this.armUpperSlim = 0,
    this.armForearmSlim = 0,
    this.legThighSlim = 0,
    this.legCalfSlim = 0,
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
        'chestExpand': chestExpand,
        'bellyReduce': bellyReduce,
        'buttExpand': buttExpand,
        'height': height,
        'shoulderReduce': shoulderReduce,
        'armUpperSlim': armUpperSlim,
        'armForearmSlim': armForearmSlim,
        'legThighSlim': legThighSlim,
        'legCalfSlim': legCalfSlim,
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
        'chest_expand': chestExpand,
        'belly_reduce': bellyReduce,
        'butt_expand': buttExpand,
        'height': height,
        'shoulder_reduce': shoulderReduce,
        'arm_upper_slim': armUpperSlim,
        'arm_forearm_slim': armForearmSlim,
        'leg_thigh_slim': legThighSlim,
        'leg_calf_slim': legCalfSlim,
      };

  factory BodyParams.fromJson(Map<String, dynamic> json) {
    double read(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return BodyParams(
      waistSlim: read('waistSlim'),
      hip: read('hip'),
      bodySlim: read('bodySlim'),
      legLength: read('legLength'),
      legSlim: read('legSlim'),
      armSlim: read('armSlim'),
      neckSlim: read('neckSlim'),
      shoulderWidth: read('shoulderWidth'),
      headSize: read('headSize'),
      chestExpand: read('chestExpand'),
      bellyReduce: read('bellyReduce'),
      buttExpand: read('buttExpand'),
      height: read('height'),
      shoulderReduce: read('shoulderReduce'),
      armUpperSlim: read('armUpperSlim'),
      armForearmSlim: read('armForearmSlim'),
      legThighSlim: read('legThighSlim'),
      legCalfSlim: read('legCalfSlim'),
    );
  }

  /// Migra mapa legado (só keys antigas) para [BodyParams] completo.
  factory BodyParams.fromParameterMap(Map<String, double> parameters) {
    double p(String snake, [String? camel]) {
      final v = parameters[snake] ??
          (camel != null ? parameters[camel] : null) ??
          0;
      return v.clamp(0.0, 1.0);
    }

    return BodyParams(
      waistSlim: p('waist_slim', 'waistSlim'),
      hip: p('hip'),
      bodySlim: p('body_slim', 'bodySlim'),
      legLength: p('leg_length', 'legLength'),
      legSlim: p('leg_slim', 'legSlim'),
      armSlim: p('arm_slim', 'armSlim'),
      neckSlim: p('neck_slim', 'neckSlim'),
      shoulderWidth: p('shoulder_width', 'shoulderWidth'),
      headSize: p('head_size', 'headSize'),
      chestExpand: p('chest_expand', 'chestExpand'),
      bellyReduce: p('belly_reduce', 'bellyReduce'),
      buttExpand: p('butt_expand', 'buttExpand'),
      height: p('height'),
      shoulderReduce: p('shoulder_reduce', 'shoulderReduce'),
      armUpperSlim: p('arm_upper_slim', 'armUpperSlim'),
      armForearmSlim: p('arm_forearm_slim', 'armForearmSlim'),
      legThighSlim: p('leg_thigh_slim', 'legThighSlim'),
      legCalfSlim: p('leg_calf_slim', 'legCalfSlim'),
    );
  }
}
