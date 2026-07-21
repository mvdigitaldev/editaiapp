import 'dart:convert';
import 'dart:io';

import '../models/beauty_preset.dart';

/// Persistencia local de presets do usuario em JSON (Sprint 08).
class BeautyPresetLocalStore {
  BeautyPresetLocalStore({
    Future<Directory> Function()? resolveDirectory,
    List<BeautyPreset>? seed,
  })  : _resolveDirectory = resolveDirectory,
        _memory = seed != null ? List<BeautyPreset>.from(seed) : null;

  static const fileName = 'user_presets.json';

  final Future<Directory> Function()? _resolveDirectory;
  List<BeautyPreset>? _memory;
  bool _loaded = false;

  bool get isInMemory => _resolveDirectory == null;

  Future<List<BeautyPreset>> readAll() async {
    if (isInMemory) {
      _memory ??= [];
      return List<BeautyPreset>.from(_memory!);
    }

    if (!_loaded) {
      _memory = await _readFromDisk();
      _loaded = true;
    }
    return List<BeautyPreset>.from(_memory!);
  }

  Future<void> writeAll(List<BeautyPreset> presets) async {
    _memory = List<BeautyPreset>.from(presets);
    if (isInMemory) {
      return;
    }

    final directory = await _resolveDirectory!();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/$fileName');
    final encoded = presets.map((preset) => preset.toJson()).toList();
    await file.writeAsString(jsonEncode(encoded));
    _loaded = true;
  }

  Future<List<BeautyPreset>> _readFromDisk() async {
    final directory = await _resolveDirectory!();
    final file = File('${directory.path}/$fileName');
    if (!await file.exists()) {
      return [];
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      return [];
    }

    return decoded
        .whereType<Map>()
        .map((entry) => BeautyPreset.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }
}
