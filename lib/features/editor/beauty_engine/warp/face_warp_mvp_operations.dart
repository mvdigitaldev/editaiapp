import '../filters/face/face_filter_pipeline.dart';
import 'anatomy/face_model_specification.dart';
import 'face_warp_operation.dart';

/// Operações MVP de contorno facial (Fase 15).
///
/// Nariz, olhos, boca, pele e cor ficam fora desta fase — mas reutilizarão
/// o mesmo pipeline estrutural quando forem habilitadas.
abstract final class FaceWarpMvpOperations {
  FaceWarpMvpOperations._();

  /// Sliders MVP de rosto (menu Fase 15).
  static const parameterKeys = [
    'face_slim',
    'narrow_face',
    'v_face',
    'jaw',
    'chin',
    'cheekbone',
    'forehead',
  ];

  /// Ferramentas laterais de contorno MVP — usam malha backward unificada.
  static const contourToolKeys = {
    'face_slim',
    'narrow_face',
    'v_face',
    'jaw',
  };

  /// Operações registradas (lazy via spec).
  static List<FaceWarpOperation> get all => [
        for (final key in parameterKeys)
          if (FaceModelSpecification.forKey(key) case final spec?)
            FaceWarpOperation(
              id: key,
              parameterKey: key,
              spec: spec,
            ),
      ];

  static bool isMvpKey(String key) => parameterKeys.contains(key);

  static bool hasActiveMvpTool(Map<String, double> parameters) {
    for (final key in parameterKeys) {
      if ((parameters[key] ?? 0) > 1e-6) {
        return true;
      }
    }
    return false;
  }

  /// Composição aditiva entre ferramentas MVP (evita que slider posterior
  /// substitua o efeito de slider anterior na mesma zona).
  static bool usesAdditiveComposition(String toolKey) => isMvpKey(toolKey);

  /// Malha backward V3 quando só ferramentas MVP de contorno estão ativas
  /// (sem olhos/boca laterais que exigem vacancy na grade).
  static bool usesMvpMeshPath(Map<String, double> parameters) {
    if (!hasActiveMvpTool(parameters)) {
      return false;
    }
    const nonMvpLateral = {'eye_distance', 'mouth_width'};
    for (final key in nonMvpLateral) {
      if ((parameters[key] ?? 0) > 1e-6) {
        return false;
      }
    }
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      if (parameterKeys.contains(key) || nonMvpLateral.contains(key)) {
        continue;
      }
      if ((parameters[key] ?? 0) > 1e-6) {
        return false;
      }
    }
    return true;
  }
}
