import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class UserDataPage extends ConsumerStatefulWidget {
  const UserDataPage({super.key});

  @override
  ConsumerState<UserDataPage> createState() => _UserDataPageState();
}

class _UserDataPageState extends ConsumerState<UserDataPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).user;
    _nameController = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _openChangePasswordBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChangePasswordBottomSheet(
        ref: ref,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Senha alterada com sucesso'),
              backgroundColor: Colors.green,
            ),
          );
        },
        onFailure: (message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (xfile == null || !mounted) return;
    final sourcePath = xfile.path;
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar foto',
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: 'Recortar foto',
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );
    if (croppedFile == null || !mounted) return;
    final ext = croppedFile.path.split('.').last;
    if (ext.isEmpty) return;
    final path = '${user.id}/avatar.$ext';
    try {
      final bytes = await File(croppedFile.path).readAsBytes();
      await Supabase.instance.client.storage
          .from(AppConfig.avatarsBucket)
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
      final url = Supabase.instance.client.storage
          .from(AppConfig.avatarsBucket)
          .getPublicUrl(path);
      final updateProfile = ref.read(updateProfileProvider);
      final result = await updateProfile(avatarUrl: url);
      if (!mounted) return;
      result.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failure.when(
                  server: (m, _) => m ?? 'Erro ao atualizar foto',
                  network: (m) => m ?? 'Erro de conexão',
                  storage: (m) => m ?? 'Erro de armazenamento',
                  auth: (m) => m ?? 'Erro ao atualizar foto',
                  validation: (m) => m ?? 'Erro de validação',
                  unknown: (m) => m ?? 'Erro desconhecido',
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
        },
        (updatedUser) {
          ref.read(authStateProvider.notifier).setUser(updatedUser);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Foto atualizada'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSavingProfile = true);
    final updateProfile = ref.read(updateProfileProvider);
    final result = await updateProfile(
      displayName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSavingProfile = false);
    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.when(
                server: (m, _) => m ?? 'Erro ao salvar',
                network: (m) => m ?? 'Erro de conexão',
                storage: (m) => m ?? 'Erro de armazenamento',
                auth: (m) => m ?? 'Erro ao salvar',
                validation: (m) => m ?? 'Erro de validação',
                unknown: (m) => m ?? 'Erro desconhecido',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      },
      (updatedUser) {
        ref.read(authStateProvider.notifier).setUser(updatedUser);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dados salvos'),
            backgroundColor: Colors.green,
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeleteAccountBottomSheet(
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleteAccount = ref.read(deleteAccountProvider);
    final signOut = ref.read(signOutProvider);
    final result = await deleteAccount();
    if (!mounted) return;
    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.when(
                server: (m, _) => m ?? 'Erro ao excluir conta',
                network: (m) => m ?? 'Erro de conexão',
                storage: (m) => m ?? 'Erro',
                auth: (m) => m ?? 'Erro ao excluir conta',
                validation: (m) => m ?? 'Erro',
                unknown: (m) => m ?? 'Erro desconhecido',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      },
      (_) async {
        await signOut();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      },
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('dd/MM/yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Meus dados',
          style: AppTextStyles.headingMedium.copyWith(
            color: isDark ? AppColors.textLight : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Perfil editável
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickAndUploadAvatar,
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.2),
                                  width: 2,
                                ),
                                image: user?.avatarUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(user!.avatarUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: user?.avatarUrl == null
                                  ? const Icon(Icons.person, size: 40)
                                  : const SizedBox.shrink(),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.backgroundDark
                                        : Colors.white,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: 'Nome',
                              hint: 'Seu nome',
                              controller: _nameController,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isSavingProfile ? null : _saveProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                              ),
                              child: _isSavingProfile
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text('Salvar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Informações da conta (somente leitura)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'INFORMAÇÕES DA CONTA',
                    style: AppTextStyles.overline.copyWith(
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      label: 'Email',
                      value: user?.email ?? '—',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Conta criada em',
                      value: _formatDate(user?.createdAt),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Plano atual',
                      value: (user?.subscriptionTier ?? 'Free').toUpperCase(),
                      isDark: isDark,
                    ),
                    if ((user?.subscriptionTier ?? 'Free').toLowerCase() != 'free') ...[
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Vencimento do plano',
                        value: _formatDate(
                          user?.subscriptionEndsAt ?? user?.trialEndsAt,
                        ),
                        isDark: isDark,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Créditos',
                      value: user?.creditsBalance?.toString() ?? '0',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Segurança (alterar senha)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Segurança',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton(
                      onPressed: _openChangePasswordBottomSheet,
                      child: const Text('Alterar senha'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Excluir conta (menos destaque)
              TextButton(
                onPressed: _confirmDeleteAccount,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Excluir conta',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChangePasswordBottomSheet extends StatefulWidget {
  final WidgetRef ref;
  final VoidCallback onSuccess;
  final void Function(String message) onFailure;

  const _ChangePasswordBottomSheet({
    required this.ref,
    required this.onSuccess,
    required this.onFailure,
  });

  @override
  State<_ChangePasswordBottomSheet> createState() =>
      _ChangePasswordBottomSheetState();
}

class _ChangePasswordBottomSheetState extends State<_ChangePasswordBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      if (mounted) {
        widget.onFailure('As senhas não coincidem');
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() => _isLoading = true);
    final result = await widget.ref.read(updatePasswordProvider)(
      _newPasswordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    result.fold(
      (failure) {
        Navigator.of(context).pop();
        widget.onFailure(
          failure.when(
            server: (m, _) => m ?? 'Erro ao alterar senha',
            network: (m) => m ?? 'Erro de conexão',
            storage: (m) => m ?? 'Erro',
            auth: (m) => m ?? 'Erro ao alterar senha',
            validation: (m) => m ?? 'Erro de validação',
            unknown: (m) => m ?? 'Erro desconhecido',
          ),
        );
      },
      (_) {
        Navigator.of(context).pop();
        widget.onSuccess();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDarkSecondary : Colors.white;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alterar senha',
              style: AppTextStyles.headingMedium.copyWith(
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            AppTextField(
              label: 'Nova senha',
              hint: '••••••••',
              controller: _newPasswordController,
              obscureText: _obscureNewPassword,
              validator: Validators.password,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Confirmar nova senha',
              hint: '••••••••',
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              validator: Validators.password,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: 'Alterar senha',
                    onPressed: _isLoading ? null : _submit,
                    isLoading: _isLoading,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountBottomSheet extends StatefulWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _DeleteAccountBottomSheet({
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_DeleteAccountBottomSheet> createState() =>
      _DeleteAccountBottomSheetState();
}

class _DeleteAccountBottomSheetState extends State<_DeleteAccountBottomSheet> {
  final _controller = TextEditingController();
  static const String _confirmWord = 'DELETAR';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canConfirm => _controller.text.trim() == _confirmWord;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDarkSecondary : Colors.white;
    final borderColor = isDark ? AppColors.borderDark : AppColors.border;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Excluir conta',
            style: AppTextStyles.headingMedium.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tem certeza? Todas as suas informações serão apagadas do banco de dados e esta ação não pode ser desfeita.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Para confirmar, digite $_confirmWord abaixo:',
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: _confirmWord,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              filled: true,
              fillColor: isDark ? AppColors.backgroundDarkSecondary : AppColors.backgroundLight,
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _canConfirm ? widget.onConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
