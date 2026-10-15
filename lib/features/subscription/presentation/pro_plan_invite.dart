import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/app_remote_config_provider.dart';
import '../../../core/providers/enable_plans_provider.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'widgets/pro_plan_banner.dart';

const freeManualProBannerEveryKey = 'free_manual_pro_banner_every';
const proBannerDismissDaysKey = 'pro_banner_dismiss_days';

const _dismissCompactKey = 'pro_banner_dismissed_compact_at';
const _dismissPrincipalKey = 'pro_banner_dismissed_principal_at';

/// Incrementa para a home voltar a ler o fecho gravado no telemóvel.
final proBannerEpochProvider = StateProvider<int>((ref) => 0);

class ProBannerConfig {
  const ProBannerConfig({required this.every, required this.dismissDays});

  /// `0` desliga o banner principal. Valor em falta usa 3.
  final int every;

  /// Dias sem voltar a mostrar o compacto e o principal depois de fechar.
  final int dismissDays;

  static const fallback = ProBannerConfig(every: 3, dismissDays: 7);
}

class ProBannerHighlights {
  const ProBannerHighlights({
    required this.morePhotos,
    required this.moreCredits,
  });

  final bool morePhotos;
  final bool moreCredits;

  static const fallback = ProBannerHighlights(
    morePhotos: true,
    moreCredits: false,
  );
}

final proBannerConfigProvider = FutureProvider<ProBannerConfig>((ref) async {
  final ds = ref.watch(appSettingsDataSourceProvider);
  try {
    final values = await ds.getValues(const [
      freeManualProBannerEveryKey,
      proBannerDismissDaysKey,
    ]);
    return ProBannerConfig(
      every: _parseEvery(values[freeManualProBannerEveryKey]),
      dismissDays: _parseDays(values[proBannerDismissDaysKey]),
    );
  } catch (_) {
    return ProBannerConfig.fallback;
  }
});

int _parseEvery(String? raw) {
  final value = int.tryParse(raw?.trim() ?? '');
  if (value == null || value < 0) return ProBannerConfig.fallback.every;
  return value;
}

int _parseDays(String? raw) {
  final value = int.tryParse(raw?.trim() ?? '');
  if (value == null || value < 0) return ProBannerConfig.fallback.dismissDays;
  return value;
}

/// A 3.ª, a 6.ª e a 9.ª com [every] = 3. Zero edições ou intervalo desligado não.
bool shouldOfferAfterManualEdits({required int count, required int every}) {
  if (every <= 0 || count <= 0) return false;
  return count % every == 0;
}

final proBannerHighlightsProvider =
    FutureProvider<ProBannerHighlights>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from('plans')
        .select('name, price, add_credit, max_stored_photos')
        .eq('is_active', true);
    var freePhotos = 5;
    var paidPhotos = 0;
    var moreCredits = false;
    for (final row in rows as List) {
      final name = (row['name'] as String? ?? '').toLowerCase();
      final price = (row['price'] as num?)?.toDouble() ?? 0;
      final photos = (row['max_stored_photos'] as num?)?.toInt() ?? 0;
      final credits = (row['add_credit'] as num?)?.toInt() ?? 0;
      final isFree = name == 'free' || price <= 0;
      if (isFree) {
        if (photos > 0) freePhotos = photos;
      } else {
        if (photos > paidPhotos) paidPhotos = photos;
        if (credits > 0) moreCredits = true;
      }
    }
    return ProBannerHighlights(
      morePhotos: paidPhotos > freePhotos,
      moreCredits: moreCredits,
    );
  } catch (_) {
    return ProBannerHighlights.fallback;
  }
});

final proCompactBannerVisibleProvider = FutureProvider<bool>((ref) async {
  ref.watch(proBannerEpochProvider);
  final plansOn = await ref.watch(enablePlansProvider.future);
  if (!plansOn) return false;
  final tier =
      ref.watch(authStateProvider).user?.subscriptionTier.toLowerCase();
  if (tier != null && tier != 'free') return false;
  final config = await ref.watch(proBannerConfigProvider.future);
  return !await _isSilenced(_dismissCompactKey, config.dismissDays);
});

Future<bool> _isSilenced(String key, int days) async {
  if (days <= 0) return false;
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(key);
  if (raw == null) return false;
  final at = DateTime.tryParse(raw);
  if (at == null) return false;
  return DateTime.now().difference(at) < Duration(days: days);
}

Future<void> _silence(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, DateTime.now().toIso8601String());
}

Future<bool> proInviteAllowed(WidgetRef ref) async {
  final plansOn = await ref.read(enablePlansProvider.future);
  if (!plansOn) return false;
  final tier = ref.read(authStateProvider).user?.subscriptionTier.toLowerCase();
  return tier == null || tier == 'free';
}

void openProPlans(BuildContext context) {
  Navigator.of(context).pushNamed('/subscription');
}

/// Créditos de IA a zero. Fechar segue para a loja. O toque abre os planos.
Future<void> showOutOfAiCreditsOffer(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await proInviteAllowed(ref)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Créditos insuficientes. Recarregue para continuar.'),
      ),
    );
    await Navigator.of(context).pushNamed('/credits-shop');
    return;
  }

  if (!context.mounted) return;
  final highlights = await ref.read(proBannerHighlightsProvider.future);
  if (!context.mounted) return;
  final openPlans = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ProPlanBanner(
          kind: ProBannerKind.offer,
          highlights: highlights,
          onTap: () => Navigator.of(dialogContext).pop(true),
          onClose: () => Navigator.of(dialogContext).pop(false),
        ),
      );
    },
  );
  if (!context.mounted) return;
  if (openPlans == true) {
    openProPlans(context);
  } else {
    await Navigator.of(context).pushNamed('/credits-shop');
  }
}

/// Ferramenta exclusiva. O painel é o banner de oportunidade.
Future<void> showExclusiveFeatureOffer(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await proInviteAllowed(ref)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disponível nos planos pagos.')),
    );
    return;
  }
  if (!context.mounted) return;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Consumer(
            builder: (context, ref, _) {
              final highlights =
                  ref.watch(proBannerHighlightsProvider).valueOrNull ??
                      ProBannerHighlights.fallback;
              return ProPlanBanner(
                kind: ProBannerKind.opportunity,
                highlights: highlights,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openProPlans(context);
                },
                onClose: () => Navigator.of(sheetContext).pop(),
              );
            },
          ),
        ),
      );
    },
  );
}

/// Banner principal na comparação, no lugar do anúncio, a cada N edições.
Future<bool> showPrincipalAfterManualEdit(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await proInviteAllowed(ref)) return false;
  final config = await ref.read(proBannerConfigProvider.future);
  if (config.every <= 0) return false;
  if (await _isSilenced(_dismissPrincipalKey, config.dismissDays)) {
    return false;
  }

  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;
  int count;
  try {
    final response = await Supabase.instance.client
        .from('edits')
        .select('id')
        .eq('user_id', userId)
        .eq('operation_type', 'manual_edit')
        .eq('status', 'completed')
        .count(CountOption.exact);
    count = response.count;
  } catch (_) {
    return false;
  }
  if (!shouldOfferAfterManualEdits(count: count, every: config.every)) {
    return false;
  }
  if (!context.mounted) return false;

  final highlights = await ref.read(proBannerHighlightsProvider.future);
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ProPlanBanner(
          kind: ProBannerKind.principal,
          highlights: highlights,
          onTap: () {
            Navigator.of(dialogContext).pop();
            openProPlans(context);
          },
          onClose: () async {
            await _silence(_dismissPrincipalKey);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
        ),
      );
    },
  );
  return true;
}

Future<void> dismissCompactBanner(WidgetRef ref) async {
  await _silence(_dismissCompactKey);
  ref.read(proBannerEpochProvider.notifier).state++;
}
