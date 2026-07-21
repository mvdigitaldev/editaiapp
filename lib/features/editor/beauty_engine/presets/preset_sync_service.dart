import '../models/beauty_preset.dart';
import 'beauty_preset_remote_record.dart';

/// Resultado de merge last-write-wins (Sprint 23).
class PresetSyncMergeResult {
  const PresetSyncMergeResult({
    required this.mergedLocal,
    required this.pushedClientIds,
    required this.pulledClientIds,
  });

  final List<BeautyPreset> mergedLocal;
  final Set<String> pushedClientIds;
  final Set<String> pulledClientIds;
}

/// Merge local/remoto com last-write-wins por `updatedAt`.
class PresetSyncService {
  const PresetSyncService();

  PresetSyncMergeResult merge({
    required List<BeautyPreset> localPresets,
    required List<BeautyPresetRemoteRecord> remoteRecords,
  }) {
    final localByClientId = {
      for (final preset in localPresets) preset.id: preset,
    };
    final remoteByClientId = {
      for (final record in remoteRecords) record.clientId: record,
    };

    final merged = <BeautyPreset>[];
    final pushed = <String>{};
    final pulled = <String>{};
    final allClientIds = {
      ...localByClientId.keys,
      ...remoteByClientId.keys,
    };

    for (final clientId in allClientIds) {
      final local = localByClientId[clientId];
      final remote = remoteByClientId[clientId];

      if (local == null && remote != null) {
        merged.add(_presetFromRemote(remote));
        pulled.add(clientId);
        continue;
      }

      if (local != null && remote == null) {
        merged.add(local);
        pushed.add(clientId);
        continue;
      }

      if (local != null && remote != null) {
        final localUpdated = _effectiveUpdatedAt(local);
        final remoteUpdated = remote.updatedAt;

        if (remoteUpdated.isAfter(localUpdated)) {
          merged.add(_presetFromRemote(remote));
          pulled.add(clientId);
        } else if (localUpdated.isAfter(remoteUpdated)) {
          merged.add(local);
          pushed.add(clientId);
        } else {
          merged.add(
            local.copyWith(
              remoteId: remote.id,
              authorId: remote.userId,
              isPublic: remote.isPublic,
            ),
          );
        }
      }
    }

    merged.sort(
      (a, b) => _effectiveUpdatedAt(b).compareTo(_effectiveUpdatedAt(a)),
    );

    return PresetSyncMergeResult(
      mergedLocal: merged,
      pushedClientIds: pushed,
      pulledClientIds: pulled,
    );
  }

  DateTime _effectiveUpdatedAt(BeautyPreset preset) {
    return preset.updatedAt ??
        preset.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  BeautyPreset _presetFromRemote(BeautyPresetRemoteRecord remote) {
    return remote.preset.copyWith(
      id: remote.clientId,
      name: remote.name,
      remoteId: remote.id,
      authorId: remote.userId,
      isPublic: remote.isPublic,
      createdAt: remote.createdAt,
      updatedAt: remote.updatedAt,
      clearThumbnailPath: true,
    );
  }
}
