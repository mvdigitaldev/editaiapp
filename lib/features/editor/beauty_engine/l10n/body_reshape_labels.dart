import '../body_reshape/models/body_adjustment.dart';
import '../body_reshape/models/legacy_body_parameter_adapter.dart';
import '../body_reshape/models/warp_plan.dart';

/// Labels e mensagens do Body Reshape V2 (Sprint 12).
abstract final class BodyReshapeLabels {
  static const parameterLabelPt = <String, String>{
    'waist_slim': 'Afinar cintura',
    'hip': 'Quadril',
    'body_slim': 'Afinar corpo',
    'leg_length': 'Alongar pernas',
    'leg_slim': 'Afinar pernas',
    'arm_slim': 'Afinar braços',
    'neck_slim': 'Afinar pescoço',
    'shoulder_width': 'Alargar ombros',
    'chest_expand': 'Expandir peito',
    'belly_reduce': 'Reduzir barriga',
    'butt_expand': 'Expandir glúteo',
    'height': 'Altura',
    'shoulder_reduce': 'Estreitar ombros',
    'arm_upper_slim': 'Afinar braço (superior)',
    'arm_forearm_slim': 'Afinar antebraço',
    'leg_thigh_slim': 'Afinar coxa',
    'leg_calf_slim': 'Afinar panturrilha',
  };

  static String parameterLabel(String key) => parameterLabelPt[key] ?? key;

  static const limitedByOcclusion = 'Ajuste limitado por oclusão';
  static const limitedByConfidence = 'Ajuste limitado por confiança baixa';
  static const limitedByCapability = 'Ajuste limitado — evidência insuficiente';
  static const rejectedByOcclusion = 'Ajuste bloqueado por oclusão';

  /// Mensagem curta para exibir sob o slider quando o plano V2 limitou o param.
  static String? limitationHint({
    required String parameterKey,
    WarpPlan? plan,
  }) {
    if (plan == null) {
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

  /// Limite semântico do controle (região / max / oclusão).
  static String? controlLimitHint(String parameterKey) {
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
