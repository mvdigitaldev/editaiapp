import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/support_datasource.dart';

final supportDataSourceProvider = Provider<SupportDataSource>((ref) {
  return SupportDataSourceImpl(ref.watch(supabaseClientProvider));
});
