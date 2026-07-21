import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class PlanPhotoLimits {
  final int maxPhotos;
  final int storedPhotosCount;
  final bool canAddMore;

  const PlanPhotoLimits({
    required this.maxPhotos,
    required this.storedPhotosCount,
    required this.canAddMore,
  });
}

final planLimitsProvider = FutureProvider<PlanPhotoLimits>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) {
    return const PlanPhotoLimits(maxPhotos: 10, storedPhotosCount: 0, canAddMore: true);
  }

  final client = Supabase.instance.client;
  try {
    final response = await client
        .rpc('get_user_plan_photo_limits', params: {'p_user_id': user.id});

    if (response is List && response.isNotEmpty) {
      final row = response.first as Map<String, dynamic>;
      final maxPhotos = (row['max_photos'] as num?)?.toInt() ?? 10;
      final storedCount = (row['stored_photos_count'] as num?)?.toInt() ?? 0;
      return PlanPhotoLimits(
        maxPhotos: maxPhotos,
        storedPhotosCount: storedCount,
        canAddMore: storedCount < maxPhotos,
      );
    }
  } catch (_) {
    // Fallback em caso de erro
  }

  return const PlanPhotoLimits(maxPhotos: 10, storedPhotosCount: 0, canAddMore: true);
});
