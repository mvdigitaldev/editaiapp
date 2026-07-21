import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../di/beauty_engine_providers.dart';
import '../models/beauty_preset.dart';
import '../models/body_params.dart';
import '../models/face_params.dart';
import '../models/image_source.dart';
import 'widgets/beauty_accessible_slider.dart';
import '../models/image_source_rgba.dart';
import '../models/processing_pipeline.dart';
import '../models/skin_params.dart';
import '../models/tune_params.dart';
import '../presets/bundled_presets.dart';

/// Criador de presets custom — sliders + save/export/import (Sprint 22).
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
  FaceParams _face = const FaceParams();
  BodyParams _body = const BodyParams();
  SkinParams _skin = const SkinParams();
  String? _lutAssetPath;
  double _lutIntensity = 1;

  Uint8List? _imageBytes;
  Uint8List? _previewBytes;
  ImageSource? _source;
  bool _processing = false;
  bool _saving = false;
  bool _loaded = false;
  bool _isPublic = false;
  bool _syncing = false;

  static const _lutOptions = {
    'Nenhum': null,
    'Natural': 'assets/filters/lut/natural.png',
    'Cinema': 'assets/filters/lut/cinema_teal_orange.png',
  };

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
    _face = preset.face;
    _body = preset.body;
    _skin = preset.skin;
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
    _nameController.dispose();
    super.dispose();
  }

  BeautyPreset _buildDraft({String? id}) {
    return BeautyPreset(
      id: id ?? _presetId ?? 'user_${_uuid.v4()}',
      name: _nameController.text.trim().isEmpty
          ? 'Meu preset'
          : _nameController.text.trim(),
      lutAssetPath: _lutAssetPath,
      lutIntensity: _lutIntensity,
      tune: _tune,
      face: _face,
      body: _body,
      skin: _skin,
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
          const SnackBar(content: Text('Entre na conta para sincronizar presets')),
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
          const SnackBar(content: Text('Presets sincronizados')),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Preset publicado no marketplace'
                  : 'Preset removido do marketplace',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao publicar: $error')),
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
    final decoded = await decodeImageFromList(bytes);
    setState(() {
      _imageBytes = bytes;
      _previewBytes = bytes;
      _source = ImageSource(
        bytes: bytes,
        width: decoded.width,
        height: decoded.height,
      );
    });
    await _runPreview();
  }

  Future<void> _runPreview() async {
    if (_source == null || _processing) {
      return;
    }

    setState(() => _processing = true);
    try {
      final controller = ref.read(beautyEngineControllerProvider);
      final previewSource = ImageSourceRgba.downscaleForPreview(_source!);
      final jpeg = await controller.exportJpeg(
        source: previewSource,
        pipeline: ProcessingPipeline(preset: _buildDraft()),
        quality: 85,
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
      if (_source != null && !_processing) {
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

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "${saved.name}" salvo')),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_presetId == null ? 'Criar preset' : 'Editar preset'),
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PreviewCard(
                  previewBytes: _previewBytes,
                  processing: _processing,
                  onPickImage: _pickImage,
                  onRefreshPreview: _source == null ? null : _runPreview,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do preset',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publicar no marketplace'),
                  subtitle: const Text(
                    'Outros usuários logados poderão instalar uma cópia deste preset.',
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
                const SizedBox(height: 16),
                _Section(
                  title: 'LUT',
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
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Intensidade LUT',
                      value: _lutIntensity,
                      onChanged: (value) {
                        setState(() => _lutIntensity = value);
                        _runPreview();
                      },
                    ),
                  ],
                ),
                _Section(
                  title: 'Cor / Tune',
                  children: [
                    _SliderRow(
                      label: 'Brilho',
                      value: _tune.brightness,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) {
                        setState(() => _tune = TuneParams(
                              brightness: v,
                              contrast: _tune.contrast,
                              saturation: _tune.saturation,
                              exposure: _tune.exposure,
                              temperature: _tune.temperature,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Contraste',
                      value: _tune.contrast,
                      onChanged: (v) {
                        setState(() => _tune = TuneParams(
                              brightness: _tune.brightness,
                              contrast: v,
                              saturation: _tune.saturation,
                              exposure: _tune.exposure,
                              temperature: _tune.temperature,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Saturação',
                      value: _tune.saturation,
                      min: -0.5,
                      max: 0.5,
                      onChanged: (v) {
                        setState(() => _tune = TuneParams(
                              brightness: _tune.brightness,
                              contrast: _tune.contrast,
                              saturation: v,
                              exposure: _tune.exposure,
                              temperature: _tune.temperature,
                            ));
                        _runPreview();
                      },
                    ),
                  ],
                ),
                _Section(
                  title: 'Rosto',
                  children: [
                    _SliderRow(
                      label: 'Face slim',
                      value: _face.faceSlim,
                      onChanged: (v) {
                        setState(() => _face = FaceParams(
                              faceSlim: v,
                              noseSlim: _face.noseSlim,
                              eyeScale: _face.eyeScale,
                              cheekbone: _face.cheekbone,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Nose slim',
                      value: _face.noseSlim,
                      onChanged: (v) {
                        setState(() => _face = FaceParams(
                              faceSlim: _face.faceSlim,
                              noseSlim: v,
                              eyeScale: _face.eyeScale,
                              cheekbone: _face.cheekbone,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Eye scale',
                      value: _face.eyeScale,
                      onChanged: (v) {
                        setState(() => _face = FaceParams(
                              faceSlim: _face.faceSlim,
                              noseSlim: _face.noseSlim,
                              eyeScale: v,
                              cheekbone: _face.cheekbone,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Cheekbone',
                      value: _face.cheekbone,
                      onChanged: (v) {
                        setState(() => _face = FaceParams(
                              faceSlim: _face.faceSlim,
                              noseSlim: _face.noseSlim,
                              eyeScale: _face.eyeScale,
                              cheekbone: v,
                            ));
                        _runPreview();
                      },
                    ),
                  ],
                ),
                _Section(
                  title: 'Pele',
                  children: [
                    _SliderRow(
                      label: 'Skin smooth',
                      value: _skin.smooth,
                      onChanged: (v) {
                        setState(() => _skin = SkinParams(
                              smooth: v,
                              whitening: _skin.whitening,
                              blush: _skin.blush,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Whitening',
                      value: _skin.whitening,
                      onChanged: (v) {
                        setState(() => _skin = SkinParams(
                              smooth: _skin.smooth,
                              whitening: v,
                              blush: _skin.blush,
                            ));
                        _runPreview();
                      },
                    ),
                    _SliderRow(
                      label: 'Blush',
                      value: _skin.blush,
                      onChanged: (v) {
                        setState(() => _skin = SkinParams(
                              smooth: _skin.smooth,
                              whitening: _skin.whitening,
                              blush: v,
                            ));
                        _runPreview();
                      },
                    ),
                  ],
                ),
                _Section(
                  title: 'Corpo',
                  children: [
                    _SliderRow(
                      label: 'Waist slim',
                      value: _body.waistSlim,
                      onChanged: (v) {
                        setState(() => _body = BodyParams(waistSlim: v));
                        _runPreview();
                      },
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
  });

  final Uint8List? previewBytes;
  final bool processing;
  final VoidCallback onPickImage;
  final VoidCallback? onRefreshPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
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
          ),
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

class _SliderRow extends StatelessWidget {
  const _SliderRow({
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
