/// Keys do menu Corpo V2. Cada uma é um Field → DisplacementField →
/// BackwardBilinearWarp, encadeado depois de `applyFaceWarpChain`.
abstract final class BodyWarpChain {
  BodyWarpChain._();

  static const waistKey = 'waist';
  static const legsKey = 'legs';

  /// Aba «Magro» (Meitu Magro).
  static const slimParameterKeys = <String>[waistKey];

  /// Aba «Pernas» (Meitu Pernas).
  static const legParameterKeys = <String>[legsKey];

  /// Ordem da cadeia: cintura → pernas.
  static const parameterKeys = <String>[waistKey, legsKey];

  /// Trava de fundo (0 / 1). Não é slider: sozinha não activa nada, e só
  /// chega aqui com plano pago (o editor tira-a nos outros casos).
  static const backgroundLockKey = 'body_bg_lock';

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

  /// Tira a trava quando o utilizador não tem direito a ela.
  static Map<String, double> gateBackgroundLock(
    Map<String, double> parameters, {
    required bool allowed,
  }) {
    if (allowed || !parameters.containsKey(backgroundLockKey)) {
      return parameters;
    }
    return Map<String, double>.of(parameters)..remove(backgroundLockKey);
  }
}
