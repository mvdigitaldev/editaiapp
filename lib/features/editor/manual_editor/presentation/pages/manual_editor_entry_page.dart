import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/upload_area.dart';
import '../../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../../../beauty_engine/di/beauty_engine_feature_flag_provider.dart';
import '../../../beauty_engine/l10n/beauty_engine_labels.dart';
import 'manual_editor_page.dart';

/// Entrada do editor manual — seleção de foto.
class ManualEditorEntryPage extends ConsumerStatefulWidget {
  const ManualEditorEntryPage({super.key});

  @override
  ConsumerState<ManualEditorEntryPage> createState() =>
      _ManualEditorEntryPageState();
}

class _ManualEditorEntryPageState extends ConsumerState<ManualEditorEntryPage> {
  String? _selectedPath;
  bool _isOpening = false;

  Future<void> _openEditor() async {
    if (_selectedPath == null || _isOpening) return;

    setState(() => _isOpening = true);
    final originalBytes = await File(_selectedPath!).readAsBytes();

    if (!mounted) return;
    setState(() => _isOpening = false);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ManualEditorPage(
          imagePath: _selectedPath!,
          originalBytes: originalBytes,
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (image == null) return;
    setState(() => _selectedPath = image.path);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final planLimitsAsync = ref.watch(planLimitsProvider);
    final beautyEnabledAsync = ref.watch(beautyEngineEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar manualmente'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajustes, filtros e recorte',
                style: AppTextStyles.headingSmall.copyWith(
                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Edite localmente no dispositivo. Ao concluir, a foto é salva '
                'automaticamente na sua galeria do app — sem usar créditos de IA.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color:
                      isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              beautyEnabledAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (enabled) {
                  if (!enabled) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ActionChip(
                      avatar: const Icon(Icons.storefront_outlined, size: 18),
                      label: Text(BeautyEngineLabels.manualEditorMarketplaceHint),
                      onPressed: () => Navigator.of(context)
                          .pushNamed('/beauty-preset-marketplace'),
                    ),
                  );
                },
              ),
              planLimitsAsync.when(
                data: (limits) {
                  if (limits.canAddMore) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Armazenamento cheio (${limits.storedPhotosCount}/${limits.maxPhotos} fotos). '
                      'Você pode editar, mas precisa excluir fotos na galeria para salvar.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
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
                onPressed: _pickFromCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Usar câmera'),
              ),
              const Spacer(),
              AppButton(
                text: 'Abrir editor',
                onPressed: _selectedPath == null ? null : _openEditor,
                isLoading: _isOpening,
                icon: Icons.brush_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
