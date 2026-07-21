import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/beauty_preset_remote_record.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/preset_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sync = PresetSyncService();

  BeautyPreset local({
    required String id,
    DateTime? updatedAt,
    String? remoteId,
  }) {
    return BeautyPreset(
      id: id,
      name: 'Local $id',
      updatedAt: updatedAt,
      remoteId: remoteId,
    );
  }

  BeautyPresetRemoteRecord remote({
    required String clientId,
    required DateTime updatedAt,
    String remoteId = 'remote-1',
  }) {
    return BeautyPresetRemoteRecord(
      id: remoteId,
      userId: 'user-1',
      clientId: clientId,
      name: 'Remote $clientId',
      preset: BeautyPreset(id: clientId, name: 'Remote $clientId'),
      updatedAt: updatedAt,
      createdAt: updatedAt,
    );
  }

  group('PresetSyncService', () {
    test('pulls remote-only presets', () {
      final result = sync.merge(
        localPresets: const [],
        remoteRecords: [
          remote(
            clientId: 'user_a',
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      expect(result.mergedLocal, hasLength(1));
      expect(result.mergedLocal.first.id, 'user_a');
      expect(result.mergedLocal.first.remoteId, 'remote-1');
      expect(result.pulledClientIds, {'user_a'});
      expect(result.pushedClientIds, isEmpty);
    });

    test('marks local-only presets for push', () {
      final result = sync.merge(
        localPresets: [
          local(
            id: 'user_b',
            updatedAt: DateTime.utc(2026, 1, 3),
          ),
        ],
        remoteRecords: const [],
      );

      expect(result.mergedLocal, hasLength(1));
      expect(result.pushedClientIds, {'user_b'});
      expect(result.pulledClientIds, isEmpty);
    });

    test('last-write-wins prefers newer remote', () {
      final result = sync.merge(
        localPresets: [
          local(
            id: 'user_c',
            updatedAt: DateTime.utc(2026, 1, 1),
            remoteId: 'remote-c',
          ),
        ],
        remoteRecords: [
          remote(
            clientId: 'user_c',
            remoteId: 'remote-c',
            updatedAt: DateTime.utc(2026, 1, 5),
          ),
        ],
      );

      expect(result.pulledClientIds, {'user_c'});
      expect(result.pushedClientIds, isEmpty);
      expect(result.mergedLocal.first.updatedAt, DateTime.utc(2026, 1, 5));
    });

    test('last-write-wins prefers newer local', () {
      final result = sync.merge(
        localPresets: [
          local(
            id: 'user_d',
            updatedAt: DateTime.utc(2026, 2, 1),
            remoteId: 'remote-d',
          ),
        ],
        remoteRecords: [
          remote(
            clientId: 'user_d',
            remoteId: 'remote-d',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      expect(result.pushedClientIds, {'user_d'});
      expect(result.pulledClientIds, isEmpty);
      expect(result.mergedLocal.first.updatedAt, DateTime.utc(2026, 2, 1));
    });
  });
}
