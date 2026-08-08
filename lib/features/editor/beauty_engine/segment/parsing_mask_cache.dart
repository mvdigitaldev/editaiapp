import 'dart:typed_data';

import 'face_parsing_class.dart';

/// Cache LRU de máscaras R8 por região (Sprint 4 — cap. 2.3).
class ParsingMaskCache {
  final Map<int, Uint8List> _entries = {};
  static const maxEntries = 8;

  Uint8List? get(int key) => _entries[key];

  void put(int key, Uint8List weights) {
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = weights;
  }

  void clear() => _entries.clear();

  static int cacheKey({
    required int width,
    required int height,
    required FaceParsingClass region,
    required int parsingHash,
    int tileOriginX = 0,
    int tileOriginY = 0,
  }) {
    return Object.hash(
      width,
      height,
      region.index,
      parsingHash,
      tileOriginX,
      tileOriginY,
    );
  }

  static int hashParsingBuffer(Uint8List classes) {
    if (classes.isEmpty) return 0;
    final mid = classes.length ~/ 2;
    return Object.hash(classes.length, classes[0], classes[mid], classes.last);
  }
}
