import 'dart:math' as math;

/// Telemetria leve por passe do Body Reshape multi-passe (Sprint 10).
class PassProfileEntry {
  final String passId;
  final int durationUs;
  final Map<String, double> metrics;
  final bool skipped;

  const PassProfileEntry({
    required this.passId,
    required this.durationUs,
    this.metrics = const {},
    this.skipped = false,
  });

  double get durationMs => durationUs / 1000.0;
}

/// Acumula timings e métricas por passe.
class PassProfiler {
  PassProfiler({this.enabled = true});

  final bool enabled;
  final List<PassProfileEntry> _entries = [];
  final Map<String, int> _startsUs = {};

  List<PassProfileEntry> get entries => List.unmodifiable(_entries);

  Map<String, int> get durationsMs {
    final map = <String, int>{};
    for (final entry in _entries) {
      map[entry.passId] = (map[entry.passId] ?? 0) + entry.durationUs ~/ 1000;
    }
    return map;
  }

  void begin(String passId) {
    if (!enabled) {
      return;
    }
    _startsUs[passId] = _nowUs();
  }

  void end(
    String passId, {
    Map<String, double> metrics = const {},
    bool skipped = false,
  }) {
    if (!enabled) {
      return;
    }
    final started = _startsUs.remove(passId);
    final duration = started == null ? 0 : _nowUs() - started;
    _entries.add(
      PassProfileEntry(
        passId: passId,
        durationUs: duration,
        metrics: metrics,
        skipped: skipped,
      ),
    );
  }

  void recordSkipped(String passId, {String reason = 'disabled'}) {
    if (!enabled) {
      return;
    }
    _entries.add(
      PassProfileEntry(
        passId: passId,
        durationUs: 0,
        metrics: {'reason_code': reason.hashCode.toDouble()},
        skipped: true,
      ),
    );
  }

  void reset() {
    _entries.clear();
    _startsUs.clear();
  }

  int get totalDurationUs =>
      _entries.fold<int>(0, (sum, e) => sum + e.durationUs);

  static int _nowUs() => DateTime.now().microsecondsSinceEpoch;
}

/// Configuração de toggles do pipeline multi-passe.
class BodyMultiPassConfig {
  final bool bodyMeshWarp;
  final bool localMls;
  final bool edgeRefinement;
  final bool antiFolding;
  final bool tpsRefinement;
  final bool textureStabilization;
  final bool backgroundCorrection;
  final bool profilePasses;

  const BodyMultiPassConfig({
    this.bodyMeshWarp = false,
    this.localMls = false,
    this.edgeRefinement = false,
    this.antiFolding = false,
    this.tpsRefinement = false,
    this.textureStabilization = false,
    this.backgroundCorrection = false,
    this.profilePasses = true,
  });

  /// Legado: nenhum passe V2 (MLS compose permanece).
  static const legacy = BodyMultiPassConfig();

  /// Preview V2 completo (Sprints 10–11).
  static const previewV2 = BodyMultiPassConfig(
    bodyMeshWarp: true,
    localMls: true,
    edgeRefinement: true,
    antiFolding: true,
    tpsRefinement: true,
    textureStabilization: true,
    backgroundCorrection: true,
  );

  bool get isV2Enabled =>
      bodyMeshWarp ||
      localMls ||
      edgeRefinement ||
      antiFolding ||
      tpsRefinement ||
      textureStabilization ||
      backgroundCorrection;

  int get enabledPassCount =>
      (bodyMeshWarp ? 1 : 0) +
      (localMls ? 1 : 0) +
      (edgeRefinement ? 1 : 0) +
      (antiFolding ? 1 : 0) +
      (tpsRefinement ? 1 : 0) +
      (textureStabilization ? 1 : 0) +
      (backgroundCorrection ? 1 : 0);

  BodyMultiPassConfig copyWith({
    bool? bodyMeshWarp,
    bool? localMls,
    bool? edgeRefinement,
    bool? antiFolding,
    bool? tpsRefinement,
    bool? textureStabilization,
    bool? backgroundCorrection,
    bool? profilePasses,
  }) {
    return BodyMultiPassConfig(
      bodyMeshWarp: bodyMeshWarp ?? this.bodyMeshWarp,
      localMls: localMls ?? this.localMls,
      edgeRefinement: edgeRefinement ?? this.edgeRefinement,
      antiFolding: antiFolding ?? this.antiFolding,
      tpsRefinement: tpsRefinement ?? this.tpsRefinement,
      textureStabilization: textureStabilization ?? this.textureStabilization,
      backgroundCorrection: backgroundCorrection ?? this.backgroundCorrection,
      profilePasses: profilePasses ?? this.profilePasses,
    );
  }

  @override
  String toString() =>
      'BodyMultiPassConfig(mesh=$bodyMeshWarp, mls=$localMls, '
      'edge=$edgeRefinement, antiFold=$antiFolding, tps=$tpsRefinement, '
      'tex=$textureStabilization, bg=$backgroundCorrection)';
}

/// Utilitário de hash espacial 2D (células uniformes).
class SpatialHash2D {
  SpatialHash2D({
    required this.cellSize,
    required this.originX,
    required this.originY,
  }) : assert(cellSize > 0);

  final double cellSize;
  final double originX;
  final double originY;
  final Map<int, List<int>> _buckets = {};

  void insert(int id, double x, double y) {
    final key = _key(x, y);
    (_buckets[key] ??= <int>[]).add(id);
  }

  /// IDs em células cuja vizinhança cobre o raio [radius].
  List<int> query(double x, double y, double radius) {
    final result = <int>[];
    final seen = <int>{};
    final cells = math.max(1, (radius / cellSize).ceil());
    final cx = ((x - originX) / cellSize).floor();
    final cy = ((y - originY) / cellSize).floor();
    for (var dy = -cells; dy <= cells; dy++) {
      for (var dx = -cells; dx <= cells; dx++) {
        final bucket = _buckets[pack(cx + dx, cy + dy)];
        if (bucket == null) {
          continue;
        }
        for (final id in bucket) {
          if (seen.add(id)) {
            result.add(id);
          }
        }
      }
    }
    return result;
  }

  int get bucketCount => _buckets.length;

  int get totalInserted {
    var n = 0;
    for (final bucket in _buckets.values) {
      n += bucket.length;
    }
    return n;
  }

  int _key(double x, double y) {
    final cx = ((x - originX) / cellSize).floor();
    final cy = ((y - originY) / cellSize).floor();
    return pack(cx, cy);
  }

  static int pack(int cx, int cy) => (cx << 16) ^ (cy & 0xffff);
}
