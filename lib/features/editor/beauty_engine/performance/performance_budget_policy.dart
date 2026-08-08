import 'beauty_benchmark_aggregator.dart';
import 'device_capability.dart';

/// Limites p95 slider→frame por tier (cap. 18).
abstract final class PerformanceBudgetPolicy {
  static const previewStageKeys = [
    'process_total',
    'total',
    'render_texture',
  ];

  static int sliderToFrameP95Limit(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.a:
        return 33;
      case DeviceTier.b:
        return 66;
      case DeviceTier.c:
        return 120;
    }
  }

  /// True se o p95 do estágio principal está dentro do orçamento do tier.
  static bool isWithinBudget(
    BeautyBenchmarkAggregator aggregator,
    DeviceTier tier, {
    int minSamples = 5,
  }) {
    if (aggregator.sampleCount < minSamples) {
      return true;
    }
    final limit = sliderToFrameP95Limit(tier);
    for (final stage in previewStageKeys) {
      final p95 = aggregator.percentile(stage, 95);
      if (p95 <= 0) {
        continue;
      }
      return p95 <= limit;
    }
    return true;
  }

  /// p95 usado para badge/debug — primeiro estágio com amostras.
  static int previewP95Ms(BeautyBenchmarkAggregator aggregator) {
    for (final stage in previewStageKeys) {
      final p95 = aggregator.percentile(stage, 95);
      if (p95 > 0) {
        return p95;
      }
    }
    return 0;
  }
}
