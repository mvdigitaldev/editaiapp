import '../warp/anatomy/face_warp_debug_stats.dart';
import 'parity_golden_baseline.dart';

/// Resultado da comparação automática com o corpus golden.
enum ParityGoldenVerdict {
  pass,
  fail,
  skipped,
}

class ParityGoldenResult {
  const ParityGoldenResult({
    required this.toolKey,
    required this.verdict,
    this.detail,
  });

  final String toolKey;
  final ParityGoldenVerdict verdict;
  final String? detail;

  bool get isPass => verdict == ParityGoldenVerdict.pass;
}

/// Avalia stats de warp contra baselines golden (Sprint 39).
abstract final class ParityAutoEvaluator {
  static ParityGoldenResult evaluateTool({
    required String toolKey,
    required double paramValue,
    required FaceWarpDebugStats stats,
  }) {
    if (paramValue <= 1e-6) {
      return ParityGoldenResult(
        toolKey: toolKey,
        verdict: ParityGoldenVerdict.skipped,
      );
    }

    final baseline = ParityGoldenBaseline.forTool(toolKey);
    if (baseline == null) {
      return ParityGoldenResult(
        toolKey: toolKey,
        verdict: ParityGoldenVerdict.skipped,
      );
    }

    if (stats.movedVertices < baseline.minMovedVertices) {
      return ParityGoldenResult(
        toolKey: toolKey,
        verdict: ParityGoldenVerdict.fail,
        detail:
            'golden: vértices ${stats.movedVertices} < ${baseline.minMovedVertices}',
      );
    }

    if (stats.vertexMaxPx < baseline.minVertexMaxPx) {
      return ParityGoldenResult(
        toolKey: toolKey,
        verdict: ParityGoldenVerdict.fail,
        detail:
            'golden: Δv ${stats.vertexMaxPx.toStringAsFixed(2)}px abaixo do mínimo',
      );
    }

    if (stats.vertexMaxPx > baseline.maxVertexMaxPx) {
      return ParityGoldenResult(
        toolKey: toolKey,
        verdict: ParityGoldenVerdict.fail,
        detail:
            'golden: Δv ${stats.vertexMaxPx.toStringAsFixed(1)}px — possível fold',
      );
    }

    return ParityGoldenResult(
      toolKey: toolKey,
      verdict: ParityGoldenVerdict.pass,
      detail: 'golden ✓ Δv=${stats.vertexMaxPx.toStringAsFixed(1)}px',
    );
  }

  static Map<String, ParityGoldenResult> evaluateAll({
    required Map<String, double> params,
    required FaceWarpDebugStats stats,
  }) {
    final out = <String, ParityGoldenResult>{};
    for (final baseline in ParityGoldenBaseline.all) {
      out[baseline.toolKey] = evaluateTool(
        toolKey: baseline.toolKey,
        paramValue: params[baseline.toolKey] ?? 0,
        stats: stats,
      );
    }
    return out;
  }
}
