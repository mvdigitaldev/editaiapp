import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

/// Plano pago activo: tier diferente de `free` e assinatura não vencida.
/// Lê só os campos que o utilizador já traz (`subscription_tier`,
/// `subscription_ends_at`); não há tabela de recursos por plano.
bool hasActivePaidPlan({
  required String? subscriptionTier,
  required DateTime? subscriptionEndsAt,
  DateTime? now,
}) {
  final tier = subscriptionTier?.trim().toLowerCase() ?? 'free';
  if (tier.isEmpty || tier == 'free') {
    return false;
  }
  return subscriptionEndsAt == null ||
      subscriptionEndsAt.isAfter(now ?? DateTime.now());
}

/// `true` quando o utilizador pode ligar a trava de fundo do corpo.
final bodyBackgroundLockAllowedProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).user;
  return hasActivePaidPlan(
    subscriptionTier: user?.subscriptionTier,
    subscriptionEndsAt: user?.subscriptionEndsAt,
  );
});
