import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> init() async {
    await _getPrefs();
  }

  // Secure Storage (para tokens, dados sensiveis)
  Future<void> writeSecure(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  Future<String?> readSecure(String key) async {
    return _secureStorage.read(key: key);
  }

  Future<void> deleteSecure(String key) async {
    await _secureStorage.delete(key: key);
  }

  Future<void> clearSecure() async {
    await _secureStorage.deleteAll();
  }

  // Shared Preferences (para dados nao sensiveis)
  Future<void> write(String key, String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, value);
  }

  Future<String?> read(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  Future<void> delete(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  Future<void> clear() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }
}
