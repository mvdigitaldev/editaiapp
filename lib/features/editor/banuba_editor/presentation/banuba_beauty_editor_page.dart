import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/banuba_config.dart';
import '../../../../core/providers/app_remote_config_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../../manual_editor/di/manual_editor_providers.dart';
import '../../presentation/utils/edit_submission_helpers.dart';
import '../data/banuba_photo_editor_service.dart';

class BanubaBeautyEditorPage extends ConsumerStatefulWidget {
  const BanubaBeautyEditorPage({super.key});

  @override
  ConsumerState<BanubaBeautyEditorPage> createState() =>
      _BanubaBeautyEditorPageState();
}

class _BanubaBeautyEditorPageState
    extends ConsumerState<BanubaBeautyEditorPage> {
  final _editor = const BanubaPhotoEditorService();

  String? _selectedPath;
  bool _isOpening = false;
  bool _isSaving = false;

  Future<void> _pickFromCamera() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (image == null || !mounted) return;
    setState(() => _selectedPath = image.path);
  }

  Future<void> _openEditor() async {
    final sourcePath = _selectedPath;
    if (sourcePath == null || _isOpening || _isSaving) return;

    setState(() => _isOpening = true);

    // Reconsulta a cada abertura para aceitar troca do token sem novo deploy
    // e sem precisar reiniciar o aplicativo.
    ref.invalidate(banubaLicenseTokenProvider);
    final licenseToken = await ref.read(banubaLicenseTokenProvider.future);
    if (!mounted) return;
    if (!BanubaConfig.isConfigured(licenseToken)) {
      setState(() => _isOpening = false);
      _showMessage(
        'Licença Banuba não configurada. Atualize '
        '`banuba_license_token` em app_settings.',
      );
      return;
    }

    try {
      final originalBytes = await File(sourcePath).readAsBytes();
      if (!mounted) return;

      final outputPath = await _editor.editPhoto(
        licenseToken: licenseToken,
        sourcePath: sourcePath,
        useDarkTheme: Theme.of(context).brightness == Brightness.dark,
      );

      if (!mounted) return;
      if (outputPath == null) {
        setState(() => _isOpening = false);
        return;
      }

      setState(() {
        _isOpening = false;
        _isSaving = true;
      });

      final editedBytes = await File(outputPath).readAsBytes();
      final result =
          await ref.read(manualEditRepositoryProvider).saveEditedImage(
                editedJpeg: editedBytes,
                originalBytes: originalBytes,
                clientRequestId: const Uuid().v4(),
              );

      await trackAcceptedEdit(
        ref,
        editId: result.editId,
        operationType: 'manual_edit',
        status: 'completed',
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/comparison',
        (route) => route.settings.name == '/home' || route.isFirst,
        arguments: <String, dynamic>{
          'editId': result.editId,
          'before': sourcePath,
        },
      );
    } on BanubaEditorException catch (error) {
      if (!mounted) return;
      setState(() {
        _isOpening = false;
        _isSaving = false;
      });
      _showMessage(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isOpening = false;
        _isSaving = false;
      });
      _showMessage(_saveErrorMessage(error));
    }
  }

  String _saveErrorMessage(Object error) {
    final storageMessage = storageLimitMessageFromError(error);
    if (storageMessage != null) return storageMessage;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
    }
    return 'Não foi possível salvar a edição. Tente novamente.';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final limits = ref.watch(planLimitsProvider).valueOrNull;

    if (_isSaving) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Salvando na sua galeria...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Retoque beauty')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rosto, pele e maquiagem',
                style: AppTextStyles.headingSmall.copyWith(
                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Retoque sua foto com o editor profissional Banuba. '
                'A edição não consome créditos de IA.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color:
                      isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ),
              if (limits != null && !limits.canAddMore) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Armazenamento cheio (${limits.storedPhotosCount}/${limits.maxPhotos} fotos). '
                    'Exclua fotos da galeria antes de salvar uma nova edição.',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              UploadArea(
                imagePath: _selectedPath,
                title: 'Escolher foto',
                subtitle: 'Toque para selecionar da galeria',
                onImageSelected: (file) {
                  setState(() => _selectedPath = file.path);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isOpening ? null : _pickFromCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Usar câmera'),
              ),
              const Spacer(),
              AppButton(
                text: 'Abrir retoque beauty',
                icon: Icons.auto_fix_high,
                isLoading: _isOpening,
                onPressed: _selectedPath == null ? null : _openEditor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
