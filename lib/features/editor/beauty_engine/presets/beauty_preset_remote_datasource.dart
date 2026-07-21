import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/beauty_preset.dart';
import '../models/beauty_preset_marketplace_entry.dart';
import 'beauty_preset_remote_record.dart';

/// CRUD remoto de presets via Supabase (Sprint 23/24).
class BeautyPresetRemoteDataSource {
  BeautyPresetRemoteDataSource(this._client);

  final SupabaseClient _client;

  static const table = 'beauty_presets';
  static const marketplaceView = 'beauty_presets_marketplace';
  static const thumbnailBucket = 'beauty-preset-thumbnails';

  Future<List<BeautyPresetRemoteRecord>> fetchUserPresets(String userId) async {
    final response = await _client
        .from(table)
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => BeautyPresetRemoteRecord.fromJson(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  Future<BeautyPresetRemoteRecord?> fetchByRemoteId(String remoteId) async {
    final response = await _client
        .from(table)
        .select()
        .eq('id', remoteId)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return BeautyPresetRemoteRecord.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<BeautyPresetRemoteRecord> upsertPreset({
    required String userId,
    required BeautyPreset preset,
    String? remoteId,
    String? thumbnailUrl,
  }) async {
    final record = remoteId == null
        ? await _insert(userId: userId, preset: preset, thumbnailUrl: thumbnailUrl)
        : await _update(
            remoteId: remoteId,
            preset: preset,
            thumbnailUrl: thumbnailUrl,
          );

    return record;
  }

  Future<void> deletePreset(String remoteId) async {
    await _client.from(table).delete().eq('id', remoteId);
  }

  Future<List<BeautyPresetMarketplaceEntry>> listMarketplacePresets({
    String? excludeAuthorId,
    int limit = 50,
    int offset = 0,
  }) async {
    var filter = _client.from(marketplaceView).select();

    if (excludeAuthorId != null) {
      filter = filter.neq('author_id', excludeAuthorId);
    }

    final response = await filter
        .order('updated_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (response as List<dynamic>)
        .map((row) => BeautyPresetMarketplaceEntry.fromJson(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  Future<void> incrementInstallCount(String remoteId) async {
    await _client.rpc<void>(
      'increment_beauty_preset_install_count',
      params: {'p_preset_id': remoteId},
    );
  }

  Future<String?> uploadThumbnail({
    required String userId,
    required String remoteId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      return null;
    }

    final path = '$userId/$remoteId.jpg';
    await _client.storage.from(thumbnailBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    return _client.storage.from(thumbnailBucket).getPublicUrl(path);
  }

  Future<void> deleteThumbnail({
    required String userId,
    required String remoteId,
  }) async {
    final path = '$userId/$remoteId.jpg';
    try {
      await _client.storage.from(thumbnailBucket).remove([path]);
    } on StorageException {
      // Thumbnail ausente — ignorar.
    }
  }

  Future<String?> downloadThumbnailToFile({
    required String thumbnailUrl,
    required File destination,
  }) async {
    if (thumbnailUrl.isEmpty) {
      return null;
    }

    final uri = Uri.parse(thumbnailUrl);
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        return null;
      }

      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, data) {
          builder.add(data);
          return builder;
        },
      ).then((builder) => builder.takeBytes());

      if (bytes.isEmpty) {
        return null;
      }

      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(bytes, flush: true);
      return destination.path;
    } finally {
      httpClient.close();
    }
  }

  Future<BeautyPresetRemoteRecord> _insert({
    required String userId,
    required BeautyPreset preset,
    String? thumbnailUrl,
  }) async {
    final payload = BeautyPresetRemoteRecord(
      id: '',
      userId: userId,
      clientId: preset.id,
      name: preset.name,
      preset: preset,
      isPublic: preset.isPublic,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ).toInsertJson(
      userId: userId,
      preset: preset,
      name: preset.name,
      isPublic: preset.isPublic,
      thumbnailUrl: thumbnailUrl,
    );

    final response = await _client.from(table).insert(payload).select().single();
    return BeautyPresetRemoteRecord.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<BeautyPresetRemoteRecord> _update({
    required String remoteId,
    required BeautyPreset preset,
    String? thumbnailUrl,
  }) async {
    final payload = BeautyPresetRemoteRecord(
      id: remoteId,
      userId: preset.authorId ?? '',
      clientId: preset.id,
      name: preset.name,
      preset: preset,
      isPublic: preset.isPublic,
      createdAt: preset.createdAt ?? DateTime.now().toUtc(),
      updatedAt: preset.updatedAt ?? DateTime.now().toUtc(),
    ).toUpdateJson(
      preset: preset,
      name: preset.name,
      isPublic: preset.isPublic,
      thumbnailUrl: thumbnailUrl,
    );

    final response = await _client
        .from(table)
        .update(payload)
        .eq('id', remoteId)
        .select()
        .single();

    return BeautyPresetRemoteRecord.fromJson(
      Map<String, dynamic>.from(response),
    );
  }
}
