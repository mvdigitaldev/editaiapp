import 'package:editaiapp/features/editor/beauty_engine/performance/beauty_benchmark_aggregator.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/beauty_profiler.dart';
import 'package:flutter_test/flutter_test.dart';

BeautyProfileSnapshot _snapshot(Map<String, int> spans, int total) {
  return BeautyProfileSnapshot(spansMs: spans, totalMs: total);
}

void main() {
  group('BeautyBenchmarkAggregator', () {
    test('agrega p50/p95 por estágio', () {
      final aggregator = BeautyBenchmarkAggregator();
      for (var i = 1; i <= 100; i++) {
        aggregator.record(_snapshot({'warp': i, 'skin': i * 2}, i * 3));
      }

      expect(aggregator.sampleCount, 100);
      expect(aggregator.percentile('warp', 50), closeTo(50, 2));
      expect(aggregator.percentile('warp', 95), closeTo(95, 2));
      expect(aggregator.percentile('skin', 95), closeTo(190, 4));
      expect(aggregator.percentile('total', 50), closeTo(150, 6));
    });

    test('ignora estágios com 0ms e estágio desconhecido retorna 0', () {
      final aggregator = BeautyBenchmarkAggregator();
      aggregator.record(_snapshot({'warp': 0, 'skin': 10}, 10));

      expect(aggregator.percentile('warp', 50), 0);
      expect(aggregator.percentile('skin', 50), 10);
      expect(aggregator.percentile('inexistente', 95), 0);
    });

    test('janela FIFO limita memória em sessão longa', () {
      final aggregator = BeautyBenchmarkAggregator(maxSamplesPerStage: 10);
      // 90 amostras lentas antigas seguidas de 10 rápidas recentes.
      for (var i = 0; i < 90; i++) {
        aggregator.record(_snapshot({'warp': 1000}, 1000));
      }
      for (var i = 0; i < 10; i++) {
        aggregator.record(_snapshot({'warp': 5}, 5));
      }

      // Só a janela recente conta.
      expect(aggregator.percentile('warp', 95), 5);
      final stages = aggregator.summary()['stages'] as Map<String, dynamic>;
      expect((stages['warp'] as Map<String, dynamic>)['count'], 10);
    });

    test('summary estruturado e reset', () {
      final aggregator = BeautyBenchmarkAggregator();
      aggregator.record(_snapshot({'warp': 12}, 20));

      final summary = aggregator.summary();
      expect(summary['samples'], 1);
      final stages = summary['stages'] as Map<String, dynamic>;
      expect((stages['warp'] as Map<String, dynamic>)['p50'], 12);
      expect((stages['total'] as Map<String, dynamic>)['max'], 20);

      aggregator.reset();
      expect(aggregator.sampleCount, 0);
      expect(aggregator.percentile('warp', 50), 0);
    });
  });
}
