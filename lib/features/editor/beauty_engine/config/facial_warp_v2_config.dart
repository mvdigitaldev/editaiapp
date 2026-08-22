/// Flag do Device Lab V2. Não é rollout de produto. Não troca o preview V1.
abstract final class FacialWarpV2Config {
  FacialWarpV2Config._();

  /// Liga só o dump paralelo de laboratório (`v2Raw`). Default false.
  ///
  /// Pode inicializar com `--dart-define=FACIAL_WARP_V2_LAB=true`.
  static bool facialWarpCoreV2Lab =
      const bool.fromEnvironment('FACIAL_WARP_V2_LAB', defaultValue: false);

  static void resetForTest() {
    facialWarpCoreV2Lab = false;
  }
}
