import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import '../../../../core/storage/local_storage.dart';
import '../../../gallery/presentation/providers/gallery_provider.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';

class ActiveEditSnapshot {
  const ActiveEditSnapshot({
    required this.editId,
    required this.status,
    required this.operationType,
    required this.createdAt,
  });

  final String editId;
  final String status;
  final String operationType;
  final DateTime createdAt;

  bool get isTerminal => status == 'completed' || status == 'failed';

  ActiveEditSnapshot copyWith({
    String? status,
    String? operationType,
    DateTime? createdAt,
  }) {
    return ActiveEditSnapshot(
      editId: editId,
      status: status ?? this.status,
      operationType: operationType ?? this.operationType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'edit_id': editId,
      'status': status,
      'operation_type': operationType,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory ActiveEditSnapshot.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)?.toUtc()
        : null;
    return ActiveEditSnapshot(
      editId: json['edit_id'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      operationType: json['operation_type'] as String? ?? 'unknown',
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
  }

  bool sameAs(ActiveEditSnapshot other) {
    return editId == other.editId &&
        status == other.status &&
        operationType == other.operationType &&
        createdAt.isAtSameMomentAs(other.createdAt);
  }
}

final activeEditsProvider = StateNotifierProvider<ActiveEditsNotifier,
    Map<String, ActiveEditSnapshot>>((ref) {
  final notifier = ActiveEditsNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

class ActiveEditsNotifier extends StateNotifier<Map<String, ActiveEditSnapshot>> {
  ActiveEditsNotifier(this._ref) : super(const <String, ActiveEditSnapshot>{});

  static const _freshPollThreshold = Duration(minutes: 2);
  static const _fastPollInterval = Duration(seconds: 5);
  static const _slowPollInterval = Duration(seconds: 15);
  static const _storageKeyPrefix = 'active_edit_jobs_v1';

  final Ref _ref;
  final LocalStorage _storage = LocalStorage();

  Timer? _pollTimer;
  bool _isForeground = true;
  String? _currentUserId;
  bool _isHydrated = false;
  bool _syncInFlight = false;

  @override
  void dispose() {
    _cancelPolling();
    super.dispose();
  }

  Future<void> handleAuthChanged(String? userId) async {
    final normalizedUserId =
        userId != null && userId.isNotEmpty ? userId : null;

    if (normalizedUserId == null) {
      _currentUserId = null;
      _isHydrated = false;
      _cancelPolling();
      if (state.isNotEmpty) {
        state = const <String, ActiveEditSnapshot>{};
      }
      return;
    }

    if (_currentUserId == normalizedUserId && _isHydrated) {
      _scheduleNextPoll(immediate: true);
      return;
    }

    _currentUserId = normalizedUserId;
    _isHydrated = true;
    await _loadPersistedState();
    await syncNow();
  }

  Future<void> trackEdit({
    required String editId,
    required String operationType,
    String status = 'queued',
    DateTime? createdAt,
  }) async {
    if (editId.isEmpty) return;
    final currentUserId =
        _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return;

    if (_currentUserId != currentUserId || !_isHydrated) {
      await handleAuthChanged(currentUserId);
    }

    final next = Map<String, ActiveEditSnapshot>.from(state);
    if (status == 'completed' || status == 'failed') {
      if (next.remove(editId) != null) {
        state = next;
        await _persistState();
      }
      _ref.invalidate(recentEditsProvider);
      _ref.invalidate(creditsUsageProvider);
      _ref.invalidate(planLimitsProvider);
      return;
    }

    final snapshot = ActiveEditSnapshot(
      editId: editId,
      status: status,
      operationType: operationType,
      createdAt: createdAt?.toUtc() ?? DateTime.now().toUtc(),
    );
    final previous = next[editId];
    if (previous != null && previous.sameAs(snapshot)) {
      _scheduleNextPoll(immediate: true);
      return;
    }

    next[editId] = snapshot;
    state = next;
    await _persistState();
    _ref.invalidate(recentEditsProvider);
    _scheduleNextPoll(immediate: true);
  }

  void setForeground(bool isForeground) {
    _isForeground = isForeground;
    if (!isForeground) {
      _cancelPolling();
      return;
    }
    _scheduleNextPoll(immediate: state.isNotEmpty);
  }

  Future<void> syncNow() async {
    if (_syncInFlight || !_isForeground || state.isEmpty) {
      if (state.isEmpty) {
        _cancelPolling();
      }
      return;
    }

    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    _syncInFlight = true;
    try {
      final ids = state.keys.toList(growable: false);
      dynamic query = Supabase.instance.client
          .from('edits')
          .select('id, status, operation_type, created_at');

      if (ids.length == 1) {
        query = query.eq('id', ids.first);
      } else {
        final filter = ids.map((id) => 'id.eq.$id').join(',');
        query = query.or(filter);
      }

      final response = await query;
      final rows = (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

      final next = Map<String, ActiveEditSnapshot>.from(state);
      var stateChanged = false;
      var timelineChanged = false;
      var terminalChange = false;

      for (final row in rows) {
        final editId = row['id'] as String?;
        if (editId == null || editId.isEmpty) continue;

        final previous = next[editId];
        if (previous == null) continue;

        final status = row['status'] as String? ?? previous.status;
        if (status == 'completed' || status == 'failed') {
          next.remove(editId);
          stateChanged = true;
          timelineChanged = true;
          terminalChange = true;
          continue;
        }

        final updated = previous.copyWith(
          status: status,
          operationType:
              row['operation_type'] as String? ?? previous.operationType,
          createdAt: _parseCreatedAt(row['created_at']) ?? previous.createdAt,
        );

        if (!previous.sameAs(updated)) {
          next[editId] = updated;
          stateChanged = true;
          timelineChanged = true;
        }
      }

      if (stateChanged) {
        state = next;
        await _persistState();
      }

      if (timelineChanged) {
        _ref.invalidate(recentEditsProvider);
      }

      if (terminalChange) {
        _ref.invalidate(creditsUsageProvider);
        _ref.invalidate(planLimitsProvider);
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[ActiveEdits] Falha ao sincronizar status: $error\n$stackTrace',
      );
    } finally {
      _syncInFlight = false;
      _scheduleNextPoll();
    }
  }

  Future<void> _loadPersistedState() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    try {
      final raw = await _storage.read(_storageKeyForUser(currentUserId));
      if (raw == null || raw.isEmpty) {
        state = const <String, ActiveEditSnapshot>{};
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        state = const <String, ActiveEditSnapshot>{};
        return;
      }

      final restored = <String, ActiveEditSnapshot>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final snapshot =
            ActiveEditSnapshot.fromJson(Map<String, dynamic>.from(item));
        if (snapshot.editId.isEmpty || snapshot.isTerminal) continue;
        restored[snapshot.editId] = snapshot;
      }
      state = restored;
    } catch (error, stackTrace) {
      debugPrint(
        '[ActiveEdits] Falha ao restaurar estado local: $error\n$stackTrace',
      );
      state = const <String, ActiveEditSnapshot>{};
    }
  }

  Future<void> _persistState() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final storageKey = _storageKeyForUser(currentUserId);
    if (state.isEmpty) {
      await _storage.delete(storageKey);
      return;
    }

    final encoded = jsonEncode(
      state.values
          .map((snapshot) => snapshot.toJson())
          .toList(growable: false),
    );
    await _storage.write(storageKey, encoded);
  }

  void _scheduleNextPoll({bool immediate = false}) {
    _cancelPolling();

    if (!_isForeground || state.isEmpty) return;

    final interval = immediate ? Duration.zero : _nextPollInterval();
    _pollTimer = Timer(interval, () {
      unawaited(syncNow());
    });
  }

  Duration _nextPollInterval() {
    final now = DateTime.now().toUtc();
    final hasFreshJob = state.values.any(
      (snapshot) => now.difference(snapshot.createdAt) < _freshPollThreshold,
    );
    return hasFreshJob ? _fastPollInterval : _slowPollInterval;
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static DateTime? _parseCreatedAt(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static String _storageKeyForUser(String userId) {
    return '${_storageKeyPrefix}_$userId';
  }
}
