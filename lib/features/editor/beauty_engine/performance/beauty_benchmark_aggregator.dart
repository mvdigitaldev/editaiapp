import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'beauty_profiler.dart';

/// Agrega snapshots do [BeautyProfiler] ao longo da sessão e expõe p50/p95
/// por estágio (Sprint 0 do SDK facial — cap. 10 do plano).
///
/// Objetivo: medir o "antes" de cada sprint da migração (pele CPU→GPU, color
/// engine, FFI) com dados reais, em vez de comparar sensações. O log é uma
/// linha JSON por flush, fácil de filtrar no logcat/console:
/// `beauty_benchmark {"samples":42,"stages":{"process_total":{"p50":180,...}}}`
class BeautyBenchmarkAggregator {
  BeautyBenchmarkAggregator({this.maxSamplesPerStage = 512});

  final int maxSamplesPerStage;
  final Map<String, List<int>> _samplesMs = {};
  int _recorded = 0;

  int get sampleCount => _recorded;

  /// Registra um snapshot de frame/export. Estágios com 0ms são ignorados
  /// (label não rodou naquele frame).
  void record(BeautyProfileSnapshot snapshot) {
    _recorded++;
    for (final entry in snapshot.spansMs.entries) {
      if (entry.value <= 0) continue;
      _add(entry.key, entry.value);
    }
    if (snapshot.totalMs > 0) {
      _add('total', snapshot.totalMs);
    }
  }

  void _add(String stage, int ms) {
    final samples = _samplesMs.putIfAbsent(stage, () => <int>[]);
    samples.add(ms);
    // FIFO: mantém a janela recente para não crescer sem limite em sessão longa.
    if (samples.length > maxSamplesPerStage) {
      samples.removeAt(0);
    }
  }

  /// Percentil (0–100) por interpolação de vizinho mais próximo.
  int percentile(String stage, int p) {
    final samples = _samplesMs[stage];
    if (samples == null || samples.isEmpty) return 0;
    final sorted = List<int>.of(samples)..sort();
    final rank = ((p / 100) * (sorted.length - 1)).round();
    return sorted[rank.clamp(0, sorted.length - 1)];
  }

  /// Resumo estruturado: por estágio, {count, p50, p95, max}.
  Map<String, dynamic> summary() {
    final stages = <String, dynamic>{};
    for (final entry in _samplesMs.entries) {
      final sorted = List<int>.of(entry.value)..sort();
      stages[entry.key] = {
        'count': sorted.length,
        'p50': percentile(entry.key, 50),
        'p95': percentile(entry.key, 95),
        'max': sorted.last,
      };
    }
    return {'samples': _recorded, 'stages': stages};
  }

  /// Loga o resumo como linha única JSON (apenas em debug/profile builds).
  void logSummary({String tag = 'beauty_benchmark'}) {
    if (kReleaseMode) return;
    debugPrint('$tag ${jsonEncode(summary())}');
  }

  void reset() {
    _samplesMs.clear();
    _recorded = 0;
  }
}
