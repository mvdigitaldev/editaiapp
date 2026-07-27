import 'dart:async' show Timer, unawaited;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../../../../core/theme/app_colors.dart';
import '../di/beauty_engine_providers.dart';
import '../diagnostics/beauty_engine_error_reporter.dart';
import '../filters/body/body_filter_pipeline.dart';
import '../l10n/beauty_engine_labels.dart';
import '../models/face_mesh_result.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/pose_result.dart';
import '../models/processing_pipeline.dart';
import '../performance/adaptive_preview_policy.dart';
import '../segment/person_mask.dart';
import 'widgets/beauty_adjustments_panel.dart';

/// Editor de retoque beauty — ajustes manuais rosto/nariz/corpo/pele.
class BeautyEditorPage extends ConsumerStatefulWidget {
  const BeautyEditorPage({super.key});

  @override
  ConsumerState<BeautyEditorPage> createState() => _BeautyEditorPageState();
}

class _BeautyEditorPageState extends ConsumerState<BeautyEditorPage> {
  static final _errorReporter = BeautyEngineErrorReporter();

  Uint8List? _imageBytes;
  Uint8List? _previewBytes;
  ImageSource? _source;
  ImageSource? _previewSource;
  FaceMeshResult? _cachedFace;
  PoseResult? _cachedPose;
  PersonMask? _cachedPersonMask;
  bool _landmarksReady = false;
  bool _processing = false;
  bool _showOriginal = false;
  bool _linkEyes = true;
  int? _lastApplyMs;
  bool _prewarmed = false;
  Timer? _debounceTimer;
  bool _previewQueued = false;

  late Map<String, double> _params =
      BeautyAdjustmentsPanel.initialParams(linkEyes: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prewarmShaders());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
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

    final previewSource = ImageSourceRgba.downscaleForPreview(
      source,
      maxEdge: AdaptivePreviewPolicy.maxEdgeForBodyWarpPreview(source),
    );

    setState(() {
      _imageBytes = bytes;
      _previewBytes = bytes;
      _source = source;
      _previewSource = previewSource;
      _cachedFace = null;
      _cachedPose = null;
      _cachedPersonMask = null;
      _landmarksReady = false;
      _lastApplyMs = null;
      _showOriginal = false;
      _params = BeautyAdjustmentsPanel.initialParams(linkEyes: _linkEyes);
    });
    _schedulePreview();
  }

  void _onParamChanged(String key, double value) {
    setState(() => _params[key] = value);
    _schedulePreview();
  }

  void _onLinkEyesChanged(bool value) {
    setState(() {
      _linkEyes = value;
      _params['link_eyes'] = value ? 1 : 0;
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      Duration(milliseconds: _hasActiveBodyWarp(_params) ? 120 : 100),
      () {
      if (_source == null) {
        return;
      }
      if (_processing) {
        _previewQueued = true;
        return;
      }
      unawaited(_processPreview());
    });
  }

  Future<void> _ensureLandmarks() async {
    if (_landmarksReady || _previewSource == null) {
      return;
    }
    final controller = ref.read(beautyEngineControllerProvider);
    controller.faceLandmarkThrottle.reset();
    controller.poseLandmarkThrottle.reset();
    final face = await controller.detectFace(_previewSource!);
    final pose = await controller.detectPose(_previewSource!);
    final personMask = await controller.detectPersonMask(_previewSource!);
    _cachedFace = face;
    _cachedPose = pose;
    _cachedPersonMask = personMask;
    _landmarksReady = true;
  }

  Future<void> _processPreview() async {
    if (_source == null || _previewSource == null) {
      return;
    }

    setState(() => _processing = true);

    final stopwatch = Stopwatch()..start();

    try {
      final controller = ref.read(beautyEngineControllerProvider);
      final bodyActive = _hasActiveBodyWarp(_params);
      await _ensureLandmarks();

      final jpeg = await controller.exportJpeg(
        source: _previewSource!,
        pipeline: ProcessingPipeline(overrides: Map<String, double>.of(_params)),
        quality: bodyActive ? 82 : 85,
        face: _cachedFace,
        pose: _cachedPose,
        personMask: bodyActive ? _cachedPersonMask : null,
        interactivePreview: bodyActive,
      );

      stopwatch.stop();
      final profile = controller.profiler.snapshot();

      if (!mounted) {
        return;
      }

      final needsFace = _paramsNeedFaceOrSkin(_params);
      if (_cachedFace == null && needsFace) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(BeautyEngineLabels.faceNotDetectedHint),
            duration: Duration(seconds: 3),
          ),
        );
      }

      setState(() {
        _previewBytes = jpeg;
        _lastApplyMs =
            profile.totalMs > 0 ? profile.totalMs : stopwatch.elapsedMilliseconds;
        _showOriginal = false;
      });
    } catch (error, stackTrace) {
      unawaited(_errorReporter.report(
        error,
        context: 'adjustments_preview',
        stackTrace: stackTrace,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        if (_previewQueued) {
          _previewQueued = false;
          _schedulePreview();
        }
      } else {
        _processing = false;
        _previewQueued = false;
      }
    }
  }

  bool _hasActiveBodyWarp(Map<String, double> params) {
    for (final key in BodyFilterPipeline.bodyWarpParameterKeys) {
      if ((params[key] ?? 0) > 0.001) {
        return true;
      }
    }
    return false;
  }

  bool _paramsNeedFaceOrSkin(Map<String, double> params) {
    const faceAndSkinKeys = {
      'face_slim', 'narrow_face', 'v_face', 'nose_slim', 'nose_length',
      'nose_height', 'nose_tip', 'nose_bridge', 'eye_scale', 'eye_distance',
      'eye_height', 'eye_rotation', 'double_eyelid', 'jaw', 'chin',
      'cheekbone', 'forehead', 'temple', 'mouth_width', 'lip_thickness',
      'smile', 'head_size', 'skin_smooth', 'skin_whitening', 'remove_acne',
      'remove_wrinkles', 'remove_dark_circles', 'teeth_whitening', 'blush',
      'contour', 'eyebrows', 'eyelashes',
    };
    for (final key in faceAndSkinKeys) {
      if ((params[key] ?? 0) > 0) {
        return true;
      }
    }
    return false;
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
    return 'Erro ao aplicar ajuste: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(BeautyEngineLabels.beautyEditorTitle),
        actions: [
          if (_imageBytes != null)
            IconButton(
              tooltip: _showOriginal ? 'Ver editada' : 'Ver original',
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              icon: Icon(_showOriginal ? Icons.auto_fix_high : Icons.compare),
            ),
          IconButton(
            tooltip: 'Selecionar foto',
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
                        BeautyEngineLabels.beautyEditorEmptyHint,
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
                            _showOriginal ? 'original' : 'preview_${_params.hashCode}',
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
          BeautyAdjustmentsPanel(
            params: _params,
            enabled: _source != null && !_processing,
            linkEyes: _linkEyes,
            onParamChanged: _onParamChanged,
            onLinkEyesChanged: _onLinkEyesChanged,
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
    final fast = milliseconds < 250;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fast
            ? AppColors.success.withValues(alpha: 0.9)
            : AppColors.warning.withValues(alpha: 0.9),
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
