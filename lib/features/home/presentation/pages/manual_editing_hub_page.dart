import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/hero_action_card.dart';
import '../../../editor/beauty_engine/di/beauty_engine_feature_flag_provider.dart';

/// Hub de edição manual — filtros, retoque beauty e marketplace.
class ManualEditingHubPage extends ConsumerWidget {
  const ManualEditingHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final beautyEnabledAsync = ref.watch(beautyEngineEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar manualmente'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edição local no dispositivo',
                style: AppTextStyles.headingSmall.copyWith(
                  color:
                      isDark ? Theme.of(context).colorScheme.onSurface : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Filtros, retoque e recorte — sem usar créditos de IA.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              HeroActionCard(
                index: 0,
                icon: Icons.brush_outlined,
                title: 'Editar manualmente',
                description: 'Filtros, ajustes e recorte — sem IA, grátis.',
                onTap: () => Navigator.of(context).pushNamed('/manual-editor'),
              ),
              const SizedBox(height: 12),
              HeroActionCard(
                index: 1,
                icon: Icons.view_agenda_outlined,
                title: 'Colagem sem emenda',
                description:
                    'Empilhe até 6 fotos com transição suave — sem IA, grátis.',
                onTap: () =>
                    Navigator.of(context).pushNamed('/seamless-collage'),
              ),
              const SizedBox(height: 12),
              HeroActionCard(
                index: 2,
                icon: Icons.auto_fix_high,
                title: 'Retoque beauty',
                description: 'Ajustes de rosto, pele, maquiagem e corpo.',
                onTap: () => Navigator.of(context).pushNamed('/beauty-editor'),
              ),
              beautyEnabledAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (enabled) {
                  if (!enabled) return const SizedBox.shrink();
                  return Column(
                    children: [
                      const SizedBox(height: 12),
                      HeroActionCard(
                        index: 3,
                        icon: Icons.tune_outlined,
                        title: 'Criar filtro custom',
                        description:
                            'LUT e grade estilo Lightroom — uso pessoal.',
                        onTap: () => Navigator.of(context)
                            .pushNamed('/beauty-preset-creator'),
                      ),
                      const SizedBox(height: 12),
                      HeroActionCard(
                        index: 4,
                        icon: Icons.storefront_outlined,
                        title: 'Marketplace de filtros',
                        description:
                            'Instale filtros da comunidade no editor manual.',
                        onTap: () => Navigator.of(context)
                            .pushNamed('/beauty-preset-marketplace'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
