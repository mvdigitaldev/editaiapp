import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class CreditsUsage {
  final int balance;

  const CreditsUsage({required this.balance});
}

/// Saldo de créditos: fonte única users.credits_balance
final creditsUsageProvider = FutureProvider<CreditsUsage>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) {
    return const CreditsUsage(balance: 0);
  }

  final client = Supabase.instance.client;
  int balance = user.creditsBalance ?? 0;

  try {
    final row = await client
        .from('users')
        .select('credits_balance')
        .eq('id', user.id)
        .maybeSingle();

    if (row != null && row['credits_balance'] != null) {
      final v = row['credits_balance'];
      balance = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
    }
  } catch (_) {
    // Fallback para valor em cache do user
  }

  return CreditsUsage(balance: balance);
});
