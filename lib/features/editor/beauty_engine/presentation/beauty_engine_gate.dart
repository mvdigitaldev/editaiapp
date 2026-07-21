import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../di/beauty_engine_feature_flag_provider.dart';

/// Bloqueia telas do Beauty Engine quando o rollout não inclui o usuário.
class BeautyEngineGate extends ConsumerWidget {
  const BeautyEngineGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(beautyEngineEnabledProvider);

    return enabledAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _UnavailableScaffold(
        message: 'Não foi possível verificar o Retoque Beauty.',
      ),
      data: (enabled) {
        if (!enabled) {
          return const _UnavailableScaffold(
            message:
                'Retoque Beauty ainda não está disponível para sua conta. '
                'Estamos liberando aos poucos — tente novamente em breve.',
          );
        }
        return child;
      },
    );
  }
}

class _UnavailableScaffold extends StatelessWidget {
  const _UnavailableScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Retoque Beauty')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_empty_rounded,
                size: 56,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
