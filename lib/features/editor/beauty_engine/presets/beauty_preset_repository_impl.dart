import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:postgrest/postgrest.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/postgrest_user_message.dart';
import '../models/beauty_preset.dart';
import '../models/beauty_preset_marketplace_entry.dart';
import 'beauty_preset_local_store.dart';
import 'beauty_preset_remote_datasource.dart';
import 'beauty_preset_remote_record.dart';
import 'beauty_preset_repository.dart';
import 'bundled_presets.dart';
import 'bundled_preset_loader.dart';
import 'preset_sync_service.dart';
import 'preset_thumbnail_service.dart';

export 'beauty_preset_body_migration.dart';

/// Repositorio local + sync Supabase opcional (Sprint 23/24).
class BeautyPresetRepositoryImpl implements BeautyPresetRepository {
  BeautyPresetRepositoryImpl({
    BeautyPresetLocalStore? store,
    BundledPresetLoader? bundledLoader,
    PresetThumbnailService? thumbnailService,
    BeautyPresetRemoteDataSource? remote,
    PresetSyncService? syncService,
    String? Function()? currentUserId,
  })  : _store = store ?? BeautyPresetLocalStore(),
        _bundledLoader = bundledLoader ?? const BundledPresetLoader(),
        _thumbnailService = thumbnailService ?? const PresetThumbnailService(),
        _remote = remote,
        _syncService = syncService ?? const PresetSyncService(),
        _currentUserId = currentUserId;

  final BeautyPresetLocalStore _store;
  final BundledPresetLoader _bundledLoader;
  final PresetThumbnailService _thumbnailService;
  final BeautyPresetRemoteDataSource? _remote;
  final PresetSyncService _syncService;
  final String? Function()? _currentUserId;

  List<BeautyPreset>? _userPresets;

  Future<List<BeautyPreset>> _bundledLoaded() {
    return BundledBeautyPresets.loadAll(loader: _bundledLoader);
  }

  Future<List<BeautyPreset>> _userPresetsLoaded() async {
    _userPresets ??= await _store.readAll();
    return _userPresets!;
  }

  Future<void> _persistUserPresets() async {
    await _store.writeAll(_userPresets ?? []);
  }

  String? get _authenticatedUserId => _currentUserId?.call();

  @override
  Future<List<BeautyPreset>> listPresets() async {
    final bundled = await _bundledLoaded();
    final user = await _userPresetsLoaded();
    return [...bundled, ...user];
  }

  @override
  Future<List<BeautyPreset>> listBundledPresets() async {
    return List<BeautyPreset>.from(await _bundledLoaded());
  }

  @override
  Future<List<BeautyPreset>> listUserPresets() async {
    return List<BeautyPreset>.from(await _userPresetsLoaded());
  }

  @override
  Future<BeautyPreset?> findById(String id) async {
    final bundled = BundledBeautyPresets.findById(id);
    if (bundled != null) {
      return bundled;
    }

    if (BundledBeautyPresets.isBundled(id)) {
      final loaded = await _bundledLoaded();
      for (final preset in loaded) {
        if (preset.id == id) {
          return preset;
        }
      }
    }

    final user = await _userPresetsLoaded();
    for (final preset in user) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  @override
  Future<void> savePreset(BeautyPreset preset) async {
    if (BundledBeautyPresets.isBundled(preset.id)) {
      throw ArgumentError('Bundled preset cannot be overwritten: ${preset.id}');
    }

    var stamped = preset.withLocalSaveTimestamp();
    final userId = _authenticatedUserId;
    if (userId != null) {
      stamped = stamped.copyWith(authorId: userId);
    }

    final user = await _userPresetsLoaded();
    user.removeWhere((entry) => entry.id == stamped.id);

    if (_remote != null && userId != null) {
      try {
        stamped = await _pushPresetToRemote(stamped, userId);
      } on PostgrestException catch (e) {
        throw Exception(_marketplacePublishErrorMessage(e, preset: stamped));
      }
    }

    user.add(stamped);
    await _persistUserPresets();
  }

  @override
  Future<void> deletePreset(String id) async {
    if (BundledBeautyPresets.isBundled(id)) {
      throw ArgumentError('Bundled preset cannot be deleted: $id');
    }

    final user = await _userPresetsLoaded();
    BeautyPreset? removed;
    for (final preset in user) {
      if (preset.id == id) {
        removed = preset;
        break;
      }
    }

    user.removeWhere((entry) => entry.id == id);
    await _persistUserPresets();
    await _thumbnailService.deleteForPreset(id);

    final remote = _remote;
    final remoteId = removed?.remoteId;
    final userId = _authenticatedUserId;
    if (remote != null && userId != null && remoteId != null) {
      await remote.deletePreset(remoteId);
      await remote.deleteThumbnail(userId: userId, remoteId: remoteId);
    }
  }

  @override
  Future<String> exportPresetJson(String id) async {
    final preset = await findById(id);
    if (preset == null) {
      throw StateError('Preset not found: $id');
    }
    return jsonEncode(preset.toJson());
  }

  @override
  Future<BeautyPreset> importPresetJson(Map<String, dynamic> json) async {
    // BeautyPreset.fromJson aplica BeautyPresetBodyMigration (Sprint 12).
    var preset = BeautyPreset.fromJson(json);
    if (BundledBeautyPresets.isBundled(preset.id)) {
      preset = preset.copyWith(
        id: 'user_${const Uuid().v4()}',
        clearThumbnailPath: true,
        clearRemoteId: true,
      );
    }

    await savePreset(preset);
    return preset;
  }

  @override
  Future<BeautyPreset> savePresetWithThumbnail({
    required BeautyPreset preset,
    required List<int> previewJpegBytes,
  }) async {
    final thumbPath = await _thumbnailService.saveFromJpeg(
      presetId: preset.id,
      jpegBytes: Uint8List.fromList(previewJpegBytes),
    );
    final withThumb = preset.copyWith(thumbnailPath: thumbPath);
    await savePreset(withThumb);
    return await findById(withThumb.id) ?? withThumb;
  }

  @override
  Future<void> syncWithRemote() async {
    final remote = _remote;
    final userId = _authenticatedUserId;
    if (remote == null || userId == null) {
      return;
    }

    final local = List<BeautyPreset>.from(await _userPresetsLoaded());
    final remoteRecords = await remote.fetchUserPresets(userId);
    final merge = _syncService.merge(
      localPresets: local,
      remoteRecords: remoteRecords,
    );

    final remoteByClientId = {
      for (final record in remoteRecords) record.clientId: record,
    };

    final synced = <BeautyPreset>[];
    for (final preset in merge.mergedLocal) {
      var current = preset;

      if (merge.pulledClientIds.contains(preset.id)) {
        final record = remoteByClientId[preset.id];
        if (record != null) {
          current = await _hydratePulledPreset(current, record);
        }
      } else if (merge.pushedClientIds.contains(preset.id)) {
        current = await _pushPresetToRemote(
          current.copyWith(authorId: userId),
          userId,
        );
      } else {
        final record = remoteByClientId[preset.id];
        if (record != null) {
          current = current.copyWith(
            remoteId: record.id,
            authorId: userId,
            isPublic: record.isPublic,
            updatedAt: record.updatedAt,
            createdAt: record.createdAt,
          );
        }
      }

      synced.add(current);
    }

    _userPresets = synced;
    await _persistUserPresets();
  }

  @override
  Future<BeautyPreset> setPresetPublic({
    required String id,
    required bool isPublic,
  }) async {
    final preset = await findById(id);
    if (preset == null || BundledBeautyPresets.isBundled(id)) {
      throw StateError('Preset not found or not editable: $id');
    }

    final updated = preset.withLocalSaveTimestamp().copyWith(isPublic: isPublic);
    await savePreset(updated);
    return await findById(id) ?? updated;
  }

  @override
  Future<List<BeautyPresetMarketplaceEntry>> listMarketplacePresets({
    int limit = 50,
    int offset = 0,
  }) async {
    final remote = _remote;
    if (remote == null) {
      return const [];
    }

    return remote.listMarketplacePresets(
      excludeAuthorId: _authenticatedUserId,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<BeautyPreset> installMarketplacePreset(String remoteId) async {
    final remote = _remote;
    final userId = _authenticatedUserId;
    if (remote == null || userId == null) {
      throw StateError('Login necessário para instalar presets públicos.');
    }

    final record = await remote.fetchByRemoteId(remoteId);
    if (record == null || !record.isPublic) {
      throw StateError('Preset público não encontrado.');
    }

    final newId = 'user_${const Uuid().v4()}';
    var installed = record.preset.copyWith(
      id: newId,
      name: record.name,
      clearRemoteId: true,
      clearThumbnailPath: true,
      isPublic: false,
      authorId: userId,
      installedFromRemoteId: remoteId,
    ).withLocalSaveTimestamp();

    if (record.thumbnailUrl != null) {
      final directory = await _thumbnailService.resolveDirectory();
      final destination = File('${directory.path}/$newId.jpg');
      final localPath = await remote.downloadThumbnailToFile(
        thumbnailUrl: record.thumbnailUrl!,
        destination: destination,
      );
      if (localPath != null) {
        installed = installed.copyWith(thumbnailPath: localPath);
      }
    }

    await savePreset(installed);
    await remote.incrementInstallCount(remoteId);
    return await findById(newId) ?? installed;
  }

  Future<BeautyPreset> _pushPresetToRemote(
    BeautyPreset preset,
    String userId,
  ) async {
    final remote = _remote!;
    var record = await remote.upsertPreset(
      userId: userId,
      preset: preset,
      remoteId: preset.remoteId,
    );

    String? thumbnailUrl = record.thumbnailUrl;
    final thumbPath = preset.thumbnailPath;
    if (thumbPath != null) {
      final file = File(thumbPath);
      if (await file.exists()) {
        thumbnailUrl = await remote.uploadThumbnail(
          userId: userId,
          remoteId: record.id,
          bytes: await file.readAsBytes(),
        );
      }
    }

    if (thumbnailUrl != record.thumbnailUrl) {
      record = await remote.upsertPreset(
        userId: userId,
        preset: preset.copyWith(remoteId: record.id, authorId: userId),
        remoteId: record.id,
        thumbnailUrl: thumbnailUrl,
      );
    }

    return preset.copyWith(
      remoteId: record.id,
      authorId: userId,
      isPublic: record.isPublic,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }

  Future<BeautyPreset> _hydratePulledPreset(
    BeautyPreset preset,
    BeautyPresetRemoteRecord record,
  ) async {
    var hydrated = preset;
    final thumbnailUrl = record.thumbnailUrl;
    if (thumbnailUrl != null) {
      final directory = await _thumbnailService.resolveDirectory();
      final destination = File('${directory.path}/${preset.id}.jpg');
      final localPath = await _remote!.downloadThumbnailToFile(
        thumbnailUrl: thumbnailUrl,
        destination: destination,
      );
      if (localPath != null) {
        hydrated = hydrated.copyWith(thumbnailPath: localPath);
      }
    }
    return hydrated;
  }
}

String _marketplacePublishErrorMessage(
  PostgrestException e, {
  required BeautyPreset preset,
}) {
  if (!preset.isPublic) {
    return postgrestUserMessage(e);
  }
  final msg = postgrestUserMessage(e);
  if (msg.contains('Sem permissão') ||
      e.code == '42501' ||
      e.message.toLowerCase().contains('policy')) {
    return 'Apenas administradores podem publicar presets no marketplace.';
  }
  return msg;
}
