import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/loading_indicator.dart';
import '../../domain/usecases/apply_ai_effect.dart';
import '../providers/editor_provider.dart';

class EffectCard extends ConsumerWidget {
  final String effectType;
  final String title;
  final IconData icon;

  const EffectCard({
    super.key,
    required this.effectType,
    required this.title,
    required this.icon,
  });

  Future<void> _applyEffect(
    BuildContext context,
    WidgetRef ref,
    String photoId,
  ) async {
    final applyEffect = ref.read(applyAIEffectProvider);
    final result = await applyEffect(
      photoId: photoId,
      effectType: effectType,
    );

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.when(
                server: (msg, _) => msg ?? 'Erro ao aplicar efeito',
                network: (msg) => msg ?? 'Erro de conexão',
                storage: (msg) => msg ?? 'Erro de armazenamento',
                auth: (msg) => msg ?? 'Erro de autenticação',
                validation: (msg) => msg ?? 'Erro de validação',
                unknown: (msg) => msg ?? 'Erro desconhecido',
              ),
            ),
          ),
        );
      },
      (edit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Efeito aplicado! Processando...'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          // TODO: Implementar seleção de foto
          // _applyEffect(context, ref, photoId);
        },
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
