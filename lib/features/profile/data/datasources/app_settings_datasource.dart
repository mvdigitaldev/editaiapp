import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AppSettingsDataSource {
  Future<String?> getValue(String key);

  Future<Map<String, String>> getValues(Iterable<String> keys);
}

class AppSettingsDataSourceImpl implements AppSettingsDataSource {
  final SupabaseClient _supabase;

  AppSettingsDataSourceImpl(this._supabase);

  @override
  Future<String?> getValue(String key) async {
    final response = await _supabase
        .from('app_settings')
        .select('setting_value')
        .eq('setting_key', key)
        .maybeSingle();

    if (response == null) return null;
    return response['setting_value'] as String?;
  }

  @override
  Future<Map<String, String>> getValues(Iterable<String> keys) async {
    final requested = keys.toSet().toList(growable: false);
    if (requested.isEmpty) return const {};

    final response = await _supabase
        .from('app_settings')
        .select('setting_key, setting_value')
        .inFilter('setting_key', requested);

    return {
      for (final row in response)
        if (row['setting_key'] case final String key)
          key: row['setting_value']?.toString() ?? '',
    };
  }
}
