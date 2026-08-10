import 'dart:async' show Timer, unawaited;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../manual_editor/di/manual_editor_providers.dart';
import '../../presentation/utils/edit_submission_helpers.dart';
import '../body_reshape/brush/brush_warp_field_builder.dart';
import '../body_reshape/models/warp_plan.dart';
import '../controllers/beauty_engine_controller.dart';
import '../di/face_warp_v3_rollout_provider.dart';
import '../di/beauty_engine_providers.dart';
import '../diagnostics/beauty_editor_session_reporter.dart';
import '../diagnostics/beauty_engine_error_reporter.dart';
import '../config/face_warp_v3_config.dart';
import '../config/face_warp_v3_rollout.dart';
import '../warp/anatomy/face_warp_vacancy_fill.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/body/body_filter_pipeline.dart';
import '../l10n/beauty_engine_labels.dart';
import '../models/beauty_image_loader.dart';
import '../models/face_mesh_result.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/multi_face_detection.dart';
import '../models/pose_result.dart';
import '../models/processing_pipeline.dart';
import '../performance/adaptive_preview_policy.dart';
import '../performance/device_capability.dart';
import '../segment/person_mask.dart';
import '../rendering/preview_image_decoder.dart';
import 'widgets/anatomy_debug_overlay.dart';
import 'widgets/beauty_adjustments_panel.dart';
import 'widgets/beauty_rgba_preview.dart';
import 'widgets/face_selection_overlay.dart';
import 'widgets/preview_coordinate_mapper.dart';
import 'widgets/parity_checklist_panel.dart';
import 'widgets/warp_debug_overlay.dart';

/// Editor de retoque beauty — ajustes manuais rosto/nariz/corpo/pele.
class BeautyEditorPage extends ConsumerStatefulWidget {
  const BeautyEditorPage({
    super.key,
    this.bodyOnly = false,
    this.labMode = false,
  });

  final bool bodyOnly;
  final bool labMode;

  @override
  ConsumerState<BeautyEditorPage> createState() => _BeautyEditorPageState();
}

class _BeautyEditorPageState extends ConsumerState<BeautyEditorPage> {
  static final _errorReporter = BeautyEngineErrorReporter();
  static final _sessionReporter = BeautyEditorSessionReporter();
  static const _coordMapper = PreviewCoordinateMapper();
  // Grade densa: o traço do pincel tem gradiente alto e uma grade grossa
  // faria o guard anti-dobra suavizar o traço até quase desaparecer.
  static const _brushBuilder =
      BrushWarpFieldBuilder(gridWidth: 128, gridHeight: 128);

  Uint8List? _imageBytes;
  ui.Image? _previewImage;
  int _previewImageGeneration = 0;
  String? _imagePath;
  ImageSource? _source;
  ImageSource? _previewSource;
  FaceMeshResult? _cachedFace;
  List<FaceMeshResult> _detectedFaces = const [];
  int _selectedFaceIndex = 0;
  PoseResult? _cachedPose;
  PersonMask? _cachedPersonMask;
  bool _landmarksReady = false;
  bool _processing = false;
  bool _saving = false;
  bool _showOriginal = false;
  bool _linkEyes = true;
  int? _lastApplyMs;
  bool _showWarpDebug = false;
  String? _debugActiveToolKey;
  DeviceCapabilityProfile? _deviceProfile;
  WarpPlan? _lastBodyWarpPlan;
  bool _prewarmed = false;
  Timer? _debounceTimer;
  Timer? _inpaintSettleTimer;
  bool _previewQueued = false;
  bool _pendingInpaintPass = false;
  static const _inpaintSettleMs = 150;
  static const _lateralFastPreviewMs = 50;

  // Pincel manual (Facetune-style).
  bool _brushMode = false;
  WarpBrushMode _brushTool = WarpBrushMode.push;
  double _brushRadius = 0.08;
  double _brushStrength = 0.65;
  final BrushStrokeHistory _brushHistory = BrushStrokeHistory();
  final List<Offset> _activeStrokePoints = [];
  final TransformationController _viewerTransform = TransformationController();
  final GlobalKey _previewImageKey = GlobalKey();

  late Map<String, double> _params =
      BeautyAdjustmentsPanel.initialParams(linkEyes: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prewarmShaders());
      unawaited(_resolveDeviceCapability());
      unawaited(_logEditorOpen());
    });
  }

  Future<void> _logEditorOpen() async {
    final snapshot = ref.read(faceWarpV3RolloutSnapshotProvider).valueOrNull;
    await _sessionReporter.logEvent(
      'editor_open',
      metadata: {
        'body_only': widget.bodyOnly,
        'lab_mode': widget.labMode,
        ...?snapshot?.toTelemetry(),
      },
    );
  }

  Future<void> _resolveDeviceCapability() async {
    final profile =
        await ref.read(deviceCapabilityManagerProvider).resolve();
    if (!mounted) {
      return;
    }
    ref.read(beautyEngineControllerProvider).deviceProfile = profile;
    setState(() => _deviceProfile = profile);
    unawaited(
      ref.read(hotPathRendererProvider).probeCapabilities(),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _inpaintSettleTimer?.cancel();
    _previewImage?.dispose();
    _viewerTransform.dispose();
    super.dispose();
  }

  void _disposePreviewImage() {
    _previewImage?.dispose();
    _previewImage = null;
  }

  Future<void> _loadInitialPreviewImage(ImageSource previewSource) async {
    final rgba = ImageSourceRgba.ensureRgba(previewSource);
    final generation = ++_previewImageGeneration;
    final image = await PreviewImageDecoder.fromRgba(
      rgba.bytes,
      rgba.width,
      rgba.height,
    );
    if (!mounted || generation != _previewImageGeneration) {
      image.dispose();
      return;
    }
    _disposePreviewImage();
    setState(() => _previewImage = image);
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
    final file =
        await picker.pickImage(source: image_picker.ImageSource.gallery);
    if (file == null) {
      return;
    }

    final bytes = await file.readAsBytes();
    // Normaliza EXIF/orientação e aplica o teto de resolução de entrada em
    // isolate — garante que UI, pipeline e detecção vejam os mesmos pixels.
    final source = await BeautyImageLoader.load(bytes);

    final profile = _deviceProfile ??
        await ref.read(deviceCapabilityManagerProvider).resolve();
    _deviceProfile ??= profile;
    ref.read(beautyEngineControllerProvider).deviceProfile = profile;

    final previewMaxEdge = widget.bodyOnly
        ? AdaptivePreviewPolicy.maxEdgeForBodyWarpPreviewWithProfile(
            source,
            profile,
          )
        : AdaptivePreviewPolicy.maxEdgeForSourceWithProfile(source, profile);

    final previewSource = ImageSourceRgba.downscaleForPreview(
      source,
      maxEdge: previewMaxEdge,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _imageBytes = source.bytes;
      _disposePreviewImage();
      _imagePath = file.path;
      _source = source;
      _previewSource = previewSource;
      _cachedFace = null;
      _detectedFaces = const [];
      _selectedFaceIndex = 0;
      _cachedPose = null;
      _cachedPersonMask = null;
      _landmarksReady = false;
      _lastApplyMs = null;
      _showOriginal = false;
      _params = BeautyAdjustmentsPanel.initialParams(linkEyes: _linkEyes);
      _brushHistory.clear();
      _activeStrokePoints.clear();
      _brushMode = false;
      _viewerTransform.value = Matrix4.identity();
    });
    ref.read(beautyEngineControllerProvider).manualBrushField = null;
    ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
    unawaited(_loadInitialPreviewImage(previewSource));
    _schedulePreview();
  }

  void _syncBrushFieldToController() {
    final controller = ref.read(beautyEngineControllerProvider);
    final preview = _previewSource;
    if (preview == null || _brushHistory.strokes.isEmpty) {
      controller.manualBrushField = null;
      return;
    }
    final size = Size(preview.width.toDouble(), preview.height.toDouble());
    controller.manualBrushField = _brushHistory.buildField(
      imageSize: size,
      builder: _brushBuilder,
    );
  }

  void _rebuildBrushForExport() {
    final controller = ref.read(beautyEngineControllerProvider);
    final source = _source;
    if (source == null || _brushHistory.strokes.isEmpty) {
      controller.manualBrushField = null;
      return;
    }
    // Traços em UV normalizado → reconstruir na resolução full.
    final size = Size(source.width.toDouble(), source.height.toDouble());
    controller.manualBrushField = _brushHistory.buildField(
      imageSize: size,
      builder: const BrushWarpFieldBuilder(gridWidth: 128, gridHeight: 128),
    );
  }

  Offset? _localToNormalized(Offset localInImageBox) {
    final box =
        _previewImageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    return _coordMapper.normalizedInImageBox(
      localPosition: localInImageBox,
      boxSize: box.size,
    );
  }

  void _onBrushStart(Offset local) {
    final uv = _localToNormalized(local);
    if (uv == null) {
      return;
    }
    setState(() {
      _activeStrokePoints
        ..clear()
        ..add(uv);
    });
  }

  void _onBrushUpdate(Offset local) {
    final uv = _localToNormalized(local);
    if (uv == null || _activeStrokePoints.isEmpty) {
      return;
    }
    final last = _activeStrokePoints.last;
    if ((uv - last).distance < 0.004) {
      return;
    }
    setState(() => _activeStrokePoints.add(uv));
  }

  void _onBrushEnd() {
    if (_activeStrokePoints.isEmpty) {
      return;
    }
    final points = List<Offset>.from(_activeStrokePoints);
    // Expand/pinch com um toque: duplicar ponto para o builder.
    if (points.length == 1 &&
        (_brushTool == WarpBrushMode.expand ||
            _brushTool == WarpBrushMode.pinch ||
            _brushTool == WarpBrushMode.restore)) {
      points.add(points.first);
    }
    if (points.length < 2 && _brushTool == WarpBrushMode.push) {
      _activeStrokePoints.clear();
      return;
    }
    _brushHistory.add(
      WarpStroke(
        points: points,
        radiusNormalized: _brushRadius,
        strength: _brushStrength,
        mode: _brushTool,
      ),
    );
    _activeStrokePoints.clear();
    _syncBrushFieldToController();
    _schedulePreview();
  }

  void _undoBrush() {
    if (!_brushHistory.canUndo) {
      return;
    }
    _brushHistory.undo();
    _syncBrushFieldToController();
    _schedulePreview();
    setState(() {});
  }

  void _onParamChanged(String key, double value) {
    setState(() {
      _params[key] = value;
      _debugActiveToolKey = key;
    });
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
    _inpaintSettleTimer?.cancel();
    if (_source == null) {
      return;
    }

    final faceSlimOnly = FaceWarpVacancyFill.isFaceSlimOnly(_params);
    final lateralInpaint =
        FaceWarpV3Config.usePostWarpInpaint &&
            FaceWarpVacancyFill.hasActiveLateralTool(_params) &&
            !faceSlimOnly;
    final profile = _deviceProfile;
    final debounceMs = faceSlimOnly
        ? (profile?.sliderDebounceMs ?? 100)
        : lateralInpaint
            ? _lateralFastPreviewMs
            : (profile?.sliderDebounceMs ??
                (_hasActiveBodyWarp(_params) ? 120 : 100));

    _debounceTimer = Timer(Duration(milliseconds: debounceMs), () {
      if (_processing) {
        _previewQueued = true;
        return;
      }
      unawaited(_processPreview(postWarpInpaint: faceSlimOnly));
    });

    if (lateralInpaint) {
      _inpaintSettleTimer = Timer(
        const Duration(milliseconds: _inpaintSettleMs),
        () {
          if (_processing) {
            _pendingInpaintPass = true;
            return;
          }
          unawaited(_processPreview(postWarpInpaint: true));
        },
      );
    }
  }

  Future<void> _ensureLandmarks() async {
    if (_landmarksReady || _previewSource == null) {
      return;
    }
    final controller = ref.read(beautyEngineControllerProvider);
    controller.faceLandmarkThrottle.reset();
    controller.poseLandmarkThrottle.reset();
    final faces = widget.bodyOnly
        ? <FaceMeshResult>[]
        : await controller.detectAllFaces(_previewSource!);
    final pose = await controller.detectPose(_previewSource!);
    final personMask = await controller.detectPersonMask(_previewSource!);
    _detectedFaces = faces;
    _selectedFaceIndex =
        faces.isEmpty ? 0 : MultiFaceDetection.indexOfLargest(faces);
    _cachedFace = faces.isEmpty ? null : faces[_selectedFaceIndex];
    _cachedPose = pose;
    _cachedPersonMask = personMask;
    if (_previewSource != null && !widget.bodyOnly && _cachedFace != null) {
      final faceParts = await controller.detectFaceParts(_previewSource!);
      await controller.assessImageQuality(
        source: _previewSource!,
        face: _cachedFace,
        faceParts: faceParts,
      );
    }
    _landmarksReady = true;
  }

  void _selectFace(int index) {
    if (index < 0 ||
        index >= _detectedFaces.length ||
        index == _selectedFaceIndex) {
      return;
    }
    setState(() {
      _selectedFaceIndex = index;
      _cachedFace = _detectedFaces[index];
    });
    ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
    unawaited(_reassessQualityForSelectedFace());
    _schedulePreview();
  }

  Future<void> _reassessQualityForSelectedFace() async {
    final source = _previewSource;
    final face = _cachedFace;
    if (source == null || face == null || widget.bodyOnly) {
      return;
    }
    final controller = ref.read(beautyEngineControllerProvider);
    final faceParts = await controller.detectFaceParts(source);
    await controller.assessImageQuality(
      source: source,
      face: face,
      faceParts: faceParts,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, double> _gatedParams(BeautyEngineController controller) {
    // Lab e pré-produção: sliders crus enquanto o V3 ainda está sendo calibrado.
    if (widget.labMode || FaceWarpV3Rollout.preProductionForceFull) {
      return Map<String, double>.of(_params);
    }
    return controller.applyToolGating(_params);
  }

  bool get _warpDebugAvailable => widget.labMode || kDebugMode;

  Future<void> _processPreview({bool postWarpInpaint = false}) async {
    if (_source == null || _previewSource == null) {
      return;
    }

    setState(() => _processing = true);

    final stopwatch = Stopwatch()..start();

    try {
      final controller = ref.read(beautyEngineControllerProvider);
      await _ensureLandmarks();

      final gated = _gatedParams(controller);
      final frame = await controller.renderPreview(
        source: _previewSource!,
        pipeline:
            ProcessingPipeline(overrides: Map<String, double>.of(gated)),
        face: _cachedFace,
        pose: _cachedPose,
        personMask: _cachedPersonMask,
        postWarpInpaint: postWarpInpaint,
      );

      final generation = ++_previewImageGeneration;
      final image = await PreviewImageDecoder.fromRgba(
        frame.bytes,
        frame.width,
        frame.height,
      );
      if (!mounted || generation != _previewImageGeneration) {
        image.dispose();
        return;
      }

      stopwatch.stop();
      final profile = controller.profiler.snapshot();
      // Benchmark por estágio (Sprint 0): agrega p50/p95 e loga a cada 20
      // frames — base de comparação para as migrações CPU→GPU.
      final benchmark = ref.read(beautyBenchmarkProvider);
      benchmark.record(profile);
      if (benchmark.sampleCount % 20 == 0) {
        benchmark.logSummary();
      }

      unawaited(
        _sessionReporter.logEvent(
          'preview_apply',
          metadata: {
            'face_count': _detectedFaces.length,
            'selected_face_index': _selectedFaceIndex,
            'apply_ms': profile.totalMs > 0
                ? profile.totalMs
                : stopwatch.elapsedMilliseconds,
          },
        ),
      );

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
        _previewImage?.dispose();
        _previewImage = image;
        _lastApplyMs = profile.totalMs > 0
            ? profile.totalMs
            : stopwatch.elapsedMilliseconds;
        _lastBodyWarpPlan = controller.lastBodyWarpPlan;
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
        if (_pendingInpaintPass) {
          _pendingInpaintPass = false;
          unawaited(_processPreview(postWarpInpaint: true));
        } else if (_previewQueued) {
          _previewQueued = false;
          _schedulePreview();
        }
      } else {
        _processing = false;
        _previewQueued = false;
        _pendingInpaintPass = false;
      }
    }
  }

  bool _hasActiveBodyWarp(Map<String, double> params) {
    if (_brushHistory.strokes.isNotEmpty) {
      return true;
    }
    for (final key in BodyFilterPipeline.bodyWarpParameterKeys) {
      if ((params[key] ?? 0) > 0.001) {
        return true;
      }
    }
    return false;
  }

  String? _firstActiveFaceWarpKey() {
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      if ((_params[key] ?? 0) > 0.001) {
        return key;
      }
    }
    return FaceFilterPipeline.faceWarpParameterKeys.first;
  }

  bool _paramsNeedFaceOrSkin(Map<String, double> params) {
    const faceAndSkinKeys = {
      'face_slim',
      'narrow_face',
      'v_face',
      'nose_slim',
      'nose_length',
      'nose_height',
      'nose_tip',
      'nose_bridge',
      'eye_scale',
      'eye_distance',
      'eye_height',
      'eye_rotation',
      'double_eyelid',
      'jaw',
      'chin',
      'cheekbone',
      'forehead',
      'temple',
      'mouth_width',
      'lip_thickness',
      'smile',
      'head_size',
      'skin_smooth',
      'skin_whitening',
      'remove_acne',
      'remove_wrinkles',
      'remove_dark_circles',
      'skin_shine',
      'teeth_whitening',
      'blush',
      'contour',
      'eyebrows',
      'eyelashes',
      'iris_enhance',
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
    if (text.contains('detect_failed') ||
        text.contains('image_decode_failed')) {
      return 'Não foi possível processar esta foto.';
    }
    return 'Erro ao aplicar ajuste: $error';
  }

  Future<void> _saveBodyEdit() async {
    final source = _source;
    final originalBytes = _imageBytes;
    final imagePath = _imagePath;
    if (source == null ||
        originalBytes == null ||
        imagePath == null ||
        _processing ||
        _saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      final controller = ref.read(beautyEngineControllerProvider);
      _rebuildBrushForExport();
      final editedBytes = await controller.exportJpeg(
        source: source,
        pipeline: ProcessingPipeline(
          overrides: Map<String, double>.of(_gatedParams(controller)),
        ),
        quality: 92,
      );
      // Restaura campo do pincel na resolução de preview.
      _syncBrushFieldToController();

      final result =
          await ref.read(manualEditRepositoryProvider).saveEditedImage(
                editedJpeg: editedBytes,
                originalBytes: originalBytes,
                clientRequestId: const Uuid().v4(),
              );

      await trackAcceptedEdit(
        ref,
        editId: result.editId,
        operationType: 'manual_edit',
        status: 'completed',
      );

      unawaited(
        _sessionReporter.logEvent(
          'export_save',
          metadata: {'body_only': widget.bodyOnly},
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/comparison',
        (route) => route.settings.name == '/home' || route.isFirst,
        arguments: <String, dynamic>{
          'editId': result.editId,
          'before': imagePath,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_saveErrorMessage(error))),
      );
    }
  }

  String _saveErrorMessage(Object error) {
    final storageMessage = storageLimitMessageFromError(error);
    if (storageMessage != null) return storageMessage;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
    }
    return 'Não foi possível salvar a edição. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(faceWarpV3RolloutAppliedProvider);

    if (_saving) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Salvando na sua galeria...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.bodyOnly
              ? 'Ajustar corpo'
              : BeautyEngineLabels.beautyEditorTitle,
        ),
        actions: [
          if (widget.bodyOnly && _imageBytes != null) ...[
            IconButton(
              tooltip: _brushMode ? 'Sliders' : 'Pincel',
              onPressed: () => setState(() {
                _brushMode = !_brushMode;
                if (!_brushMode) {
                  _activeStrokePoints.clear();
                }
              }),
              icon: Icon(
                _brushMode ? Icons.tune_rounded : Icons.brush_rounded,
              ),
            ),
            if (_brushHistory.canUndo)
              IconButton(
                tooltip: 'Desfazer pincel',
                onPressed: _processing ? null : _undoBrush,
                icon: const Icon(Icons.undo_rounded),
              ),
          ],
          if (_imageBytes != null)
            IconButton(
              tooltip: _showOriginal ? 'Ver editada' : 'Ver original',
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              icon: Icon(_showOriginal ? Icons.auto_fix_high : Icons.compare),
            ),
          if (widget.labMode && _imageBytes != null)
            IconButton(
              tooltip: FaceWarpV3Config.useDirectMeshRender
                  ? 'Malha direct (~2.5px) — toque para grade interativa'
                  : 'Grade interativa — toque para malha direct',
              onPressed: () {
                FaceWarpV3Config.toggleDirectMesh();
                ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
                setState(() {});
                _schedulePreview();
              },
              icon: Icon(
                FaceWarpV3Config.useDirectMeshRender
                    ? Icons.texture_outlined
                    : Icons.blur_linear,
                color: FaceWarpV3Config.useDirectMeshRender
                    ? AppColors.primary
                    : null,
              ),
            ),
          if (widget.labMode && _imageBytes != null)
            IconButton(
              tooltip: FaceWarpV3Config.useGpuPiecewiseAffine
                  ? 'GPU piecewise ON — toque para grade CPU'
                  : 'Grade CPU — toque para GPU piecewise',
              onPressed: () {
                FaceWarpV3Config.toggleGpuPiecewise();
                ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
                setState(() {});
                _schedulePreview();
              },
              icon: Icon(
                FaceWarpV3Config.useGpuPiecewiseAffine
                    ? Icons.memory_outlined
                    : Icons.memory,
                color: FaceWarpV3Config.useGpuPiecewiseAffine
                    ? AppColors.primary
                    : null,
              ),
            ),
          if (widget.labMode && _imageBytes != null)
            IconButton(
              tooltip: FaceWarpV3Config.usePostWarpInpaint
                  ? 'Inpaint pós-warp ON'
                  : 'Inpaint pós-warp OFF',
              onPressed: () {
                FaceWarpV3Config.togglePostWarpInpaint();
                ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
                setState(() {});
                _schedulePreview();
              },
              icon: Icon(
                FaceWarpV3Config.usePostWarpInpaint
                    ? Icons.healing_outlined
                    : Icons.healing,
                color: FaceWarpV3Config.usePostWarpInpaint
                    ? AppColors.primary
                    : null,
              ),
            ),
          if (widget.labMode && _imageBytes != null)
            IconButton(
              tooltip: FaceWarpV3Config.useGpuInpaint
                  ? 'Inpaint GPU ON'
                  : 'Inpaint CPU — toque para GPU',
              onPressed: () {
                FaceWarpV3Config.toggleGpuInpaint();
                ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
                setState(() {});
                _schedulePreview();
              },
              icon: Icon(
                FaceWarpV3Config.useGpuInpaint
                    ? Icons.speed_outlined
                    : Icons.speed,
                color: FaceWarpV3Config.useGpuInpaint
                    ? AppColors.primary
                    : null,
              ),
            ),
          if (widget.labMode && _imageBytes != null)
            IconButton(
              tooltip: FaceWarpV3Config.useMeshWarpV3
                  ? 'Warp V3 (malha) — toque para MLS'
                  : 'Warp MLS — toque para V3',
              onPressed: () {
                FaceWarpV3Config.toggle();
                ref.read(beautyEngineControllerProvider).invalidateRenderStageCache();
                setState(() {});
                _schedulePreview();
              },
              icon: Icon(
                FaceWarpV3Config.useMeshWarpV3
                    ? Icons.hub_outlined
                    : Icons.grid_4x4,
                color: FaceWarpV3Config.useMeshWarpV3
                    ? AppColors.primary
                    : null,
              ),
            ),
          if (widget.labMode && _imageBytes != null)
            IconButton(
              tooltip: FaceWarpV3Config.useNativePiecewiseExport
                  ? 'Export Metal nativo ON'
                  : 'Export FragmentProgram — toque para Metal',
              onPressed: () {
                FaceWarpV3Config.toggleNativePiecewiseExport();
                setState(() {});
              },
              icon: Icon(
                FaceWarpV3Config.useNativePiecewiseExport
                    ? Icons.apple_outlined
                    : Icons.apple,
                color: FaceWarpV3Config.useNativePiecewiseExport
                    ? AppColors.primary
                    : null,
              ),
            ),
          if (_warpDebugAvailable && _imageBytes != null)
            IconButton(
              tooltip: _showWarpDebug ? 'Ocultar máscara warp' : 'Máscara warp',
              onPressed: () => setState(() => _showWarpDebug = !_showWarpDebug),
              icon: Icon(
                _showWarpDebug ? Icons.grid_off : Icons.grid_on_outlined,
                color: _showWarpDebug ? AppColors.primary : null,
              ),
            ),
          IconButton(
            tooltip: 'Selecionar foto',
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          if (widget.bodyOnly && _imageBytes != null)
            IconButton(
              tooltip: 'Salvar edição',
              onPressed: _processing ? null : _saveBodyEdit,
              icon: const Icon(Icons.check_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_previewImage == null && _imageBytes == null)
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // A imagem fica num box do tamanho exato do fit, para
                        // que o toque do pincel mapeie 1:1 em UV.
                        final preview = _previewSource;
                        final fitted = preview == null
                            ? constraints.biggest
                            : _coordMapper.fittedImageSize(
                                imageSize: Size(
                                  preview.width.toDouble(),
                                  preview.height.toDouble(),
                                ),
                                viewportSize: constraints.biggest,
                              );
                        final image = SizedBox(
                          key: _previewImageKey,
                          width: fitted.width,
                          height: fitted.height,
                          child: _showOriginal
                              ? Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                  key: const ValueKey('original'),
                                )
                              : _previewImage == null
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : BeautyRgbaPreview(
                                      key: ValueKey(
                                        'preview_${_params.hashCode}_'
                                        '${_brushHistory.strokes.length}',
                                      ),
                                      image: _previewImage!,
                                      fit: BoxFit.fill,
                                    ),
                        );
                        return InteractiveViewer(
                          transformationController: _viewerTransform,
                          minScale: 0.5,
                          maxScale: 4,
                          panEnabled: !_brushMode,
                          scaleEnabled: !_brushMode,
                          child: Center(
                            child: _brushMode
                                ? GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart: (d) =>
                                        _onBrushStart(d.localPosition),
                                    onPanUpdate: (d) =>
                                        _onBrushUpdate(d.localPosition),
                                    onPanEnd: (_) => _onBrushEnd(),
                                    child: image,
                                  )
                                : Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      image,
                                      if (!widget.bodyOnly &&
                                          !_showOriginal &&
                                          _detectedFaces.length > 1 &&
                                          preview != null)
                                        FaceSelectionOverlay(
                                          faces: _detectedFaces,
                                          selectedIndex: _selectedFaceIndex,
                                          imageSize: Size(
                                            preview.width.toDouble(),
                                            preview.height.toDouble(),
                                          ),
                                          boxSize: fitted,
                                          onSelected: _selectFace,
                                        ),
                                      if (_warpDebugAvailable &&
                                          _showWarpDebug &&
                                          !_showOriginal &&
                                          preview != null)
                                        WarpDebugOverlay(
                                          field: ref
                                              .watch(beautyEngineControllerProvider)
                                              .lastFaceWarpField,
                                          vertexStats: ref
                                              .watch(beautyEngineControllerProvider)
                                              .lastFaceWarpDebugStats,
                                          boxSize: fitted,
                                        ),
                                      if (_warpDebugAvailable &&
                                          _showWarpDebug &&
                                          !_showOriginal &&
                                          preview != null &&
                                          _cachedFace != null)
                                        AnatomyDebugOverlay(
                                          face: _cachedFace!,
                                          imageSize: Size(
                                            preview.width.toDouble(),
                                            preview.height.toDouble(),
                                          ),
                                          boxSize: fitted,
                                          activeToolKey: _debugActiveToolKey ??
                                              _firstActiveFaceWarpKey(),
                                        ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                if (_detectedFaces.length > 1 &&
                    !widget.bodyOnly &&
                    !_processing &&
                    _previewImage != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          BeautyEngineLabels.multiFaceSelectHint(
                            _detectedFaces.length,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
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
                if (widget.labMode && _imageBytes != null && !_showOriginal)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: ParityChecklistPanel(params: _params),
                    ),
                  ),
                if (_lastApplyMs != null && !_processing)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _ApplyTimeBadge(
                      milliseconds: _lastApplyMs!,
                      budgetMs: _deviceProfile?.sliderToFrameBudgetMs ?? 250,
                      tier: _deviceProfile?.tier,
                      p50Ms: ref.read(beautyBenchmarkProvider).percentile('total', 50),
                      showBaseline: _warpDebugAvailable,
                      warpBackend: _warpDebugAvailable
                          ? ref
                              .watch(beautyEngineControllerProvider)
                              .lastFaceWarpBackend
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          if (_brushMode && widget.bodyOnly)
            _BrushToolbar(
              mode: _brushTool,
              radius: _brushRadius,
              strength: _brushStrength,
              onModeChanged: (m) => setState(() => _brushTool = m),
              onRadiusChanged: (v) => setState(() => _brushRadius = v),
              onStrengthChanged: (v) => setState(() => _brushStrength = v),
            )
          else ...[
            BeautyAdjustmentsPanel(
              params: _params,
              enabled: _source != null && !_processing,
              linkEyes: _linkEyes,
              bodyWarpPlan: _lastBodyWarpPlan,
              bodyOnly: widget.bodyOnly,
              labMode: widget.labMode,
              gatePlan: widget.labMode ||
                      FaceWarpV3Rollout.preProductionForceFull
                  ? null
                  : ref.watch(beautyEngineControllerProvider).lastToolGatePlan,
              onParamChanged: _onParamChanged,
              onLinkEyesChanged: _onLinkEyesChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _BrushToolbar extends StatelessWidget {
  const _BrushToolbar({
    required this.mode,
    required this.radius,
    required this.strength,
    required this.onModeChanged,
    required this.onRadiusChanged,
    required this.onStrengthChanged,
  });

  final WarpBrushMode mode;
  final double radius;
  final double strength;
  final ValueChanged<WarpBrushMode> onModeChanged;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<double> onStrengthChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const [
                      (WarpBrushMode.push, 'Empurrar', Icons.swipe_rounded),
                      (WarpBrushMode.pinch, 'Afinar', Icons.compress_rounded),
                      (WarpBrushMode.expand, 'Expandir', Icons.expand_rounded),
                      (WarpBrushMode.restore, 'Restaurar', Icons.history_rounded),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: mode == entry.$1,
                          label: Text(entry.$2),
                          avatar: Icon(entry.$3, size: 18),
                          onSelected: (_) => onModeChanged(entry.$1),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('Tamanho')),
                  Expanded(
                    child: Slider(
                      value: radius,
                      min: 0.03,
                      max: 0.2,
                      onChanged: onRadiusChanged,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('Força')),
                  Expanded(
                    child: Slider(
                      value: strength,
                      min: 0.15,
                      max: 1.0,
                      onChanged: onStrengthChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplyTimeBadge extends StatelessWidget {
  const _ApplyTimeBadge({
    required this.milliseconds,
    required this.budgetMs,
    this.tier,
    this.p50Ms = 0,
    this.showBaseline = false,
    this.warpBackend,
  });

  final int milliseconds;
  final int budgetMs;
  final DeviceTier? tier;
  final int p50Ms;
  final bool showBaseline;
  final String? warpBackend;

  String _tierLabel(DeviceTier tier) {
    return switch (tier) {
      DeviceTier.a => 'A',
      DeviceTier.b => 'B',
      DeviceTier.c => 'C',
    };
  }

  @override
  Widget build(BuildContext context) {
    final fast = milliseconds <= budgetMs;
    var label = '${milliseconds}ms';
    if (showBaseline && tier != null && p50Ms > 0) {
      label = '$label · p50 ${p50Ms}ms · tier ${_tierLabel(tier!)}';
    }
    if (warpBackend != null) {
      label = '$label · ${warpBackend!.toUpperCase()}';
    }
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
          label,
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
