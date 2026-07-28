/// Capacidades declaradas por um provider de visão corporal.
///
/// O Warp Engine consulta este contrato para reduzir ou recusar ajustes
/// quando a evidência necessária não está disponível.
class VisionCapabilities {
  final bool poseLandmarks;
  final bool personMatte;
  final bool bodyPartSegmentation;
  final bool occlusionMap;
  final bool backgroundAnalysis;
  final bool multiPerson;

  const VisionCapabilities({
    this.poseLandmarks = false,
    this.personMatte = false,
    this.bodyPartSegmentation = false,
    this.occlusionMap = false,
    this.backgroundAnalysis = false,
    this.multiPerson = false,
  });

  static const none = VisionCapabilities();

  static const mediapipePoseAndMatte = VisionCapabilities(
    poseLandmarks: true,
    personMatte: true,
  );

  static const mediapipePoseOnly = VisionCapabilities(
    poseLandmarks: true,
  );

  VisionCapabilities merge(VisionCapabilities other) {
    return VisionCapabilities(
      poseLandmarks: poseLandmarks || other.poseLandmarks,
      personMatte: personMatte || other.personMatte,
      bodyPartSegmentation: bodyPartSegmentation || other.bodyPartSegmentation,
      occlusionMap: occlusionMap || other.occlusionMap,
      backgroundAnalysis: backgroundAnalysis || other.backgroundAnalysis,
      multiPerson: multiPerson || other.multiPerson,
    );
  }

  bool get canPlanBodyWarp => poseLandmarks;
}
