import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/usecases/sign_up.dart';
import '../providers/auth_provider.dart';

class RegisterForm extends ConsumerStatefulWidget {
  const RegisterForm({super.key});

  @override
  ConsumerState<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não coincidem'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final signUp = ref.read(signUpProvider);
    final result = await signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
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
                auth: (msg) => msg ?? 'Erro ao criar conta',
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
        Navigator.of(context).pushReplacementNamed('/home');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Nome (opcional)',
            hint: 'Seu nome',
            controller: _nameController,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Email',
            hint: 'seu@email.com',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Senha',
            hint: '••••••••',
            controller: _passwordController,
            obscureText: _obscurePassword,
            validator: Validators.password,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Confirmar Senha',
            hint: '••••••••',
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            validator: (value) => Validators.password(value),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Cadastrar',
            onPressed: _handleRegister,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }
}
