/// Parâmetros faciais (sliders 0..1).
class FaceParams {
  final double faceSlim;
  final double narrowFace;
  final double vFace;
  final double noseSlim;
  final double noseLength;
  final double noseHeight;
  final double noseTip;
  final double noseBridge;
  final double eyeScale;
  final double eyeDistance;
  final double eyeHeight;
  final double eyeRotation;
  final double doubleEyelid;
  final bool linkEyes;
  final double jaw;
  final double chin;
  final double cheekbone;
  final double forehead;
  final double temple;
  final double mouthWidth;
  final double lipThickness;
  final double smile;

  const FaceParams({
    this.faceSlim = 0,
    this.narrowFace = 0,
    this.vFace = 0,
    this.noseSlim = 0,
    this.noseLength = 0,
    this.noseHeight = 0,
    this.noseTip = 0,
    this.noseBridge = 0,
    this.eyeScale = 0,
    this.eyeDistance = 0,
    this.eyeHeight = 0,
    this.eyeRotation = 0,
    this.doubleEyelid = 0,
    this.linkEyes = true,
    this.jaw = 0,
    this.chin = 0,
    this.cheekbone = 0,
    this.forehead = 0,
    this.temple = 0,
    this.mouthWidth = 0,
    this.lipThickness = 0,
    this.smile = 0,
  });

  Map<String, dynamic> toJson() => {
        'faceSlim': faceSlim,
        'narrowFace': narrowFace,
        'vFace': vFace,
        'noseSlim': noseSlim,
        'noseLength': noseLength,
        'noseHeight': noseHeight,
        'noseTip': noseTip,
        'noseBridge': noseBridge,
        'eyeScale': eyeScale,
        'eyeDistance': eyeDistance,
        'eyeHeight': eyeHeight,
        'eyeRotation': eyeRotation,
        'doubleEyelid': doubleEyelid,
        'linkEyes': linkEyes,
        'jaw': jaw,
        'chin': chin,
        'cheekbone': cheekbone,
        'forehead': forehead,
        'temple': temple,
        'mouthWidth': mouthWidth,
        'lipThickness': lipThickness,
        'smile': smile,
      };

  factory FaceParams.fromJson(Map<String, dynamic> json) {
    return FaceParams(
      faceSlim: (json['faceSlim'] as num?)?.toDouble() ?? 0,
      narrowFace: (json['narrowFace'] as num?)?.toDouble() ?? 0,
      vFace: (json['vFace'] as num?)?.toDouble() ?? 0,
      noseSlim: (json['noseSlim'] as num?)?.toDouble() ?? 0,
      noseLength: (json['noseLength'] as num?)?.toDouble() ?? 0,
      noseHeight: (json['noseHeight'] as num?)?.toDouble() ?? 0,
      noseTip: (json['noseTip'] as num?)?.toDouble() ?? 0,
      noseBridge: (json['noseBridge'] as num?)?.toDouble() ?? 0,
      eyeScale: (json['eyeScale'] as num?)?.toDouble() ?? 0,
      eyeDistance: (json['eyeDistance'] as num?)?.toDouble() ?? 0,
      eyeHeight: (json['eyeHeight'] as num?)?.toDouble() ?? 0,
      eyeRotation: (json['eyeRotation'] as num?)?.toDouble() ?? 0,
      doubleEyelid: (json['doubleEyelid'] as num?)?.toDouble() ?? 0,
      linkEyes: json['linkEyes'] as bool? ?? true,
      jaw: (json['jaw'] as num?)?.toDouble() ?? 0,
      chin: (json['chin'] as num?)?.toDouble() ?? 0,
      cheekbone: (json['cheekbone'] as num?)?.toDouble() ?? 0,
      forehead: (json['forehead'] as num?)?.toDouble() ?? 0,
      temple: (json['temple'] as num?)?.toDouble() ?? 0,
      mouthWidth: (json['mouthWidth'] as num?)?.toDouble() ?? 0,
      lipThickness: (json['lipThickness'] as num?)?.toDouble() ?? 0,
      smile: (json['smile'] as num?)?.toDouble() ?? 0,
    );
  }
}
