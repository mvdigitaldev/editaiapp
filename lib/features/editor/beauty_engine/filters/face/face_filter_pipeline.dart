/// Catálogo facial do produto: Jaw + Chin + Cheekbones (Facial Warp V2).
class FaceFilterPipeline {
  const FaceFilterPipeline();

  static const faceWarpParameterKeys = ['jaw', 'chin', 'cheekbone'];

  bool hasActiveWarp(Map<String, double> parameters) {
    final jaw = parameters['jaw'] ?? parameters['Jaw'] ?? 0;
    final chin = parameters['chin'] ?? parameters['Chin'] ?? 0;
    final cheek = parameters['cheekbone'] ?? parameters['Cheekbone'] ?? 0;
    final cheekL = parameters['cheekbone_left'] ?? 0;
    final cheekR = parameters['cheekbone_right'] ?? 0;
    return jaw > 0 ||
        chin > 0 ||
        cheek.abs() > 1e-6 ||
        cheekL.abs() > 1e-6 ||
        cheekR.abs() > 1e-6;
  }
}
