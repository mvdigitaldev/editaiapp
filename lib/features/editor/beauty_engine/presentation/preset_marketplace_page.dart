import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../filter_presets/filter_presets_provider.dart';
import '../di/beauty_engine_providers.dart';
import '../l10n/beauty_engine_labels.dart';
import '../models/beauty_preset_marketplace_entry.dart';

/// Browse e instalação de filtros públicos (Sprint 24).
class PresetMarketplacePage extends ConsumerStatefulWidget {
  const PresetMarketplacePage({super.key});

  @override
  ConsumerState<PresetMarketplacePage> createState() =>
      _PresetMarketplacePageState();
}

class _PresetMarketplacePageState extends ConsumerState<PresetMarketplacePage> {
  String? _installingRemoteId;

  Future<void> _refresh() async {
    ref.invalidate(marketplacePresetsProvider);
    await ref.read(marketplacePresetsProvider.future);
  }

  Future<void> _install(BeautyPresetMarketplaceEntry entry) async {
    if (_installingRemoteId != null) {
      return;
    }

    setState(() => _installingRemoteId = entry.remoteId);
    try {
      final installed = await ref
          .read(beautyPresetRepositoryProvider)
          .installMarketplacePreset(entry.remoteId);

      ref.invalidate(userBeautyPresetsProvider);
      ref.invalidate(allBeautyPresetsProvider);
      ref.invalidate(filterPresetsProvider);
      ref.invalidate(manualEditorCustomFiltersProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${installed.name}: ${BeautyEngineLabels.filterInstalledHint}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao instalar: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _installingRemoteId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final marketplaceAsync = ref.watch(marketplacePresetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(BeautyEngineLabels.filterMarketplaceTitle),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: auth.isAuthenticated ? _refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !auth.isAuthenticated
          ? _LoginRequired(onLogin: () {
              Navigator.of(context).pushNamed('/login');
            })
          : RefreshIndicator(
              onRefresh: _refresh,
              child: marketplaceAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro ao carregar marketplace: $error'),
                    ),
                  ],
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.storefront_outlined, size: 56),
                        SizedBox(height: 16),
                        Text(
                          'Nenhum filtro público ainda.\nPublique o seu em Criar filtro custom.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final installing = _installingRemoteId == entry.remoteId;

                      return _MarketplaceCard(
                        entry: entry,
                        installing: installing,
                        onInstall: () => _install(entry),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _LoginRequired extends StatelessWidget {
  const _LoginRequired({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Entre na sua conta para explorar e instalar filtros públicos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onLogin,
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketplaceCard extends StatelessWidget {
  const _MarketplaceCard({
    required this.entry,
    required this.installing,
    required this.onInstall,
  });

  final BeautyPresetMarketplaceEntry entry;
  final bool installing;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(url: entry.thumbnailUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'por ${entry.authorName}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${entry.installCount} instalações',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: installing ? null : onInstall,
              child: installing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(BeautyEngineLabels.filterInstallAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        color: AppColors.surfaceLight,
        child: url == null
            ? const Icon(Icons.auto_fix_high)
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
              ),
      ),
    );
  }
}
