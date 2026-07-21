import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../../../../core/theme/app_colors.dart';
import '../di/beauty_engine_providers.dart';
import '../models/beauty_preset.dart';
import '../presets/bundled_presets.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/processing_pipeline.dart';

/// Editor Beauty MVP — aplica preset completo em 1 toque (Sprint 21).
class BeautyEditorPage extends ConsumerStatefulWidget {
  const BeautyEditorPage({super.key});

  @override
  ConsumerState<BeautyEditorPage> createState() => _BeautyEditorPageState();
}

class _BeautyEditorPageState extends ConsumerState<BeautyEditorPage> {
  Uint8List? _imageBytes;
  Uint8List? _previewBytes;
  ImageSource? _source;
  ImageSource? _fullResSource;
  String? _selectedPresetId;
  bool _processing = false;
  bool _showOriginal = false;
  int? _lastApplyMs;
  bool _prewarmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prewarmShaders());
  }

  Future<void> _prewarmShaders() async {
    if (_prewarmed) {
      return;
    }
    _prewarmed = true;
    try {
      await ref.read(shaderPrewarmServiceProvider).prewarm(
            ref.read(gpuRendererProvider),
          );
    } catch (_) {
      // Prewarm best-effort — não bloqueia editor.
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
    final source = ImageSource(
      bytes: bytes,
      width: decoded.width,
      height: decoded.height,
    );

    setState(() {
      _imageBytes = bytes;
      _previewBytes = bytes;
      _source = source;
      _fullResSource = source;
      _selectedPresetId = null;
      _lastApplyMs = null;
      _showOriginal = false;
    });
  }

  Future<void> _applyPreset(BeautyPreset preset) async {
    if (_source == null || _processing) {
      return;
    }

    setState(() {
      _processing = true;
      _selectedPresetId = preset.id;
      _showOriginal = false;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final controller = ref.read(beautyEngineControllerProvider);
      final previewSource = ImageSourceRgba.downscaleForPreview(_source!);

      final jpeg = await controller.exportJpeg(
        source: previewSource,
        pipeline: ProcessingPipeline(preset: preset),
        quality: 85,
      );

      stopwatch.stop();
      final profile = controller.profiler.snapshot();

      if (!mounted) {
        return;
      }
      setState(() {
        _previewBytes = jpeg;
        _lastApplyMs = profile.totalMs > 0 ? profile.totalMs : stopwatch.elapsedMilliseconds;
        _processing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('init_failed') ||
        text.contains('libmediapipe_tasks_vision_jni.so')) {
      return 'MediaPipe indisponível neste dispositivo.';
    }
    if (text.contains('detect_failed') || text.contains('image_decode_failed')) {
      return 'Não foi possível processar esta foto.';
    }
    return 'Erro ao aplicar preset: $error';
  }

  @override
  Widget build(BuildContext context) {
    final presetsAsync = ref.watch(allBeautyPresetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beauty Editor'),
        actions: [
          IconButton(
            tooltip: 'Marketplace',
            onPressed: () {
              Navigator.of(context).pushNamed('/beauty-preset-marketplace');
            },
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: 'Criar preset',
            onPressed: () {
              Navigator.of(context).pushNamed('/beauty-preset-creator');
            },
            icon: const Icon(Icons.tune),
          ),
          if (_imageBytes != null)
            IconButton(
              tooltip: _showOriginal ? 'Ver editada' : 'Ver original',
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              icon: Icon(_showOriginal ? Icons.auto_fix_high : Icons.compare),
            ),
          IconButton(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_previewBytes == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Selecione uma foto e toque em um preset para aplicar em 1 toque.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Center(
                        child: Image.memory(
                          _showOriginal ? _imageBytes! : _previewBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          key: ValueKey(
                            _showOriginal ? 'original' : 'preview_$_selectedPresetId',
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_processing)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.primary,
                    ),
                  ),
                if (_lastApplyMs != null && !_processing)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _ApplyTimeBadge(milliseconds: _lastApplyMs!),
                  ),
              ],
            ),
          ),
          presetsAsync.when(
            loading: () => const SizedBox(
              height: 96,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, _) => SizedBox(
              height: 96,
              child: Center(child: Text('Erro ao carregar presets: $error')),
            ),
            data: (presets) => _PresetStrip(
              presets: presets,
              selectedId: _selectedPresetId,
              enabled: _source != null && !_processing,
              onSelected: _applyPreset,
              onEditUserPreset: (preset) {
                Navigator.of(context).pushNamed(
                  '/beauty-preset-creator',
                  arguments: preset.id,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplyTimeBadge extends StatelessWidget {
  const _ApplyTimeBadge({required this.milliseconds});

  final int milliseconds;

  @override
  Widget build(BuildContext context) {
    final fast = milliseconds < 500;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fast ? AppColors.success.withValues(alpha: 0.9) : AppColors.warning.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          '${milliseconds}ms',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PresetStrip extends StatelessWidget {
  const _PresetStrip({
    required this.presets,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
    this.onEditUserPreset,
  });

  final List<BeautyPreset> presets;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<BeautyPreset> onSelected;
  final ValueChanged<BeautyPreset>? onEditUserPreset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = presets[index];
          final selected = preset.id == selectedId;
          final isUser = !BundledBeautyPresets.isBundled(preset.id);
          return _PresetChip(
            label: preset.name,
            selected: selected,
            enabled: enabled,
            isUser: isUser,
            thumbnailPath: preset.thumbnailPath,
            onTap: () => onSelected(preset),
            onLongPress: isUser ? () => onEditUserPreset?.call(preset) : null,
          );
        },
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.isUser = false,
    this.thumbnailPath,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool isUser;
  final String? thumbnailPath;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 92,
          height: 72,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.surfaceDarkSecondary : AppColors.surfaceLight),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (isUser
                      ? AppColors.success.withValues(alpha: 0.6)
                      : (isDark ? AppColors.borderDark : AppColors.border)),
              width: isUser ? 2 : 1,
            ),
            image: thumbnailPath != null
                ? DecorationImage(
                    image: FileImage(File(thumbnailPath!)),
                    fit: BoxFit.cover,
                    colorFilter: selected
                        ? ColorFilter.mode(
                            AppColors.primary.withValues(alpha: 0.35),
                            BlendMode.srcOver,
                          )
                        : null,
                  )
                : null,
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: selected
                    ? Colors.white
                    : (enabled
                        ? theme.colorScheme.onSurface
                        : theme.disabledColor),
                shadows: thumbnailPath != null
                    ? const [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black54,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
