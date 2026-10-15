import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/widgets/brand_blue_wash.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/utils/seamless_blend_curve.dart';
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
  List<SeamlessPhotoPan> _photoPans = [];
  CollageAspectPreset _aspect = CollageAspectPreset.ratio16x9Portrait;
  double _fusionStrength = 0.5;
  bool _isExporting = false;

  bool get _canExport =>
      _imagePaths.length >= SeamlessBlendEngine.minPhotos && !_isExporting;

  List<SeamlessPhotoPan> get _alignedPans => [
        for (var i = 0; i < _imagePaths.length; i++)
          i < _photoPans.length ? _photoPans[i] : const SeamlessPhotoPan(),
      ];

  SeamlessBlendConfig get _config => SeamlessBlendConfig(
        aspect: _aspect,
        fusionStrength: _fusionStrength,
        photoPans: _alignedPans,
      );

  void _onImagesChanged(List<String> paths) {
    final previous = <String, SeamlessPhotoPan>{};
    for (var i = 0; i < _imagePaths.length; i++) {
      previous[_imagePaths[i]] =
          i < _photoPans.length ? _photoPans[i] : const SeamlessPhotoPan();
    }
    setState(() {
      _imagePaths = List<String>.from(paths);
      _photoPans = [
        for (final path in _imagePaths)
          previous[path] ?? const SeamlessPhotoPan(),
      ];
    });
  }

  void _onAspectChanged(CollageAspectPreset aspect) {
    setState(() => _aspect = aspect);
  }

  void _onFusionChanged(double value) {
    setState(() => _fusionStrength = value);
  }

  void _onPhotoPanChanged(int index, SeamlessPhotoPan pan) {
    final pans = _alignedPans;
    if (index < 0 || index >= pans.length) return;
    pans[index] = pan;
    _photoPans = pans;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final updated = List<String>.from(_imagePaths);
      final item = updated.removeAt(oldIndex);
      updated.insert(newIndex, item);
      final pans = List<SeamlessPhotoPan>.from(_alignedPans);
      final pan = pans.removeAt(oldIndex);
      pans.insert(newIndex, pan);
      _imagePaths = updated;
      _photoPans = pans;
    });
  }

  void _removeAt(int index) {
    setState(() {
      final pans = List<SeamlessPhotoPan>.from(_alignedPans)..removeAt(index);
      _imagePaths = List<String>.from(_imagePaths)..removeAt(index);
      _photoPans = pans;
    });
  }

  Future<void> _exportAndSave() async {
    if (!_canExport) return;
    setState(() => _isExporting = true);

    try {
      final file = await _engine.exportToFile(
        imagePaths: _imagePaths,
        config: _config,
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
        config: _config,
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
    final onSurface = isDark ? Colors.white : BrandVisual.navy;
    final horizontal = _aspect.isHorizontalStack;

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
          'Colagem sem emenda',
          style: BrandVisual.title(size: 18, color: onSurface),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: BrandBlueWash(isDark: isDark)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: kToolbarHeight),
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
                          imagePaths: _imagePaths,
                          aspect: _aspect,
                          fusionStrength: _fusionStrength,
                          photoPans: _alignedPans,
                          onPhotoPanChanged: _onPhotoPanChanged,
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
                              style: BrandVisual.title(
                                size: 16,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PhotoOrderList(
                              imagePaths: _imagePaths,
                              horizontal: horizontal,
                              onReorder: _onReorder,
                              onRemove: _removeAt,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Proporção',
                            style: BrandVisual.title(
                              size: 16,
                              color: onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          CollageAspectSelector(
                            aspect: _aspect,
                            onChanged: _onAspectChanged,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(
                                'Mesclagem',
                                style: BrandVisual.title(
                                  size: 16,
                                  color: onSurface,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _fusionStrength >= 0.98
                                    ? 'Fusão máxima'
                                    : '${(_fusionStrength * 100).round()}%',
                                style: BrandVisual.text(
                                  size: 14,
                                  weight: FontWeight.w800,
                                  color: BrandVisual.blue,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _fusionStrength,
                            min: 0,
                            max: 1,
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
    required this.horizontal,
    required this.onReorder,
    required this.onRemove,
  });

  final List<String> imagePaths;
  final bool horizontal;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;

  String _positionLabel(int index) {
    if (!horizontal) {
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
