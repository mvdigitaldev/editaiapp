/// Catálogo facial do produto: Head (Proporção) + Eyebrow Height/Width/End
/// (Sobrancelha) + Eye Size/Height/Width/Length/Distance (Olhos) + Nose Size
/// (Nariz) + Hairline + Jaw + Jaw Angle + Chin Length + V Chin + V Shape +
/// Cheekbones.
class FaceFilterPipeline {
  const FaceFilterPipeline();

  /// Tab Proporção. Não entra no tab Rosto.
  static const proportionParameterKeys = [
    'head',
  ];

  /// Tab Sobrancelha. Não entra no tab Rosto. Não é makeup `eyebrows`.
  static const eyebrowParameterKeys = [
    'eyebrow_height',
    'eyebrow_width',
    'eyebrow_end',
  ];

  /// Tab Olhos. Não é makeup `eyelashes` / `iris_enhance`. Não é `eye_scale`.
  static const eyeParameterKeys = [
    'eye_size',
    'eye_height',
    'eye_width',
    'eye_length',
    'eye_distance',
    'eye_puffy',
  ];

  /// Tab Nariz. Não é `nose_slim` / `nose_length` / `nose_height` / `nose_tip`.
  static const noseParameterKeys = [
    'nose_size',
    'nose_lift',
    'nose_ala',
    'nose_bridge',
  ];

  /// Tab Lábios. Não é `lip_thickness`.
  static const lipParameterKeys = [
    'lip_size',
    'lip_width',
    'lip_height',
    'lip_angle',
    'lip_plump',
  ];

  static const faceWarpParameterKeys = [
    'jaw',
    'jaw_angle',
    'chin',
    'v_chin',
    'v_shape',
    'cheekbone',
    'hairline',
  ];

  bool hasActiveWarp(Map<String, double> parameters) {
    final head = parameters['head'] ?? 0;
    final hairline = parameters['hairline'] ?? 0;
    final jaw = parameters['jaw'] ?? parameters['Jaw'] ?? 0;
    final jawAngle = parameters['jaw_angle'] ?? 0;
    final jawAngleL = parameters['jaw_angle_left'] ?? 0;
    final jawAngleR = parameters['jaw_angle_right'] ?? 0;
    final chin = parameters['chin'] ?? parameters['Chin'] ?? 0;
    final vChin = parameters['v_chin'] ?? 0;
    final vChinL = parameters['v_chin_left'] ?? 0;
    final vChinR = parameters['v_chin_right'] ?? 0;
    final vShape = parameters['v_shape'] ?? 0;
    final vShapeL = parameters['v_shape_left'] ?? 0;
    final vShapeR = parameters['v_shape_right'] ?? 0;
    final cheek = parameters['cheekbone'] ?? parameters['Cheekbone'] ?? 0;
    final cheekL = parameters['cheekbone_left'] ?? 0;
    final cheekR = parameters['cheekbone_right'] ?? 0;
    final brow = parameters['eyebrow_height'] ?? 0;
    final browL = parameters['eyebrow_height_left'] ?? 0;
    final browR = parameters['eyebrow_height_right'] ?? 0;
    final browW = parameters['eyebrow_width'] ?? 0;
    final browWL = parameters['eyebrow_width_left'] ?? 0;
    final browWR = parameters['eyebrow_width_right'] ?? 0;
    final browE = parameters['eyebrow_end'] ?? 0;
    final browEL = parameters['eyebrow_end_left'] ?? 0;
    final browER = parameters['eyebrow_end_right'] ?? 0;
    final eye = parameters['eye_size'] ?? 0;
    final eyeL = parameters['eye_size_left'] ?? 0;
    final eyeR = parameters['eye_size_right'] ?? 0;
    final eyeH = parameters['eye_height'] ?? 0;
    final eyeHL = parameters['eye_height_left'] ?? 0;
    final eyeHR = parameters['eye_height_right'] ?? 0;
    final eyeW = parameters['eye_width'] ?? 0;
    final eyeWL = parameters['eye_width_left'] ?? 0;
    final eyeWR = parameters['eye_width_right'] ?? 0;
    final eyeLen = parameters['eye_length'] ?? 0;
    final eyeLenL = parameters['eye_length_left'] ?? 0;
    final eyeLenR = parameters['eye_length_right'] ?? 0;
    final eyeD = parameters['eye_distance'] ?? 0;
    final eyeDL = parameters['eye_distance_left'] ?? 0;
    final eyeDR = parameters['eye_distance_right'] ?? 0;
    final nose = parameters['nose_size'] ?? 0;
    final noseLift = parameters['nose_lift'] ?? 0;
    final noseAla = parameters['nose_ala'] ?? 0;
    final noseAlaL = parameters['nose_ala_left'] ?? 0;
    final noseAlaR = parameters['nose_ala_right'] ?? 0;
    final noseBridge = parameters['nose_bridge'] ?? 0;
    final lipSize = parameters['lip_size'] ?? 0;
    final lipWidth = parameters['lip_width'] ?? 0;
    final lipHeight = parameters['lip_height'] ?? 0;
    final lipAngle = parameters['lip_angle'] ?? 0;
    final lipPlump = parameters['lip_plump'] ?? 0;
    final lipPlumpU = parameters['lip_plump_upper'] ?? 0;
    final lipPlumpL = parameters['lip_plump_lower'] ?? 0;
    return head.abs() > 1e-6 ||
        brow.abs() > 1e-6 ||
        browL.abs() > 1e-6 ||
        browR.abs() > 1e-6 ||
        browW.abs() > 1e-6 ||
        browWL.abs() > 1e-6 ||
        browWR.abs() > 1e-6 ||
        browE.abs() > 1e-6 ||
        browEL.abs() > 1e-6 ||
        browER.abs() > 1e-6 ||
        eye.abs() > 1e-6 ||
        eyeL.abs() > 1e-6 ||
        eyeR.abs() > 1e-6 ||
        eyeH.abs() > 1e-6 ||
        eyeHL.abs() > 1e-6 ||
        eyeHR.abs() > 1e-6 ||
        eyeW.abs() > 1e-6 ||
        eyeWL.abs() > 1e-6 ||
        eyeWR.abs() > 1e-6 ||
        eyeLen.abs() > 1e-6 ||
        eyeLenL.abs() > 1e-6 ||
        eyeLenR.abs() > 1e-6 ||
        eyeD.abs() > 1e-6 ||
        eyeDL.abs() > 1e-6 ||
        eyeDR.abs() > 1e-6 ||
        nose.abs() > 1e-6 ||
        noseLift.abs() > 1e-6 ||
        noseAla.abs() > 1e-6 ||
        noseAlaL.abs() > 1e-6 ||
        noseAlaR.abs() > 1e-6 ||
        noseBridge.abs() > 1e-6 ||
        lipSize.abs() > 1e-6 ||
        lipWidth.abs() > 1e-6 ||
        lipHeight.abs() > 1e-6 ||
        lipAngle.abs() > 1e-6 ||
        lipPlump.abs() > 1e-6 ||
        lipPlumpU.abs() > 1e-6 ||
        lipPlumpL.abs() > 1e-6 ||
        hairline.abs() > 1e-6 ||
        jaw > 0 ||
        jawAngle.abs() > 1e-6 ||
        jawAngleL.abs() > 1e-6 ||
        jawAngleR.abs() > 1e-6 ||
        chin.abs() > 1e-6 ||
        vChin.abs() > 1e-6 ||
        vChinL.abs() > 1e-6 ||
        vChinR.abs() > 1e-6 ||
        vShape.abs() > 1e-6 ||
        vShapeL.abs() > 1e-6 ||
        vShapeR.abs() > 1e-6 ||
        cheek.abs() > 1e-6 ||
        cheekL.abs() > 1e-6 ||
        cheekR.abs() > 1e-6;
  }
}
