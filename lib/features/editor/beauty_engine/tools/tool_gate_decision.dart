/// Ação de gating por ferramenta (cap. 12 / cap. 19).
enum ToolGateAction {
  allowed,
  reduced,
  disabled,
  warn,
}

/// Decisão de gating para um parâmetro/slider.
class ToolGateDecision {
  const ToolGateDecision({
    required this.parameterKey,
    this.action = ToolGateAction.allowed,
    this.intensityScale = 1,
    this.maxEffective = 1,
    this.hintKey,
  });

  final String parameterKey;
  final ToolGateAction action;
  final double intensityScale;
  final double maxEffective;
  final String? hintKey;

  bool get isDisabled => action == ToolGateAction.disabled;
  bool get isReduced =>
      action == ToolGateAction.reduced || intensityScale < 0.999;
  bool get hasWarning =>
      action == ToolGateAction.warn || hintKey != null && !isDisabled;

  double applySliderValue(double raw) {
    if (isDisabled || raw <= 0) return 0;
    final scaled = raw * intensityScale.clamp(0, 1);
    return scaled.clamp(0, maxEffective.clamp(0, 1));
  }
}

/// Plano de gating para todos os parâmetros de uma foto.
class ToolGatePlan {
  const ToolGatePlan({this.decisions = const {}});

  final Map<String, ToolGateDecision> decisions;

  static const empty = ToolGatePlan();

  ToolGateDecision decisionFor(String key) =>
      decisions[key] ?? ToolGateDecision(parameterKey: key);

  bool isEnabled(String key) => !decisionFor(key).isDisabled;

  String? hintFor(String key) => decisionFor(key).hintKey;

  Map<String, double> applyToParameters(Map<String, double> raw) {
    final out = <String, double>{};
    for (final entry in raw.entries) {
      out[entry.key] = decisionFor(entry.key).applySliderValue(entry.value);
    }
    return out;
  }
}
