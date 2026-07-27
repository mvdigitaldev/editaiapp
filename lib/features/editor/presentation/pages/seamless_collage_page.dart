import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/utils/seamless_blend_engine.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/multi_upload_area.dart';
import '../widgets/collage_layout_selector.dart';
import '../widgets/seamless_collage_preview.dart';

class SeamlessCollagePage extends StatefulWidget {
  const SeamlessCollagePage({super.key});

  @override
  State<SeamlessCollagePage> createState() => _SeamlessCollagePageState();
}

class _SeamlessCollagePageState extends State<SeamlessCollagePage> {
  static const _engine = SeamlessBlendEngine();

  List<String> _imagePaths = [];
  CollageLayout _layout = CollageLayout.vertical;
  double _fusionStrength = 0.5;
  bool _isExporting = false;
  int _collageRevision = 0;

  bool get _canExport =>
      _imagePaths.length >= SeamlessBlendEngine.minPhotos && !_isExporting;

  String get _previewKey =>
      '$_collageRevision|$_layout|${_imagePaths.join('\u0001')}';

  void _onImagesChanged(List<String> paths) {
    setState(() {
      _imagePaths = List<String>.from(paths);
      _collageRevision++;
    });
  }

  void _onLayoutChanged(CollageLayout layout) {
    setState(() => _layout = layout);
  }

  void _onFusionChanged(double value) {
    setState(() => _fusionStrength = value);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final updated = List<String>.from(_imagePaths);
      final item = updated.removeAt(oldIndex);
      updated.insert(newIndex, item);
      _imagePaths = updated;
      _collageRevision++;
    });
  }

  void _removeAt(int index) {
    setState(() {
      final updated = List<String>.from(_imagePaths)..removeAt(index);
      _imagePaths = updated;
      _collageRevision++;
    });
  }

  Future<void> _exportAndSave() async {
    if (!_canExport) return;
    setState(() => _isExporting = true);

    try {
      final file = await _engine.exportToFile(
        imagePaths: _imagePaths,
        config: SeamlessBlendConfig(
          layout: _layout,
          fusionStrength: _fusionStrength,
        ),
      );

      if (!mounted) return;

      final success = await saveLocalImageToGallery(file.path);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Colagem salva na galeria!'
                : 'Não foi possível salvar na galeria.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar colagem: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportAndShare() async {
    if (!_canExport) return;
    setState(() => _isExporting = true);

    try {
      final file = await _engine.exportToFile(
        imagePaths: _imagePaths,
        config: SeamlessBlendConfig(
          layout: _layout,
          fusionStrength: _fusionStrength,
        ),
      );

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Colagem criada no Editai',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao compartilhar: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Colagem sem emenda'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  flex: 11,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                        ),
                      ),
                      child: SeamlessCollagePreview(
                        key: ValueKey(_previewKey),
                        imagePaths: _imagePaths,
                        layout: _layout,
                        fusionStrength: _fusionStrength,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 13,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MultiUploadArea(
                          imagePaths: _imagePaths,
                          onChanged: _onImagesChanged,
                          maxCount: SeamlessBlendEngine.maxPhotos,
                        ),
                        if (_imagePaths.length >=
                            SeamlessBlendEngine.minPhotos) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Ordem das fotos',
                            style: AppTextStyles.labelLarge.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textLight
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PhotoOrderList(
                            imagePaths: _imagePaths,
                            layout: _layout,
                            onReorder: _onReorder,
                            onRemove: _removeAt,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Formato',
                          style: AppTextStyles.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textLight
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        CollageLayoutSelector(
                          layout: _layout,
                          onChanged: _onLayoutChanged,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              'Suavidade da emenda',
                              style: AppTextStyles.labelLarge.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${(_fusionStrength * 100).round()}%',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _fusionStrength,
                          min: 0,
                          max: 1,
                          divisions: 20,
                          label: '${(_fusionStrength * 100).round()}%',
                          onChanged: _onFusionChanged,
                        ),
                        const SizedBox(height: 8),
                        AppButton(
                          text: 'Salvar na galeria',
                          icon: Icons.save_alt,
                          onPressed: _canExport ? _exportAndSave : null,
                          isLoading: _isExporting,
                        ),
                        const SizedBox(height: 12),
                        AppButton(
                          text: 'Compartilhar',
                          icon: Icons.share_outlined,
                          isPrimary: false,
                          onPressed: _canExport ? _exportAndShare : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isExporting)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoOrderList extends StatelessWidget {
  const _PhotoOrderList({
    required this.imagePaths,
    required this.layout,
    required this.onReorder,
    required this.onRemove,
  });

  final List<String> imagePaths;
  final CollageLayout layout;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;

  String _positionLabel(int index) {
    if (layout == CollageLayout.vertical) {
      if (imagePaths.length == 2) {
        return index == 0 ? 'Cima' : 'Baixo';
      }
      if (index == 0) return 'Cima';
      if (index == imagePaths.length - 1) return 'Baixo';
      return 'Meio';
    }

    if (imagePaths.length == 2) {
      return index == 0 ? 'Esquerda' : 'Direita';
    }
    if (index == 0) return 'Esquerda';
    if (index == imagePaths.length - 1) return 'Direita';
    return 'Centro';
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: imagePaths.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final path = imagePaths[index];
        return Card(
          key: ValueKey(path),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(path),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            title: Text('Foto ${index + 1}'),
            subtitle: Text(_positionLabel(index)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => onRemove(index),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
