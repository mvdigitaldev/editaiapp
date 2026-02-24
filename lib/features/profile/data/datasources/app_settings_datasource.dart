import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AppSettingsDataSource {
  Future<String?> getValue(String key);
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
}
