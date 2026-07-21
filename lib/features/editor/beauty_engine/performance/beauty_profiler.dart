/// Snapshot de timings por passo do pipeline (Sprint 25).
class BeautyProfileSnapshot {
  const BeautyProfileSnapshot({
    required this.spansMs,
    required this.totalMs,
  });

  final Map<String, int> spansMs;
  final int totalMs;

  int operator [](String key) => spansMs[key] ?? 0;
}

/// Profiler leve para medir passes do Beauty Engine.
class BeautyProfiler {
  BeautyProfiler({this.enabled = true});

  final bool enabled;
  final Map<String, int> _startsUs = {};
  final Map<String, int> _spansMs = {};
  int? _totalStartUs;

  void beginFrame() {
    if (!enabled) {
      return;
    }
    _startsUs.clear();
    _spansMs.clear();
    _totalStartUs = _nowUs();
  }

  void start(String label) {
    if (!enabled) {
      return;
    }
    _startsUs[label] = _nowUs();
  }

  void end(String label) {
    if (!enabled) {
      return;
    }
    final started = _startsUs.remove(label);
    if (started == null) {
      return;
    }
    final elapsedMs = ((_nowUs() - started) / 1000).round();
    _spansMs[label] = (_spansMs[label] ?? 0) + elapsedMs;
  }

  BeautyProfileSnapshot snapshot() {
    final totalStart = _totalStartUs;
    final totalMs = totalStart == null
        ? _spansMs.values.fold<int>(0, (sum, value) => sum + value)
        : ((_nowUs() - totalStart) / 1000).round();

    return BeautyProfileSnapshot(
      spansMs: Map<String, int>.unmodifiable(_spansMs),
      totalMs: totalMs,
    );
  }

  int _nowUs() => DateTime.now().microsecondsSinceEpoch;
}
