import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/utils/validators.dart';
import '../account_required_page.dart';
import '../providers/auth_provider.dart';

class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final signIn = ref.read(signInProvider);
    final result = await signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.when(
                server: (msg, _) => msg ?? 'Erro no servidor',
                network: (msg) => msg ?? 'Erro de conexão',
                storage: (msg) => msg ?? 'Erro de armazenamento',
                auth: (msg) => msg ?? 'Email ou senha inválidos',
                validation: (msg) => msg ?? 'Erro de validação',
                unknown: (msg) => msg ?? 'Erro desconhecido',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      },
      (user) {
        ref.read(authStateProvider.notifier).setUser(user);
        completeSignIn(context);
      },
    );
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar Senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Digite seu email para receber um link de recuperação de senha.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'seu@email.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor, insira um email válido'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final email = emailController.text.trim();

    final resetPassword = ref.read(resetPasswordProvider);
    final resetResult = await resetPassword(email);

    if (!mounted) return;

    resetResult.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.when(
                server: (msg, _) => msg ?? 'Erro no servidor',
                network: (msg) => msg ?? 'Erro de conexão',
                storage: (msg) => msg ?? 'Erro de armazenamento',
                auth: (msg) => msg ?? 'Erro ao enviar email',
                validation: (msg) => msg ?? 'Erro de validação',
                unknown: (msg) => msg ?? 'Erro desconhecido',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      },
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email de recuperação enviado! Verifique sua caixa de entrada.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = BrandVisual.navy.withValues(alpha: 0.55);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LoginField(
            label: 'E-mail',
            hint: 'seu@email.com',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: Validators.email,
            prefixIcon: Icons.mail_outline_rounded,
          ),
          const SizedBox(height: 12),
          _LoginField(
            label: 'Senha',
            hint: 'Digite sua senha',
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            validator: Validators.password,
            prefixIcon: Icons.lock_outline_rounded,
            onFieldSubmitted: (_) => _handleLogin(),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: muted,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _handleForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: BrandVisual.blue,
                minimumSize: const Size(48, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Esqueci minha senha',
                style: BrandVisual.text(
                  size: 14,
                  weight: FontWeight.w600,
                  color: BrandVisual.blue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandVisual.blue,
                disabledBackgroundColor:
                    BrandVisual.blue.withValues(alpha: 0.7),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      children: [
                        const SizedBox(width: 40),
                        Expanded(
                          child: Text(
                            'Entrar',
                            textAlign: TextAlign.center,
                            style: BrandVisual.text(
                              size: 18,
                              weight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child:
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child:
                      Divider(color: BrandVisual.navy.withValues(alpha: 0.12))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Não tem uma conta?',
                  style: BrandVisual.text(size: 13, color: muted),
                ),
              ),
              Expanded(
                  child:
                      Divider(color: BrandVisual.navy.withValues(alpha: 0.12))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  '/register',
                  arguments: ModalRoute.of(context)?.settings.arguments,
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: BrandVisual.blue,
                side: const BorderSide(color: BrandVisual.blue, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Criar uma conta gratuita',
                      style: BrandVisual.text(
                        size: 16,
                        weight: FontWeight.w700,
                        color: BrandVisual.blue,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.suffixIcon,
    this.onFieldSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final muted = BrandVisual.navy.withValues(alpha: 0.45);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: BrandVisual.navy.withValues(alpha: 0.12)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: BrandVisual.text(
              size: 14,
              weight: FontWeight.w700,
              color: BrandVisual.navy,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          style: BrandVisual.text(size: 16, weight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: BrandVisual.text(size: 16, color: muted),
            filled: true,
            fillColor: const Color(0xFFF7F9FC),
            prefixIcon: Icon(prefixIcon, color: muted),
            suffixIcon: suffixIcon,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: BrandVisual.blue, width: 1.5),
            ),
            errorStyle:
                BrandVisual.text(size: 12, color: const Color(0xFFEF4444)),
          ),
        ),
      ],
    );
  }
}
