import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/beauty_preset.dart';

/// Carrega presets de fábrica a partir de JSON em assets (Sprint 21).
class BundledPresetLoader {
  const BundledPresetLoader();

  static const assetPaths = [
    'assets/beauty/presets/natural.json',
    'assets/beauty/presets/instagram.json',
    'assets/beauty/presets/influencer.json',
    'assets/beauty/presets/beauty.json',
    'assets/beauty/presets/wedding.json',
    'assets/beauty/presets/studio.json',
    'assets/beauty/presets/soft.json',
    'assets/beauty/presets/cinema.json',
    'assets/beauty/presets/glam.json',
  ];

  Future<List<BeautyPreset>> load() async {
    final presets = <BeautyPreset>[];
    for (final path in assetPaths) {
      final raw = await rootBundle.loadString(path);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      presets.add(BeautyPreset.fromJson(json));
    }
    return presets;
  }
}
