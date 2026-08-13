import 'dart:convert';
import 'dart:io';

import '../warp/face_warp_render_contract.dart';

/// Logs NDJSON para sessão de debug do agente (face_slim / Face Warp V3).
abstract final class AgentDebugLog {
  static const _path =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/debug-13c8af.log';
  static const _sessionId = '13c8af';

  static void write({
    required String location,
    required String message,
    required Map<String, dynamic> data,
    required String hypothesisId,
    String runId = 'pre-fix',
    String phase = '0',
  }) {
    // #region agent log
    try {
      final payload = jsonEncode({
        'sessionId': _sessionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'phase': phase,
        'location': location,
        'message': message,
        'data': data,
        'hypothesisId': hypothesisId,
        'runId': runId,
      });
      File(_path).writeAsStringSync('$payload\n', mode: FileMode.append);
    } catch (_) {}
    // #endregion
  }

  /// Baseline Fase 0 — telemetria de campo (pré-remap) + backend selecionado.
  static void writePhase0Baseline({
    required String location,
    required String backend,
    required String runId,
    required FaceWarpBoundaryMetrics fieldMetrics,
    required int landmarkCount,
    required int meshVertexCount,
    String? fallbackReason,
  }) {
    write(
      location: location,
      message: 'phase0_baseline',
      hypothesisId: 'P0',
      runId: runId,
      phase: '0',
      data: {
        'backend': backend,
        if (fallbackReason != null) 'fallbackReason': fallbackReason,
        'landmarkCount': landmarkCount,
        'meshVertexCount': meshVertexCount,
        ...fieldMetrics.toJson(),
      },
    );
  }

  /// Fase 1 — roteamento V3 vs legacy (sem alterar warp).
  static void writePhase1Routing({
    required String location,
    required String passId,
    required String backend,
    required bool fallbackUsed,
    String? fallbackReason,
    int? landmarkCount,
    int? meshVertexCount,
    String? error,
  }) {
    write(
      location: location,
      message: 'phase1_routing',
      hypothesisId: 'P1',
      runId: passId,
      phase: '1',
      data: {
        'passId': passId,
        'backend': backend,
        'fallbackUsed': fallbackUsed,
        if (fallbackReason != null) 'fallbackReason': fallbackReason,
        if (landmarkCount != null) 'landmarkCount': landmarkCount,
        if (meshVertexCount != null) 'meshVertexCount': meshVertexCount,
        if (error != null) 'error': error,
      },
    );
  }

  /// Fase 2 — campo geométrico com Support + coverage pós-remap.
  static void writePhase2Metrics({
    required String location,
    required String runId,
    required FaceWarpBoundaryMetrics metrics,
    required int landmarkCount,
    required int meshVertexCount,
    int? meshHitPx,
  }) {
    write(
      location: location,
      message: 'phase2_metrics',
      hypothesisId: 'P2',
      runId: runId,
      phase: '2',
      data: {
        'landmarkCount': landmarkCount,
        'meshVertexCount': meshVertexCount,
        if (meshHitPx != null) 'meshHitPx': meshHitPx,
        ...metrics.toJson(),
      },
    );
  }
}
