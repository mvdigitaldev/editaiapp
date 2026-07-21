import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../../../../core/theme/app_colors.dart';
import '../di/beauty_engine_providers.dart';
import '../filters/body/body_filter_pipeline.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/face/skin_filter_pipeline.dart';
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

  static const _labels = {
    'face_slim': 'Face Slim',
    'narrow_face': 'Narrow Face',
    'v_face': 'V Face',
    'nose_slim': 'Nose Slim',
    'nose_length': 'Nose Length',
    'nose_height': 'Nose Height',
    'nose_tip': 'Nose Tip',
    'nose_bridge': 'Nose Bridge',
    'eye_scale': 'Eye Scale',
    'eye_distance': 'Eye Distance',
    'eye_height': 'Eye Height',
    'eye_rotation': 'Eye Rotation',
    'double_eyelid': 'Double Eyelid',
    'jaw': 'Jaw',
    'chin': 'Chin',
    'head_size': 'Head Size',
    'cheekbone': 'Cheekbone',
    'forehead': 'Forehead',
    'temple': 'Temple',
    'mouth_width': 'Mouth Width',
    'lip_thickness': 'Lip Thickness',
    'smile': 'Smile',
    'skin_smooth': 'Skin Smooth',
    'skin_whitening': 'Skin Whitening',
    'remove_acne': 'Remove Acne',
    'remove_wrinkles': 'Remove Wrinkles',
    'remove_dark_circles': 'Dark Circles',
    'teeth_whitening': 'Teeth Whitening',
    'blush': 'Blush',
    'contour': 'Contour',
    'eyebrows': 'Eyebrows',
    'eyelashes': 'Eyelashes',
    'waist_slim': 'Waist Slim',
    'hip': 'Hip',
    'body_slim': 'Body Slim',
    'leg_length': 'Leg Length',
    'leg_slim': 'Leg Slim',
    'arm_slim': 'Arm Slim',
    'neck_slim': 'Neck Slim',
    'shoulder_width': 'Shoulder Width',
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
        title: const Text('Beauty Filters (dev)'),
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
                    title: const Text('Link Eyes (simetria L/R)'),
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
                      label: _labels[key] ?? key,
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
