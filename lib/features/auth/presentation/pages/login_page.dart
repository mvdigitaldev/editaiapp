import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_visual.dart';
import '../widgets/login_form.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  /// Mantém o que foi digitado quando o teclado troca a coluna por rolagem.
  final _formKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final column = Column(
      mainAxisSize: keyboardOpen ? MainAxisSize.min : MainAxisSize.max,
      children: [
        const _LoginHeader(),
        if (keyboardOpen)
          const SizedBox(height: 16)
        else
          const Expanded(child: _BeforeAfterStrip()),
        LoginForm(key: _formKey),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: keyboardOpen
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: column,
                      ),
                    );
                  },
                )
              : column,
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    final muted = BrandVisual.navy.withValues(alpha: 0.62);
    final logoHeight = MediaQuery.sizeOf(context).height < 700 ? 92.0 : 140.0;

    return Column(
      children: [
        const SizedBox(height: 4),
        Semantics(
          label: 'Editaí',
          child: Image.asset(
            'assets/branding/logo_lockup.png',
            height: logoHeight,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Um novo olhar para suas fotos.',
          textAlign: TextAlign.center,
          style: BrandVisual.text(size: 15, color: muted),
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: BrandVisual.title(size: 26),
            children: [
              const TextSpan(text: 'Bem-vindo '),
              TextSpan(
                text: 'de volta!',
                style: BrandVisual.title(size: 26, color: BrandVisual.blue),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Entre na sua conta e continue\neditando suas fotos.',
          textAlign: TextAlign.center,
          style: BrandVisual.text(size: 15, color: muted),
        ),
      ],
    );
  }
}

class _BeforeAfterStrip extends StatelessWidget {
  const _BeforeAfterStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        label: 'Antes e depois',
        child: Image.asset(
          'assets/login/antes_depois.png',
          fit: BoxFit.contain,
          alignment: Alignment.center,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
