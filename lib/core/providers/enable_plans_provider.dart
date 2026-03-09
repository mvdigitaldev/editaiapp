import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/profile/data/datasources/app_settings_datasource.dart';

final _appSettingsDataSourceProvider = Provider<AppSettingsDataSource>((ref) {
  return AppSettingsDataSourceImpl(Supabase.instance.client);
});

/// Retorna true quando enable_plans = "enable", false quando "disable" ou null/vazio.
/// Fail-closed: em loading/erro retorna false (elementos ocultos).
final enablePlansProvider = FutureProvider<bool>((ref) async {
  final ds = ref.watch(_appSettingsDataSourceProvider);
  final value = await ds.getValue('enable_plans');
  return value?.toLowerCase() == 'enable';
});
