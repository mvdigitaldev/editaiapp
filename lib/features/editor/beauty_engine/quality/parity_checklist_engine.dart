import '../filters/face/face_filter_pipeline.dart';
import 'face_quality_context.dart';
import '../warp/anatomy/face_warp_debug_stats.dart';
import 'parity_auto_evaluator.dart';

/// Status de um item da matriz A/B Banuba (Sprint 38).
enum ParityChecklistStatus {
  idle,
  active,
  warn,
  pass,
}

class ParityChecklistItem {
  const ParityChecklistItem({
    required this.id,
    required this.label,
    required this.status,
    this.hint,
  });

  final String id;
  final String label;
  final ParityChecklistStatus status;
  final String? hint;
}

/// Avaliação heurística da matriz warp B3–B6 para o lab.
abstract final class ParityChecklistEngine {
  static const _warpGroups = [
    (
      id: 'B3',
      label: 'Mandíbula (jaw)',
      key: 'jaw',
      minVertices: 4,
    ),
    (
      id: 'B4',
      label: 'Queixo (chin)',
      key: 'chin',
      minVertices: 3,
    ),
    (
      id: 'B5',
      label: 'Olhos (eye_scale)',
      key: 'eye_scale',
      minVertices: 6,
    ),
    (
      id: 'B6',
      label: 'Lábios (lip_thickness)',
      key: 'lip_thickness',
      minVertices: 4,
    ),
  ];

  static List<ParityChecklistItem> evaluateWarp({
    required Map<String, double> params,
    FaceQualityContext? quality,
    FaceWarpDebugStats? warpStats,
    String? warpBackend,
    bool includeGoldenAuto = true,
  }) {
    final goldenByKey = includeGoldenAuto && warpStats != null
        ? ParityAutoEvaluator.evaluateAll(params: params, stats: warpStats)
        : const <String, ParityGoldenResult>{};

    final items = <ParityChecklistItem>[];
    for (final group in _warpGroups) {
      final value = params[group.key] ?? 0;
      if (value <= 1e-6) {
        items.add(
          ParityChecklistItem(
            id: group.id,
            label: group.label,
            status: ParityChecklistStatus.idle,
          ),
        );
        continue;
      }

      final golden = goldenByKey[group.key];
      final hint = _hintFor(
        groupId: group.id,
        quality: quality,
        warpBackend: warpBackend,
      );
      final moved = warpStats?.movedVertices ?? 0;
      if (moved < group.minVertices) {
        items.add(
          ParityChecklistItem(
            id: group.id,
            label: group.label,
            status: ParityChecklistStatus.warn,
            hint: hint ?? 'Poucos vértices movidos ($moved)',
          ),
        );
        continue;
      }

      if (hint != null) {
        items.add(
          ParityChecklistItem(
            id: group.id,
            label: group.label,
            status: ParityChecklistStatus.warn,
            hint: hint,
          ),
        );
        continue;
      }

      if (golden != null && golden.verdict == ParityGoldenVerdict.fail) {
        items.add(
          ParityChecklistItem(
            id: group.id,
            label: group.label,
            status: ParityChecklistStatus.warn,
            hint: golden.detail,
          ),
        );
        continue;
      }

      final goldenHint = golden?.detail;
      final backendHint =
          warpBackend != null ? 'backend: $warpBackend' : null;
      items.add(
        ParityChecklistItem(
          id: group.id,
          label: group.label,
          status: ParityChecklistStatus.pass,
          hint: goldenHint ?? backendHint,
        ),
      );
    }

    final activeCount = FaceFilterPipeline.faceWarpParameterKeys
        .where((k) => (params[k] ?? 0) > 1e-6)
        .length;
    if (activeCount > 0 && (warpStats?.vertexMaxPx ?? 0) <= 0.05) {
      items.add(
        const ParityChecklistItem(
          id: 'V3',
          label: 'Motor V3',
          status: ParityChecklistStatus.warn,
          hint: 'Warp ativo mas Δv máximo ≈ 0',
        ),
      );
    }

    return items;
  }

  static String? _hintFor({
    required String groupId,
    FaceQualityContext? quality,
    String? warpBackend,
  }) {
    final metrics = quality?.metrics;
    if (quality != null && (metrics == null || !metrics.hasFace)) {
      return 'Sem face detectada';
    }
    if (metrics == null) {
      return null;
    }

    if (metrics.faceShortEdgePx < 200) {
      return 'Rosto pequeno (<200px)';
    }

    if (metrics.yawAsymmetry > 0.35 && (groupId == 'B5' || groupId == 'B3')) {
      return 'Yaw alto — revisar paridade visual';
    }

    if (metrics.occlusionRatio > 0.25) {
      return 'Oclusão parcial';
    }

    if (warpBackend == 'mls') {
      return 'MLS legado — preferir v3_gpu';
    }

    return null;
  }
}
