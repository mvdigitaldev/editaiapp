import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/manual_edit_datasource.dart';

final manualEditRepositoryProvider = Provider<ManualEditRepository>(
  (ref) => ManualEditRepository(),
);
