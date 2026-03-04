import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/theme_preferences_storage.dart';

final themePreferencesStorageProvider =
    Provider<ThemePreferencesStorage>((ref) {
  return ThemePreferencesStorage();
});

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final storage = ref.watch(themePreferencesStorageProvider);
  return ThemeModeNotifier(storage);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    loadPreference();
  }

  final ThemePreferencesStorage _storage;
  int _operationVersion = 0;

  Future<void> loadPreference() async {
    final requestVersion = ++_operationVersion;
    final savedMode = await _storage.readThemeMode();
    if (requestVersion != _operationVersion) return;
    state = savedMode ?? ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _operationVersion++;
    await _storage.writeThemeMode(mode);
    state = mode;
  }

  Future<void> toggleByCurrentBrightness(Brightness current) async {
    final nextMode =
        current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(nextMode);
  }
}
