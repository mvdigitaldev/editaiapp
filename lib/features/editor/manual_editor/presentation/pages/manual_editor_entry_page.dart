import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/brand_visual.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/brand_blue_wash.dart';
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
    final onSurface = isDark ? Colors.white : BrandVisual.navy;
    final planLimitsAsync = ref.watch(planLimitsProvider);
    final beautyEnabledAsync = ref.watch(beautyEngineEnabledProvider);

    return Scaffold(
      backgroundColor: isDark ? BrandVisual.navy : Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        foregroundColor: onSurface,
        title: Text(
          'Editar manualmente',
          style: BrandVisual.title(size: 18, color: onSurface),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: BrandBlueWash(isDark: isDark)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, kToolbarHeight, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ajustes, filtros e recorte',
                    style: BrandVisual.title(size: 22, color: onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Edite localmente no dispositivo. Ao concluir, a foto é salva '
                    'automaticamente na sua galeria do app — sem usar créditos de IA.',
                    style: BrandVisual.text(
                      size: 15,
                      color: onSurface.withValues(alpha: 0.62),
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
                          avatar: const Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: BrandVisual.blue,
                          ),
                          backgroundColor: isDark
                              ? BrandVisual.blue.withValues(alpha: 0.16)
                              : Colors.white,
                          side: BorderSide(
                            color: BrandVisual.blue.withValues(alpha: 0.35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          label: Text(
                            BeautyEngineLabels.manualEditorMarketplaceHint,
                            style: BrandVisual.text(
                              size: 14,
                              weight: FontWeight.w600,
                              color: onSurface,
                            ),
                          ),
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
                          style: BrandVisual.text(size: 13, color: onSurface),
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BrandVisual.blue,
                      minimumSize: const Size.fromHeight(52),
                      side:
                          const BorderSide(color: BrandVisual.blue, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                      textStyle: BrandVisual.text(
                        size: 16,
                        weight: FontWeight.w600,
                        color: BrandVisual.blue,
                      ),
                    ),
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
        ],
      ),
    );
  }
}
