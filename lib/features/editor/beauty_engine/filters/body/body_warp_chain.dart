/// Keys do menu Corpo V2. Cada uma é um Field → DisplacementField →
/// BackwardBilinearWarp, encadeado depois de `applyFaceWarpChain`.
abstract final class BodyWarpChain {
  BodyWarpChain._();

  static const waistKey = 'waist';

  static const parameterKeys = <String>[waistKey];

  static bool hasActive(Map<String, double> parameters) {
    for (final key in parameterKeys) {
      if ((parameters[key] ?? 0).abs() > 1e-6) {
        return true;
      }
    }
    return false;
  }
}
