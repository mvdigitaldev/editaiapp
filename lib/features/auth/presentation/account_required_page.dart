import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/shell_tab.dart';
import '../../../core/theme/brand_visual.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_button.dart';
import 'providers/auth_provider.dart';

class AccountRequiredArgs {
  const AccountRequiredArgs({this.forSave = false});

  final bool forSave;
}

/// Depois de entrar, abre [nextRoute]. Sem argumento, o login fica onde está.
class AuthFlowArgs {
  const AuthFlowArgs({this.nextRoute});

  final String? nextRoute;
}

void completeSignIn(BuildContext context) {
  final navigator = Navigator.of(context);
  final args = ModalRoute.of(context)?.settings.arguments;
  final next = args is AuthFlowArgs ? args.nextRoute : null;
  finishSignedInNavigation(context);
  if (next != null) {
    navigator.pushNamed(next);
  }
}

/// Fecha o formulário e o aviso. A foto por baixo permanece.
void finishSignedInNavigation(BuildContext context) {
  Navigator.of(context).popUntil((route) {
    final name = route.settings.name;
    return name != '/login' &&
        name != '/register' &&
        name != '/account-required';
  });
}

Future<void> openAiRoute(
  BuildContext context,
  WidgetRef ref,
  String route, {
  Object? arguments,
}) async {
  if (!ref.read(authStateProvider).isAuthenticated) {
    await Navigator.of(context).pushNamed('/account-required');
    return;
  }
  await Navigator.of(context).pushNamed(route, arguments: arguments);
}

bool isSignedIn(BuildContext context) {
  return ProviderScope.containerOf(context)
      .read(authStateProvider)
      .isAuthenticated;
}

class AccountRequiredPage extends ConsumerWidget {
  const AccountRequiredPage({super.key, this.forSave = false});

  final bool forSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = forSave
        ? 'Crie uma conta para guardar esta edição'
        : 'Crie uma conta para usar a edição com IA';
    final detail = forSave
        ? 'A foto fica aqui. Depois de entrar, grave de novo.'
        : 'Essa edição gasta créditos.';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: BrandVisual.navy,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: BrandVisual.title(size: 26)),
              const SizedBox(height: 12),
              Text(
                detail,
                style: BrandVisual.text(
                  color: BrandVisual.navy.withValues(alpha: 0.72),
                ),
              ),
              const Spacer(),
              AppButton(
                text: forSave ? 'Entrar' : 'Ir para o Perfil',
                onPressed: () {
                  if (forSave) {
                    Navigator.of(context).pushNamed('/login');
                    return;
                  }
                  ref.read(shellTabIndexProvider.notifier).state =
                      AppBottomNav.indexProfile;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
