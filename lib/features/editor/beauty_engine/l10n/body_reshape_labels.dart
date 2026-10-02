import '../body_reshape/models/body_adjustment.dart';
import '../body_reshape/models/legacy_body_parameter_adapter.dart';
import '../body_reshape/models/warp_plan.dart';

/// Labels e mensagens do Body Reshape V2.
///
/// Menu zerado (2026-10-01). Sem sliders até existirem Fields novos.
abstract final class BodyReshapeLabels {
  static const parameterLabelPt = <String, String>{};

  static String parameterLabel(String key) => parameterLabelPt[key] ?? key;

  static const emptyToolsHint = 'Sem ferramentas ainda.';
  static const backgroundLock = 'Travar fundo';
  static const backgroundLockPaywallTitle = 'Travar fundo';
  static const backgroundLockPaywallBody =
      'Disponível nos planos pagos. O fundo fica parado enquanto o corpo é '
      'ajustado, sem portas ou linhas tortas.';
  static const backgroundLockPaywallAction = 'Ver planos';
  static const proToolPaywallBody =
      'Ferramenta dos planos pagos. Assine para ajustar com ela.';
  static const legsNotRecognized =
      'Falha ao reconhecer as linhas das pernas, não foi possível ajustar.';
  static const armsNotRecognized =
      'Falha ao reconhecer as linhas dos braços, não foi possível ajustar.';
  static const chestNotRecognized =
      'Falha ao reconhecer o busto, não foi possível ajustar.';
  static const shouldersNotRecognized =
      'Falha ao reconhecer os ombros, não foi possível ajustar.';
  static const limitedByOcclusion = 'Ajuste limitado por oclusão';
  static const limitedByConfidence = 'Ajuste limitado por confiança baixa';
  static const limitedByCapability = 'Ajuste limitado — evidência insuficiente';
  static const rejectedByOcclusion = 'Ajuste bloqueado por oclusão';

  static String? limitationHint({
    required String parameterKey,
    WarpPlan? plan,
  }) {
    if (plan == null || parameterKey.isEmpty) {
      return null;
    }

    for (final decision in plan.occlusionDecisions) {
      if (decision.parameter != parameterKey) {
        continue;
      }
      if (decision.wasRejected) {
        return rejectedByOcclusion;
      }
      if (decision.wasReduced) {
        return limitedByOcclusion;
      }
    }

    for (final decision in plan.capabilityDecisions) {
      if (decision.parameter != parameterKey) {
        continue;
      }
      if (decision.wasRejected || decision.wasReduced) {
        return limitedByCapability;
      }
    }

    for (final adjustment in plan.adjustments) {
      if (adjustment.sourceParameter != parameterKey) {
        continue;
      }
      if (adjustment.wasOcclusionLimited) {
        return limitedByOcclusion;
      }
      if (adjustment.weight < 0.999 && adjustment.intensity > 0) {
        return limitedByConfidence;
      }
    }
    return null;
  }

  static String? controlLimitHint(String parameterKey) {
    if (parameterKey.isEmpty) {
      return null;
    }
    final spec = LegacyBodyParameterAdapter.specFor(parameterKey);
    if (spec == null) {
      return null;
    }
    final maxPct = (spec.maxIntensity * 100).round();
    final occlusion = switch (spec.occlusionPolicy) {
      BodyOcclusionPolicy.rejectAdjustment => 'bloqueia se ocluso',
      BodyOcclusionPolicy.reduceIntensity => 'reduz se ocluso',
      BodyOcclusionPolicy.preserveOccluder => 'preserva oclusor',
    };
    return 'Limite $maxPct% · $occlusion';
  }

  static String controlSummary(BodyControlSpec spec) {
    final regions = spec.regions.map((r) => r.name).join(', ');
    return '${parameterLabel(spec.parameter)} · $regions · '
        'max ${(spec.maxIntensity * 100).round()}%';
  }
}
