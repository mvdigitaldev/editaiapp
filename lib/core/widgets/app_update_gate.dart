import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

/// Avisa na Home quando a loja tem uma versão mais nova.
///
/// A comparação é toda do [upgrader]: a versão instalada contra a Play Store
/// ou a App Store. A tag `[:mav: x.y.z]` na descrição da loja torna o aviso
/// obrigatório (o pacote esconde o «Depois» e o voltar não fecha).
class AppUpdateGate extends StatelessWidget {
  AppUpdateGate({
    super.key,
    required this.child,
    Upgrader? upgrader,
  }) : upgrader = upgrader ?? appUpgrader;

  final Widget child;

  /// Injetável nos testes. Em produção usa [appUpgrader].
  final Upgrader upgrader;

  static final Upgrader appUpgrader = Upgrader(
    messages: UpgraderMessages(code: 'pt'),
    countryCode: 'BR',
    durationUntilAlertAgain: const Duration(days: 3),
    debugLogging: kDebugMode,
  );

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;

    return UpgradeAlert(
      upgrader: upgrader,
      showIgnore: false,
      dialogStyle: defaultTargetPlatform == TargetPlatform.iOS
          ? UpgradeDialogStyle.cupertino
          : UpgradeDialogStyle.material,
      // Obrigatório (abaixo do [:mav:]): o voltar não fecha. Opcional: fecha.
      shouldPopScope: () => !upgrader.blocked(),
      child: child,
    );
  }
}
