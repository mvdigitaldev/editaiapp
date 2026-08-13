/// Contrato numérico congelado da Phase 9 (Fase 15).
///
/// Pequenas diferenças de floating point próximas de [phase9Epsilon]
/// **não** representam violação estrutural — use [minimumAcceptedJacobian]
/// para comparações de PASS/FAIL.
abstract final class FaceWarpNumericContract {
  FaceWarpNumericContract._();

  /// Limiar estrutural aprovado na Phase 9 / Phase 14.
  static const double phase9Epsilon = 0.10;

  /// Tolerância para comparação de Jacobian vs epsilon (Phase 14).
  static const double numericTolerance = 1e-6;

  /// Mínimo Jacobian aceito: `epsilon - numericTolerance`.
  static const double minimumAcceptedJacobian =
      phase9Epsilon - numericTolerance;

  /// Verifica se Jacobian de malha é estruturalmente aceito.
  static bool isJacobianAccepted(double jacobian) =>
      jacobian >= minimumAcceptedJacobian - 1e-12;

  /// Verifica se contagem de violações estruturais é zero (com tolerância).
  static bool hasNoStructuralViolations(int violationCount) =>
      violationCount <= 0;
}
