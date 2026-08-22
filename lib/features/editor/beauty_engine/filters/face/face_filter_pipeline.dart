/// Catálogo facial do produto: só Jaw (Facial Warp V2).
class FaceFilterPipeline {
  const FaceFilterPipeline();

  static const faceWarpParameterKeys = ['jaw'];

  bool hasActiveWarp(Map<String, double> parameters) {
    final jaw = parameters['jaw'] ?? parameters['Jaw'] ?? 0;
    return jaw > 0;
  }
}
