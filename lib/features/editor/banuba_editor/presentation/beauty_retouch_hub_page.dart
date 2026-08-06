import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_remote_config_provider.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/hero_action_card.dart';

class BeautyRetouchHubPage extends ConsumerWidget {
  const BeautyRetouchHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final moduleConfig = ref.watch(homeModuleConfigProvider).valueOrNull ??
        const HomeModuleConfig.allEnabled();

    var cardIndex = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Retoque beauty')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'O que você quer ajustar?',
                style: AppTextStyles.headingSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Escolha uma categoria. As edições são processadas no '
                'dispositivo e não usam créditos de IA.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              HeroActionCard(
                index: cardIndex++,
                icon: Icons.face_retouching_natural,
                title: 'Rosto, pele e maquiagem',
                description:
                    'Suavização, detalhes faciais e maquiagem com Banuba.',
                onTap: () => Navigator.of(context).pushNamed('/face-retouch'),
              ),
              if (moduleConfig.faceLab) ...[
                const SizedBox(height: 12),
                HeroActionCard(
                  index: cardIndex++,
                  icon: Icons.science_outlined,
                  title: 'Rosto — novo editor (beta)',
                  description:
                      'Nosso editor facial próprio. Compare o resultado '
                      'com o editor atual usando a mesma foto.',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/face-retouch-lab'),
                ),
              ],
              const SizedBox(height: 12),
              HeroActionCard(
                index: cardIndex++,
                icon: Icons.accessibility_new_outlined,
                title: 'Ajustar corpo',
                description:
                    'Cintura, braços, pernas, altura e proporções corporais.',
                onTap: () => Navigator.of(context).pushNamed('/body-reshape'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
