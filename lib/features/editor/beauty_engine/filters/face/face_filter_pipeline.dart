/// Catálogo facial do produto: Jaw + Chin (Facial Warp V2).
class FaceFilterPipeline {
  const FaceFilterPipeline();

  static const faceWarpParameterKeys = ['jaw', 'chin'];

  bool hasActiveWarp(Map<String, double> parameters) {
    final jaw = parameters['jaw'] ?? parameters['Jaw'] ?? 0;
    final chin = parameters['chin'] ?? parameters['Chin'] ?? 0;
    return jaw > 0 || chin > 0;
  }
}
