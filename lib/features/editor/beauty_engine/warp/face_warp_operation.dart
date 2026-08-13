import 'anatomy/face_model_specification.dart';

/// Descritor de uma operação configurável de Face Warp (Fase 15).
///
/// Cada ferramenta facial futura deve ser registrável como [FaceWarpOperation]
/// sem duplicar solver ou Safety Gate.
class FaceWarpOperation {
  const FaceWarpOperation({
    required this.id,
    required this.parameterKey,
    required this.spec,
    this.compositionMode = FaceWarpCompositionMode.additive,
  });

  /// Identificador estável (igual ao [parameterKey] para sliders existentes).
  final String id;

  /// Chave no mapa `parameters` do editor.
  final String parameterKey;

  /// Especificação anatômica (região, pins, limites).
  final FaceToolSpecification spec;

  /// Como combinar com outras operações ativas na mesma malha.
  final FaceWarpCompositionMode compositionMode;
}

/// Modo de composição entre operações simultâneas.
enum FaceWarpCompositionMode {
  /// Soma vetorial de deslocamentos (MVP rosto — doc 23).
  additive,

  /// Resolução por prioridade (ferramentas não-MVP / olhos / boca).
  priority,
}
