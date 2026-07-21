import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../filter_presets/filter_grade_engine.dart';
import '../../filter_presets/filter_preset_mapper.dart';
import '../../filter_presets/filter_presets_provider.dart';
import '../di/beauty_engine_feature_flag_provider.dart';
import '../di/beauty_engine_providers.dart';
import '../l10n/beauty_engine_labels.dart';
import '../models/beauty_preset.dart';
import '../models/tune_params.dart';
import '../presets/bundled_presets.dart';
import 'widgets/beauty_accessible_slider.dart';

/// Criador de filtros custom (LUT + cor) — estilo Lightroom (Sprint 22).
class PresetCreatorPage extends ConsumerStatefulWidget {
  const PresetCreatorPage({super.key, this.editPresetId});

  final String? editPresetId;

  @override
  ConsumerState<PresetCreatorPage> createState() => _PresetCreatorPageState();
}

class _PresetCreatorPageState extends ConsumerState<PresetCreatorPage> {
  final _nameController = TextEditingController();
  final _uuid = const Uuid();

  String? _presetId;
  TuneParams _tune = const TuneParams();
  String? _lutAssetPath;
  double _lutIntensity = 1;

  Uint8List? _imageBytes;
  Uint8List? _previewBytes;
  bool _processing = false;
  bool _saving = false;
  bool _loaded = false;
  bool _isPublic = false;
  bool _syncing = false;
  Timer? _previewDebounce;

  final _gradeEngine = FilterGradeEngine();

  static final _lutOptions = BeautyEngineLabels.lutOptionsPt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExistingPreset());
  }

  Future<void> _loadExistingPreset() async {
    final editId = widget.editPresetId;
    if (editId == null) {
      setState(() => _loaded = true);
      return;
    }

    final preset = await ref.read(beautyPresetRepositoryProvider).findById(editId);
    if (!mounted) {
      return;
    }

    if (preset == null || BundledBeautyPresets.isBundled(preset.id)) {
      setState(() => _loaded = true);
      return;
    }

    _presetId = preset.id;
    _nameController.text = preset.name;
    _tune = preset.tune;
    _lutAssetPath = preset.lutAssetPath;
    _lutIntensity = preset.lutIntensity;
    _isPublic = preset.isPublic;

    if (preset.thumbnailPath != null) {
      final file = File(preset.thumbnailPath!);
      if (await file.exists()) {
        _previewBytes = await file.readAsBytes();
      }
    }

    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  BeautyPreset _buildDraft({String? id}) {
    return BeautyPreset(
      id: id ?? _presetId ?? 'user_${_uuid.v4()}',
      name: _nameController.text.trim().isEmpty
          ? 'Meu filtro'
          : _nameController.text.trim(),
      lutAssetPath: _lutAssetPath,
      lutIntensity: _lutIntensity,
      tune: _tune,
      version: 2,
      isPublic: _isPublic,
    );
  }

  Future<void> _syncNow() async {
    if (_syncing) {
      return;
    }

    final auth = ref.read(authStateProvider);
    if (!auth.isAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entre na conta para sincronizar filtros')),
        );
      }
      return;
    }

    setState(() => _syncing = true);
    try {
      await ref.read(beautyPresetRepositoryProvider).syncWithRemote();
      ref.invalidate(userBeautyPresetsProvider);
      ref.invalidate(allBeautyPresetsProvider);
      if (_presetId != null) {
        await _loadExistingPreset();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Filtros sincronizados')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sincronizar: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  Future<void> _togglePublic(bool value) async {
    if (_presetId == null) {
      setState(() => _isPublic = value);
      return;
    }

    try {
      final updated = await ref.read(beautyPresetRepositoryProvider).setPresetPublic(
            id: _presetId!,
            isPublic: value,
          );
      setState(() => _isPublic = updated.isPublic);
      ref.invalidate(userBeautyPresetsProvider);
      ref.invalidate(allBeautyPresetsProvider);
      ref.invalidate(marketplacePresetsProvider);
      ref.invalidate(filterPresetsProvider);
      ref.invalidate(manualEditorCustomFiltersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Filtro publicado no marketplace'
                  : 'Filtro removido do marketplace',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().contains('administradores')
            ? BeautyEngineLabels.marketplacePublishDenied
            : 'Erro ao publicar: $error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = image_picker.ImagePicker();
    final file = await picker.pickImage(source: image_picker.ImageSource.gallery);
    if (file == null) {
      return;
    }

    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _previewBytes = bytes;
    });
    await _runPreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        unawaited(_runPreview());
      }
    });
  }

  void _updateTune(TuneParams Function(TuneParams current) update) {
    setState(() => _tune = update(_tune));
    _schedulePreview();
  }

  Future<void> _runPreview() async {
    if (_imageBytes == null || _processing) {
      return;
    }

    setState(() => _processing = true);
    try {
      final tune = tuneParamsToFilterTune(_tune);
      final jpeg = await _gradeEngine.applyToJpeg(
        jpegBytes: _imageBytes!,
        lutAssetPath: _lutAssetPath,
        lutIntensity: _lutIntensity,
        tune: tune,
        quality: 85,
        maxPreviewDimension: 1280,
      );
      if (mounted) {
        setState(() => _previewBytes = jpeg);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no preview: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _savePreset() async {
    if (_saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      if (_imageBytes != null && !_processing) {
        await _runPreview();
      }

      final draft = _buildDraft(id: _presetId);
      final repository = ref.read(beautyPresetRepositoryProvider);

      BeautyPreset saved;
      if (_previewBytes != null && _previewBytes!.length > 20) {
        saved = await repository.savePresetWithThumbnail(
          preset: draft,
          previewJpegBytes: _previewBytes!,
        );
      } else {
        await repository.savePreset(draft);
        saved = draft;
      }

      _presetId = saved.id;
      ref.invalidate(userBeautyPresetsProvider);
      ref.invalidate(allBeautyPresetsProvider);
      ref.invalidate(filterPresetsProvider);
      ref.invalidate(manualEditorCustomFiltersProvider);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Filtro "${saved.name}" salvo')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _exportPreset() async {
    if (_presetId == null) {
      await _savePreset();
    }
    final id = _presetId;
    if (id == null) {
      return;
    }

    try {
      final preset = await ref.read(beautyPresetRepositoryProvider).findById(id);
      if (preset == null) {
        return;
      }
      await ref.read(presetFileServiceProvider).sharePresetJson(preset);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $error')),
        );
      }
    }
  }

  Future<void> _importPreset() async {
    try {
      final json = await ref.read(presetFileServiceProvider).pickPresetJson();
      if (json == null) {
        return;
      }

      final imported =
          await ref.read(beautyPresetRepositoryProvider).importPresetJson(json);
      ref.invalidate(userBeautyPresetsProvider);
      ref.invalidate(allBeautyPresetsProvider);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PresetCreatorPage(editPresetId: imported.id),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao importar: $error')),
        );
      }
    }
  }

  Future<void> _deletePreset() async {
    final id = _presetId;
    if (id == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir preset?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await ref.read(beautyPresetRepositoryProvider).deletePreset(id);
    ref.invalidate(userBeautyPresetsProvider);
    ref.invalidate(allBeautyPresetsProvider);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final canPublishAsync = ref.watch(canPublishBeautyPresetProvider);
    final adminOnlyAsync = ref.watch(beautyMarketplacePublishAdminOnlyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _presetId == null
              ? BeautyEngineLabels.filterCreatorTitle
              : 'Editar filtro',
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar nuvem',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: 'Importar JSON',
            onPressed: _importPreset,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          if (_presetId != null) ...[
            IconButton(
              tooltip: 'Exportar JSON',
              onPressed: _exportPreset,
              icon: const Icon(Icons.ios_share),
            ),
            IconButton(
              tooltip: 'Excluir',
              onPressed: _deletePreset,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          TextButton(
            onPressed: _saving ? null : _savePreset,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _PreviewCard(
              previewBytes: _previewBytes,
              processing: _processing,
              onPickImage: _pickImage,
              onRefreshPreview: _imageBytes == null ? null : _runPreview,
              compact: true,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    BeautyEngineLabels.filterCreatorPersonalUseBanner,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do filtro',
                    border: OutlineInputBorder(),
                  ),
                ),
                canPublishAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (canPublish) {
                    if (canPublish) {
                      final adminOnly = adminOnlyAsync.maybeWhen(
                        data: (value) => value,
                        orElse: () => false,
                      );
                      return Column(
                        children: [
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              BeautyEngineLabels.marketplacePublishTitle,
                            ),
                            subtitle: Text(
                              adminOnly
                                  ? BeautyEngineLabels
                                      .marketplacePublishSubtitleAdminOnly
                                  : BeautyEngineLabels
                                      .marketplacePublishSubtitleAll,
                            ),
                            value: _isPublic,
                            onChanged: (value) {
                              if (_presetId == null) {
                                setState(() => _isPublic = value);
                              } else {
                                _togglePublic(value);
                              }
                            },
                          ),
                        ],
                      );
                    }
                    final adminOnly = adminOnlyAsync.maybeWhen(
                      data: (value) => value,
                      orElse: () => false,
                    );
                    if (!adminOnly) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        BeautyEngineLabels.filterCreatorPublishAdminNote,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _Section(
                  title: BeautyEngineLabels.sectionLut,
                  children: [
                    DropdownButtonFormField<String?>(
                      value: _lutAssetPath,
                      decoration: const InputDecoration(
                        labelText: 'Filtro LUT',
                        border: OutlineInputBorder(),
                      ),
                      items: _lutOptions.entries
                          .map(
                            (entry) => DropdownMenuItem<String?>(
                              value: entry.value,
                              child: Text(entry.key),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _lutAssetPath = value);
                        _schedulePreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Intensidade LUT',
                      value: _lutIntensity,
                      onChanged: (value) {
                        setState(() => _lutIntensity = value);
                        _schedulePreview();
                      },
                    ),
                  ],
                ),
                _Section(
                  title: BeautyEngineLabels.sectionLight,
                  children: [
                    _TuneSlider(
                      label: 'Exposição',
                      value: _tune.exposure,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(exposure: v)),
                    ),
                    _TuneSlider(
                      label: 'Contraste',
                      value: _tune.contrast,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(contrast: v)),
                    ),
                    _TuneSlider(
                      label: 'Brilho',
                      value: _tune.brightness,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(brightness: v)),
                    ),
                    _TuneSlider(
                      label: 'Realces',
                      value: _tune.highlights,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(highlights: v)),
                    ),
                    _TuneSlider(
                      label: 'Sombras',
                      value: _tune.shadows,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(shadows: v)),
                    ),
                    _TuneSlider(
                      label: 'Brancos',
                      value: _tune.whites,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(whites: v)),
                    ),
                    _TuneSlider(
                      label: 'Pretos',
                      value: _tune.blacks,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(blacks: v)),
                    ),
                  ],
                ),
                _Section(
                  title: BeautyEngineLabels.sectionColor,
                  children: [
                    _TuneSlider(
                      label: 'Temperatura',
                      value: _tune.temperature,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(temperature: v)),
                    ),
                    _TuneSlider(
                      label: 'Matiz (tint)',
                      value: _tune.tint,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(tint: v)),
                    ),
                    _TuneSlider(
                      label: 'Vibrance',
                      value: _tune.vibrance,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(vibrance: v)),
                    ),
                    _TuneSlider(
                      label: 'Saturação',
                      value: _tune.saturation,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(saturation: v)),
                    ),
                    _TuneSlider(
                      label: 'Matiz (hue)',
                      value: _tune.hue,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(hue: v)),
                    ),
                  ],
                ),
                _Section(
                  title: BeautyEngineLabels.sectionEffect,
                  children: [
                    _TuneSlider(
                      label: 'Fade',
                      value: _tune.fade,
                      min: 0,
                      max: 1,
                      onChanged: (v) => _updateTune((t) => t.copyWith(fade: v)),
                    ),
                    _TuneSlider(
                      label: 'Nitidez',
                      value: _tune.sharpness,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(sharpness: v)),
                    ),
                    _TuneSlider(
                      label: 'Luminância',
                      value: _tune.luminance,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(luminance: v)),
                    ),
                    _TuneSlider(
                      label: 'Vinheta',
                      value: _tune.vignette,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(vignette: v)),
                    ),
                    _TuneSlider(
                      label: 'Gamma',
                      value: _tune.gamma,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) => _updateTune((t) => t.copyWith(gamma: v)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.previewBytes,
    required this.processing,
    required this.onPickImage,
    this.onRefreshPreview,
    this.compact = false,
  });

  final Uint8List? previewBytes;
  final bool processing;
  final VoidCallback onPickImage;
  final VoidCallback? onRefreshPreview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final preview = AspectRatio(
      aspectRatio: compact ? 16 / 9 : 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previewBytes == null)
            Center(
              child: TextButton.icon(
                onPressed: onPickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Foto para preview'),
              ),
            )
          else
            Image.memory(previewBytes!, fit: BoxFit.cover),
          if (processing)
            const ColoredBox(
              color: Color(0x44000000),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: preview,
            )
          else
            preview,
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onPickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Trocar foto'),
                ),
                if (onRefreshPreview != null)
                  TextButton.icon(
                    onPressed: processing ? null : onRefreshPreview,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Atualizar'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _TuneSlider extends StatelessWidget {
  const _TuneSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return BeautyAccessibleSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return BeautyAccessibleSlider(
      label: label,
      value: value,
      min: 0,
      max: 1,
      onChanged: onChanged,
    );
  }
}
