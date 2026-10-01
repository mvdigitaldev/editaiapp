import 'dart:ui';

import '../../models/pose_result.dart';
import '../../warp/v2/body_arms/body_arms_field.dart';
import '../../warp/v2/body_chest/body_chest_field.dart';
import '../../warp/v2/body_legs/body_legs_field.dart';

/// Keys do menu Corpo V2. Cada uma é um Field → DisplacementField →
/// BackwardBilinearWarp, encadeado depois de `applyFaceWarpChain`.
abstract final class BodyWarpChain {
  BodyWarpChain._();

  static const waistKey = 'waist';
  static const hipsKey = 'hips';
  static const legsKey = 'legs';
  static const thighsKey = 'thighs';
  static const calvesKey = 'calves';
  static const armsKey = 'arms';
  static const chestKey = 'chest';

  /// Aba «Magro» (Meitu Magro).
  static const slimParameterKeys = <String>[waistKey];

  /// Aba «Curvas» (Meitu Curvas).
  static const curveParameterKeys = <String>[hipsKey];

  /// Aba «Braços» (Meitu Braços).
  static const armParameterKeys = <String>[armsKey];

  /// Aba «Busto» (Meitu Busto).
  static const chestParameterKeys = <String>[chestKey];

  /// Aba «Pernas» (Meitu Pernas).
  static const legParameterKeys = <String>[legsKey, thighsKey, calvesKey];

  /// Ordem da cadeia: cintura → quadris → pernas → coxas → canelas → braços
  /// → busto.
  static const parameterKeys = <String>[
    waistKey,
    hipsKey,
    legsKey,
    thighsKey,
    calvesKey,
    armsKey,
    chestKey,
  ];

  /// Ferramentas só do plano pago.
  static const proParameterKeys = <String>{thighsKey, calvesKey};

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
      return {legsKey, thighsKey, calvesKey, armsKey, chestKey};
    }
    return {
      if (!BodyArmsField.isAvailable(pose: pose, imageSize: imageSize)) armsKey,
      if (!BodyChestField.isAvailable(pose: pose, imageSize: imageSize))
        chestKey,
      if (!BodyLegsField.isAvailable(pose: pose, imageSize: imageSize)) legsKey,
      if (!BodyLegsField.isAvailable(
        pose: pose,
        imageSize: imageSize,
        band: BodyLegBand.thighs,
      ))
        thighsKey,
      if (!BodyLegsField.isAvailable(
        pose: pose,
        imageSize: imageSize,
        band: BodyLegBand.calves,
      ))
        calvesKey,
    };
  }

  static bool isLegKey(String key) => legParameterKeys.contains(key);
}
