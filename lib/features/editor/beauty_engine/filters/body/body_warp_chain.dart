import 'dart:ui';

import '../../models/pose_result.dart';
import '../../warp/v2/body_legs/body_legs_field.dart';

/// Keys do menu Corpo V2. Cada uma é um Field → DisplacementField →
/// BackwardBilinearWarp, encadeado depois de `applyFaceWarpChain`.
abstract final class BodyWarpChain {
  BodyWarpChain._();

  static const waistKey = 'waist';
  static const legsKey = 'legs';
  static const thighsKey = 'thighs';

  /// Aba «Magro» (Meitu Magro).
  static const slimParameterKeys = <String>[waistKey];

  /// Aba «Pernas» (Meitu Pernas).
  static const legParameterKeys = <String>[legsKey, thighsKey];

  /// Ordem da cadeia: cintura → pernas → coxas.
  static const parameterKeys = <String>[waistKey, legsKey, thighsKey];

  /// Ferramentas só do plano pago.
  static const proParameterKeys = <String>{thighsKey};

  /// Trava de fundo (0 / 1). Não é slider: sozinha não activa nada, e só
  /// chega aqui com plano pago (o editor tira-a nos outros casos).
  static const backgroundLockKey = 'body_bg_lock';

  static bool isPro(String key) => proParameterKeys.contains(key);

  static bool hasActive(Map<String, double> parameters) {
    for (final key in parameterKeys) {
      if ((parameters[key] ?? 0).abs() > 1e-6) {
        return true;
      }
    }
    return false;
  }

  static bool backgroundLockRequested(Map<String, double> parameters) =>
      (parameters[backgroundLockKey] ?? 0) > 0.5;

  /// Tira a trava de fundo e as ferramentas pagas quando o utilizador não
  /// tem direito a elas.
  static Map<String, double> gatePaidFeatures(
    Map<String, double> parameters, {
    required bool allowed,
  }) {
    if (allowed) {
      return parameters;
    }
    final paidKeys = {backgroundLockKey, ...proParameterKeys};
    if (!parameters.keys.any(paidKeys.contains)) {
      return parameters;
    }
    return Map<String, double>.of(parameters)
      ..removeWhere((key, _) => paidKeys.contains(key));
  }

  /// Ferramentas que esta pose não deixa usar: o painel desliga-as e avisa,
  /// como o Meitu («Falha ao reconhecer as linhas das pernas»). Sem pose,
  /// nenhuma ferramenta de perna.
  static Set<String> unavailableKeys({
    required PoseResult? pose,
    required Size imageSize,
  }) {
    if (pose == null) {
      return {legsKey, thighsKey};
    }
    return {
      if (!BodyLegsField.isAvailable(pose: pose, imageSize: imageSize)) legsKey,
      if (!BodyLegsField.isAvailable(
        pose: pose,
        imageSize: imageSize,
        band: BodyLegBand.thighs,
      ))
        thighsKey,
    };
  }

  static bool isLegKey(String key) => legParameterKeys.contains(key);
}
