/// Catálogo facial do produto: Jaw + Chin Length + V Chin + V Shape + Cheekbones (Facial Warp V2).
class FaceFilterPipeline {
  const FaceFilterPipeline();

  static const faceWarpParameterKeys = [
    'jaw',
    'chin',
    'v_chin',
    'v_shape',
    'cheekbone',
  ];

  bool hasActiveWarp(Map<String, double> parameters) {
    final jaw = parameters['jaw'] ?? parameters['Jaw'] ?? 0;
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
    return jaw > 0 ||
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
