import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../../../../core/theme/app_colors.dart';
import '../di/beauty_engine_providers.dart';
import '../filters/body/body_filter_pipeline.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/face/skin_filter_pipeline.dart';
import '../l10n/beauty_engine_labels.dart';
import '../models/image_source.dart';
import '../models/processing_pipeline.dart';
import 'widgets/beauty_accessible_slider.dart';

/// Tela dev-only para sliders dos filtros faciais e corporais (Sprint 10–20).
class FaceFiltersDemoPage extends ConsumerStatefulWidget {
  const FaceFiltersDemoPage({super.key});

  @override
  ConsumerState<FaceFiltersDemoPage> createState() => _FaceFiltersDemoPageState();
}

class _FaceFiltersDemoPageState extends ConsumerState<FaceFiltersDemoPage> {
  Uint8List? _imageBytes;
  Uint8List? _previewBytes;
  bool _processing = false;
  bool _linkEyes = true;

  final _params = <String, double>{
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) key: 0,
    for (final key in BodyFilterPipeline.bodyWarpParameterKeys) key: 0,
    for (final key in SkinFilterPipeline.skinParameterKeys) key: 0,
    'link_eyes': 1,
  };

  Iterable<String> get _allKeys => [
        ...FaceFilterPipeline.faceWarpParameterKeys,
        ...BodyFilterPipeline.bodyWarpParameterKeys,
        ...SkinFilterPipeline.skinParameterKeys,
      ];

  Future<void> _pickImage() async {
    final picker = image_picker.ImagePicker();
    final file = await picker.pickImage(
      source: image_picker.ImageSource.gallery,
    );
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _previewBytes = bytes;
    });
    await _processPreview();
  }

  Future<void> _processPreview() async {
    if (_imageBytes == null || _processing) {
      return;
    }

    setState(() => _processing = true);

    try {
      final controller = ref.read(beautyEngineControllerProvider);
      final decoded = await decodeImageFromList(_imageBytes!);
      final source = ImageSource(
        bytes: _imageBytes!,
        width: decoded.width,
        height: decoded.height,
      );

      final overrides = Map<String, double>.of(_params);
      overrides['link_eyes'] = _linkEyes ? 1 : 0;

      final jpeg = await controller.exportJpeg(
        source: source,
        pipeline: ProcessingPipeline(overrides: overrides),
        quality: 85,
      );

      if (!mounted) {
        return;
      }
      setState(() => _previewBytes = jpeg);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyProcessError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  String _friendlyProcessError(Object error) {
    final text = error.toString();
    if (text.contains('init_failed') ||
        text.contains('libmediapipe_tasks_vision_jni.so')) {
      return 'MediaPipe indisponível neste dispositivo. '
          'Use emulador ARM64 (não x86) ou celular físico, '
          'depois rode: flutter clean && flutter run';
    }
    if (text.contains('detect_failed')) {
      return 'Falha ao detectar rosto. Tente outra foto.';
    }
    if (text.contains('image_decode_failed')) {
      return 'Não foi possível decodificar a imagem. Tente outro formato (JPG/PNG).';
    }
    if (text.contains('RangeError')) {
      return 'Erro interno ao processar pixels. Atualize o app e tente novamente.';
    }
    return 'Erro ao processar: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(BeautyEngineLabels.faceFiltersDevTitle),
        actions: [
          IconButton(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _previewBytes == null
                  ? const Text('Selecione uma foto com rosto/corpo')
                  : Image.memory(_previewBytes!, fit: BoxFit.contain),
            ),
          ),
          if (_processing)
            const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
          Expanded(
            flex: 0,
            child: SizedBox(
              height: 360,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text(BeautyEngineLabels.linkEyesTitle),
                    value: _linkEyes,
                    onChanged: _imageBytes == null
                        ? null
                        : (value) {
                            setState(() => _linkEyes = value);
                            _processPreview();
                          },
                  ),
                  for (final key in _allKeys)
                    BeautyAccessibleSlider(
                      label: BeautyEngineLabels.parameterLabel(key),
                      value: _params[key] ?? 0,
                      enabled: _imageBytes != null,
                      onChanged: _imageBytes == null
                          ? null
                          : (value) {
                              setState(() => _params[key] = value);
                              _processPreview();
                            },
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
