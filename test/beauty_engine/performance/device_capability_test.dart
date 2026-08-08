import 'package:editaiapp/features/editor/beauty_engine/performance/beauty_benchmark_aggregator.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/beauty_profiler.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/device_capability.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/device_capability_benchmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/device_capability_manager.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/performance_budget_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/thermal_degradation_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/thermal_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceCapabilityBenchmark', () {
    test('tier thresholds are ordered A < B < C', () {
      expect(
        DeviceCapabilityBenchmark.tierFromBenchmarkMs(10),
        DeviceTier.a,
      );
      expect(
        DeviceCapabilityBenchmark.tierFromBenchmarkMs(50),
        DeviceTier.b,
      );
      expect(
        DeviceCapabilityBenchmark.tierFromBenchmarkMs(200),
        DeviceTier.c,
      );
    });

    test('microbench completes in reasonable time', () {
      final ms = DeviceCapabilityBenchmark.runGuidedFilterMicrobench();
      expect(ms, greaterThan(0));
      expect(ms, lessThan(5000));
    });
  });

  group('DeviceCapabilityProfile', () {
    test('tier A has highest preview resolution', () {
      final a = DeviceCapabilityProfile.forTier(DeviceTier.a);
      final c = DeviceCapabilityProfile.forTier(DeviceTier.c);
      expect(a.previewMaxEdge, greaterThan(c.previewMaxEdge));
      expect(a.sliderToFrameBudgetMs, lessThan(c.sliderToFrameBudgetMs));
    });
  });

  group('DeviceCapabilityManager', () {
    test('overrideForTests bypasses persistence', () async {
      final manager = DeviceCapabilityManager();
      manager.overrideForTests(DeviceCapabilityProfile.forTier(DeviceTier.b));
      final profile = await manager.resolve();
      expect(profile.tier, DeviceTier.b);
    });
  });

  group('ThermalDegradationPolicy', () {
    test('critical thermal shrinks tiles', () {
      final base = DeviceCapabilityProfile.forTier(DeviceTier.a);
      final plan = ThermalDegradationPolicy.plan(
        profile: base,
        thermal: ThermalState.critical,
      );
      expect(plan.tileSizePx, lessThanOrEqualTo(512));
      expect(plan.jpegQualityReduction, greaterThan(0));
    });

    test('nominal thermal keeps profile tile size', () {
      final base = DeviceCapabilityProfile.forTier(DeviceTier.a);
      final plan = ThermalDegradationPolicy.plan(
        profile: base,
        thermal: ThermalState.nominal,
      );
      expect(plan.tileSizePx, base.exportTileSizePx);
    });
  });

  group('PerformanceBudgetPolicy', () {
    test('within budget when p95 under tier limit', () {
      final agg = BeautyBenchmarkAggregator();
      for (var i = 0; i < 10; i++) {
        final profiler = BeautyProfiler();
        profiler.beginFrame();
        profiler.start('process_total');
        profiler.end('process_total');
        agg.record(profiler.snapshot());
      }
      // Samples are ~0ms in unit test — treated as within budget.
      expect(
        PerformanceBudgetPolicy.isWithinBudget(agg, DeviceTier.a),
        isTrue,
      );
    });

    test('p95 limit scales by tier', () {
      expect(
        PerformanceBudgetPolicy.sliderToFrameP95Limit(DeviceTier.a),
        33,
      );
      expect(
        PerformanceBudgetPolicy.sliderToFrameP95Limit(DeviceTier.b),
        66,
      );
    });
  });
}
