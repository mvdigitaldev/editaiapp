import 'dart:typed_data';

import 'texture_handle.dart';

/// Textura RGBA residente no backend (CPU ou GPU).
class TextureEntry {
  final int id;
  final int width;
  final int height;
  Uint8List rgba;

  TextureEntry({
    required this.id,
    required this.width,
    required this.height,
    required this.rgba,
  });

  int get byteLength => rgba.length;
}

/// Armazena texturas do renderer — abstrai backend CPU/GPU.
class GpuTextureStore {
  final Map<int, TextureEntry> _entries = {};
  int _nextId = 1;

  TextureEntry create({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    final id = _nextId++;
    final entry = TextureEntry(
      id: id,
      width: width,
      height: height,
      rgba: rgba,
    );
    _entries[id] = entry;
    return entry;
  }

  TextureEntry? get(int id) => _entries[id];

  TextureHandle toHandle(TextureEntry entry) {
    return TextureHandle(
      id: entry.id,
      width: entry.width,
      height: entry.height,
    );
  }

  void release(int id) {
    _entries.remove(id);
  }

  void clear() => _entries.clear();

  int get count => _entries.length;
}
