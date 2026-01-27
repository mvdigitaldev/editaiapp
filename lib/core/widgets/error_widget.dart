import 'package:flutter/material.dart';
import '../error/failures.dart';

class AppErrorWidget extends StatelessWidget {
  final Failure failure;
  final VoidCallback? onRetry;

  const AppErrorWidget({
    super.key,
    required this.failure,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final message = failure.when(
      server: (msg, _) => msg ?? 'Erro no servidor',
      network: (msg) => msg ?? 'Erro de conexão',
      storage: (msg) => msg ?? 'Erro de armazenamento',
      auth: (msg) => msg ?? 'Erro de autenticação',
      validation: (msg) => msg ?? 'Erro de validação',
      unknown: (msg) => msg ?? 'Erro desconhecido',
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
