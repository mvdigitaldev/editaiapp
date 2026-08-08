import 'package:flutter/material.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/hero_action_card.dart';

class BeautyRetouchHubPage extends StatelessWidget {
  const BeautyRetouchHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                index: 0,
                icon: Icons.face_retouching_natural,
                title: 'Rosto, pele e maquiagem',
                description:
                    'Suavização, detalhes faciais e retoque com nosso editor.',
                onTap: () => Navigator.of(context).pushNamed('/face-retouch'),
              ),
              const SizedBox(height: 12),
              HeroActionCard(
                index: 1,
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
