import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferencesStorage {
  static const String _themeModeKey = 'app_theme_mode';
  static const String _lightValue = 'light';
  static const String _darkValue = 'dark';

  Future<ThemeMode?> readThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_themeModeKey);

    switch (storedValue) {
      case _lightValue:
        return ThemeMode.light;
      case _darkValue:
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();

    switch (mode) {
      case ThemeMode.light:
        await prefs.setString(_themeModeKey, _lightValue);
        return;
      case ThemeMode.dark:
        await prefs.setString(_themeModeKey, _darkValue);
        return;
      case ThemeMode.system:
        await prefs.remove(_themeModeKey);
        return;
    }
  }
}
