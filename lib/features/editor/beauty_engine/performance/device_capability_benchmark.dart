import 'dart:typed_data';

import '../filters/face/skin/guided_filter.dart';
import 'device_capability.dart';

/// Micro-benchmark CPU (~100 ms alvo) na 1ª execução do editor.
///
/// Usa guided filter em buffer 512×512 como proxy de custo de pele + CPU
/// (independente de GPU nativa). Thresholds calibrados para VM/desktop lento
/// cair em tier C sem bloquear testes.
abstract final class DeviceCapabilityBenchmark {
  static const benchmarkWidth = 512;
  static const benchmarkHeight = 512;
  static const tierAThresholdMs = 35;
  static const tierBThresholdMs = 120;

  /// Executa uma passagem de guided filter e retorna duração em ms.
  static int runGuidedFilterMicrobench() {
    final pixelCount = benchmarkWidth * benchmarkHeight;
    final src = Float32List(pixelCount);
    for (var i = 0; i < pixelCount; i++) {
      src[i] = (i % 256) / 255.0;
    }

    final stopwatch = Stopwatch()..start();
    GuidedFilter.filterSelf(
      src,
      width: benchmarkWidth,
      height: benchmarkHeight,
      radius: 8,
      eps: 1e-4,
    );
    stopwatch.stop();
    return stopwatch.elapsedMilliseconds;
  }

  static DeviceTier tierFromBenchmarkMs(int ms) {
    if (ms <= tierAThresholdMs) {
      return DeviceTier.a;
    }
    if (ms <= tierBThresholdMs) {
      return DeviceTier.b;
    }
    return DeviceTier.c;
  }

  static DeviceCapabilityProfile profileFromBenchmarkMs(int ms) {
    final tier = tierFromBenchmarkMs(ms);
    return DeviceCapabilityProfile.forTier(tier, benchmarkMs: ms);
  }
}
