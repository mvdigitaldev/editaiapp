import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class CreditsUsage {
  final int total;
  final int used;
  final int balance;
  final double progress;

  const CreditsUsage({
    required this.total,
    required this.used,
    required this.balance,
    required this.progress,
  });
}

final creditsUsageProvider = FutureProvider<CreditsUsage>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) {
    return const CreditsUsage(
      total: 0,
      used: 0,
      balance: 0,
      progress: 0,
    );
  }

  final client = Supabase.instance.client;

  // 1) Breakdown: obter extras restantes e saldo via função SQL
  int extrasRemaining = 0;
  int balanceFromFn = 0;
  try {
    final result =
        await client.rpc('get_user_credits_breakdown') as List<dynamic>;

    if (result.isNotEmpty) {
      final row = result.first as Map<String, dynamic>;
      final extra = row['extra_credits_remaining'];
      final totalBalance = row['total_balance'];
      if (extra != null) {
        extrasRemaining =
            (extra is num) ? extra.toInt() : int.tryParse(extra.toString()) ?? 0;
      }
      if (totalBalance != null) {
        balanceFromFn = (totalBalance is num)
            ? totalBalance.toInt()
            : int.tryParse(totalBalance.toString()) ?? 0;
      }
    }
  } catch (_) {
    // Se der erro, seguimos com extrasRemaining = 0 e balanceFromFn = 0
  }

  // 2) Descobrir monthly_credits do plano atual
  int monthlyCredits = 0;
  try {
    final userRow = await client
        .from('users')
        .select('current_plan_id')
        .eq('id', user.id)
        .maybeSingle();

    final planId = userRow?['current_plan_id'];
    if (planId != null) {
      final planRow = await client
          .from('plans')
          .select('monthly_credits')
          .eq('id', planId)
          .maybeSingle();

      final mc = planRow?['monthly_credits'];
      if (mc != null) {
        monthlyCredits =
            (mc is num) ? mc.toInt() : int.tryParse(mc.toString()) ?? 0;
      }
    }
  } catch (_) {
    // Se não conseguir ler o plano, monthlyCredits permanece 0.
  }

  // 3) Calcular total, usados e progress
  final balance =
      user.creditsBalance ?? (balanceFromFn > 0 ? balanceFromFn : 0);

  int total = monthlyCredits + extrasRemaining;

  // Se por algum motivo total ficar menor que o saldo, ajustamos para no mínimo o saldo.
  if (total < balance) {
    total = balance;
  }

  int used = total - balance;
  if (used < 0) used = 0;
  if (used > total) used = total;

  double progress = 0;
  if (total > 0) {
    progress = used / total;
    if (progress.isNaN || progress.isInfinite) progress = 0;
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;
  }

  return CreditsUsage(
    total: total,
    used: used,
    balance: balance,
    progress: progress,
  );
});

