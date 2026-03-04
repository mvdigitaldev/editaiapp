import 'package:editaiapp/core/storage/theme_preferences_storage.dart';
import 'package:editaiapp/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loadPreference defaults to ThemeMode.system when no value exists',
      () async {
    final notifier = ThemeModeNotifier(ThemePreferencesStorage());

    await notifier.loadPreference();

    expect(notifier.state, ThemeMode.system);
  });

  test('toggleByCurrentBrightness switches light brightness to dark mode',
      () async {
    final notifier = ThemeModeNotifier(ThemePreferencesStorage());
    await notifier.loadPreference();

    await notifier.toggleByCurrentBrightness(Brightness.light);
    final prefs = await SharedPreferences.getInstance();

    expect(notifier.state, ThemeMode.dark);
    expect(prefs.getString('app_theme_mode'), 'dark');
  });

  test('toggleByCurrentBrightness switches dark brightness to light mode',
      () async {
    final notifier = ThemeModeNotifier(ThemePreferencesStorage());
    await notifier.loadPreference();

    await notifier.toggleByCurrentBrightness(Brightness.dark);
    final prefs = await SharedPreferences.getInstance();

    expect(notifier.state, ThemeMode.light);
    expect(prefs.getString('app_theme_mode'), 'light');
  });
}
