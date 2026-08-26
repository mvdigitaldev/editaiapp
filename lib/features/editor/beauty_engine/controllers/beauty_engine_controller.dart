import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../body_reshape/maps/matte_preprocessor.dart';
import '../body_reshape/maps/person_mask_bridge.dart';
import '../body_reshape/models/body_frame_assets.dart';
import '../body_reshape/models/body_reshape_request.dart';
import '../body_reshape/models/legacy_body_parameter_adapter.dart';
import '../body_reshape/models/warp_plan.dart';
import '../body_reshape/occlusion/conservative_occlusion_provider.dart';
import '../body_reshape/occlusion/occlusion_engine.dart';
import '../body_reshape/passes/anti_folding_pass.dart';
import '../body_reshape/providers/body_vision_coordinator.dart';
import '../body_reshape/providers/mediapipe_body_joint_mapper.dart';
import '../body_reshape/providers/vision_capabilities.dart';
import '../filters/body/body_filter_pipeline.dart';
import '../filters/color/color_filter_pipeline.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/face/face_warp_utils.dart';
import '../filters/face/skin_filter_pipeline.dart';
import '../models/face_mesh_result.dart';
import '../face_mesh/face_mesh_detector.dart';
import '../mesh/mesh_engine.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/warp_field.dart';
import '../models/processed_frame.dart';
import '../models/processing_pipeline.dart';
import '../models/pose_result.dart';
import '../performance/beauty_profiler.dart';
import '../performance/device_capability.dart';
import '../performance/hot_path/hot_path_renderer.dart';
import '../presets/adaptive_preset_engine.dart';
import '../quality/face_quality_assessment.dart';
import '../quality/face_quality_context.dart';
import '../performance/landmark_throttle.dart';
import '../performance/tiled_export_engine.dart';
import '../pose/pose_detector.dart';
import '../rendering/gpu_renderer_impl.dart';
import '../rendering/render_stage_cache.dart';
import '../rendering/render_target.dart';
import '../rendering/texture_handle.dart';
import '../filters/face/mask_factory.dart';
import '../segment/face_parts_detector.dart';
import '../segment/face_parts_segmentation.dart';
import '../segment/face_parsing_detector.dart';
import '../segment/face_parsing_result.dart';
import '../segment/person_mask.dart';
import '../tools/tool_gate_decision.dart';
import '../tools/tool_gate_engine.dart';
import '../warp/anatomy/face_warp_debug_stats.dart';
import '../warp/warp_engine.dart';
import '../warp/v2/backward_bilinear_warp.dart' as v2;
import '../warp/v2/chin/chin_field.dart';
import '../warp/v2/jaw_field.dart';
import '../warp/v2/cheekbones/cheekbones_field.dart';

/// Orquestrador do Beauty Engine — ponto unico para a UI (sem Widget).
class BeautyEngineController {
  final FaceMeshDetector faceDetector;
  final PoseDetector poseDetector;
  final PersonMaskDetector? personMaskDetector;
  final FacePartsDetector? facePartsDetector;
  final FaceParsingDetector? faceParsingDetector;
  final BodyVisionCoordinator? bodyVisionCoordinator;
  final MeshEngine meshEngine;
  final WarpEngine warpEngine;
  final GPURenderer gpuRenderer;
  final FaceFilterPipeline faceFilterPipeline;
  final BodyFilterPipeline bodyFilterPipeline;
  final SkinFilterPipeline skinFilterPipeline;
  final ColorFilterPipeline colorFilterPipeline;
  final ToolGateEngine toolGateEngine;
  final AdaptivePresetEngine adaptivePresetEngine;
  final BeautyProfiler profiler;
  final LandmarkThrottle<FaceMeshResult?> faceLandmarkThrottle;
  final LandmarkThrottle<PoseResult?> poseLandmarkThrottle;
  final LandmarkThrottle<PersonMask?> personMaskThrottle;
  final TiledExportEngine tiledExportEngine;
  final OcclusionEngine occlusionEngine;
  final ConservativeOcclusionProvider conservativeOcclusionProvider;

  /// Toggles do pipeline multi-passe V2 (Sprint 10). Default = legado.
  BodyMultiPassConfig bodyMultiPassConfig;

  /// Último resultado multi-passe (telemetria / debug).
  BodyMultiPassResult? lastBodyMultiPassResult;

  /// Último plano semântico V2 (UI de limites / oclusão — Sprint 12).
  WarpPlan? lastBodyWarpPlan;

  final MediaPipeBodyJointMapper _poseJointMapper =
      const MediaPipeBodyJointMapper();
  final MattePreprocessor _mattePreprocessor = const MattePreprocessor();

  final RenderStageCache _renderStageCache = RenderStageCache();
  final MaskFactory maskFactory = MaskFactory();

  /// Quality Score + gating da foto atual (Sprint 3).
  FaceQualityContext? lastQualityContext;
  ToolGatePlan? lastToolGatePlan;

  /// Último face parsing 19 classes (Sprint 4).
  FaceParsingResult? lastFaceParsing;

  /// Última máscara 6 classes (pele).
  FacePartsSegmentation? lastFaceParts;

  /// Último campo warp facial (debug overlay no lab).
  WarpField? lastFaceWarpField;

  /// Backend do último warp facial (`v2_jaw` ou identidade).
  String? lastFaceWarpBackend;

  /// Debug de warp — vazio na V2 (JawField não emite stats de malha).
  FaceWarpDebugStats lastFaceWarpDebugStats = FaceWarpDebugStats.empty;

  /// Última person mask resolvida (corpo).
  PersonMask? lastPersonMask;

  /// Campo de pincel manual acumulado (coordenadas normalizadas → grade).
  WarpField? manualBrushField;

  /// Perfil de hardware (tier A/B/C) — definido pela UI após benchmark.
  DeviceCapabilityProfile? deviceProfile;

  /// Hot path FFI-ready (MethodChannel fallback até nativo expor FFI).
  HotPathRenderer? hotPathRenderer;

  BeautyEngineController({
    required this.faceDetector,
    required this.poseDetector,
    required this.meshEngine,
    required this.warpEngine,
    required this.gpuRenderer,
    this.personMaskDetector,
    this.facePartsDetector,
    this.faceParsingDetector,
    this.bodyVisionCoordinator,
    this.faceFilterPipeline = const FaceFilterPipeline(),
    this.bodyFilterPipeline = const BodyFilterPipeline(),
    this.skinFilterPipeline = const SkinFilterPipeline(),
    this.colorFilterPipeline = const ColorFilterPipeline(),
    this.toolGateEngine = const ToolGateEngine(),
    AdaptivePresetEngine? adaptivePresetEngine,
    this.occlusionEngine = const OcclusionEngine(),
    this.conservativeOcclusionProvider = const ConservativeOcclusionProvider(),
    this.bodyMultiPassConfig = BodyMultiPassConfig.legacy,
    BeautyProfiler? profiler,
    LandmarkThrottle<FaceMeshResult?>? faceLandmarkThrottle,
    LandmarkThrottle<PoseResult?>? poseLandmarkThrottle,
    LandmarkThrottle<PersonMask?>? personMaskThrottle,
    TiledExportEngine? tiledExportEngine,
  })  : adaptivePresetEngine =
            adaptivePresetEngine ?? AdaptivePresetEngine(),
        profiler = profiler ?? BeautyProfiler(),
        faceLandmarkThrottle =
            faceLandmarkThrottle ?? LandmarkThrottle<FaceMeshResult?>(),
        poseLandmarkThrottle =
            poseLandmarkThrottle ?? LandmarkThrottle<PoseResult?>(),
        personMaskThrottle = personMaskThrottle ??
            LandmarkThrottle<PersonMask?>(detectEveryNFrames: 1000000),
        tiledExportEngine = tiledExportEngine ?? TiledExportEngine();

  /// Processa imagem estatica com pipeline GPU (warp quando parametros presentes).
  Future<ProcessedFrame> process({
    required ImageSource source,
    required ProcessingPipeline pipeline,
  }) async {
    profiler.beginFrame();
    profiler.start('process_total');

    final face = await detectFace(source);
    final pose = await detectPose(source);
    final personMask = _shouldDetectPersonMask(pipeline.effectiveParameters)
        ? await detectPersonMask(source)
        : null;
    final faceParts = face != null &&
            _shouldDetectFaceParts(pipeline.effectiveParameters)
        ? await detectFaceParts(source)
        : null;
    final faceParsing = face != null &&
            skinFilterPipeline.hasActiveSkin(pipeline.effectiveParameters)
        ? await detectFaceParsing(
            source,
            face: face,
            parts: faceParts,
          )
        : null;
    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: face,
      pose: pose,
      personMask: personMask,
      faceParts: faceParts,
      faceParsing: faceParsing,
    );

    final bytes = await gpuRenderer.readPixels(output);
    gpuRenderer.release(output);

    profiler.end('process_total');

    return ProcessedFrame(
      bytes: bytes.isEmpty ? source.bytes : bytes,
      width: source.width,
      height: source.height,
      face: face,
      pose: pose,
    );
  }

  /// Preview interativo: pipeline GPU → RGBA, sem encode JPEG.
  ///
  /// [postWarpInpaint] — quando false (padrão), preview rápido sem inpaint CPU;
  /// true após debounce do slider para limpar faixas fantasma em warps laterais.
  Future<ProcessedFrame> renderPreview({
    required ImageSource source,
    required ProcessingPipeline pipeline,
    FaceMeshResult? face,
    PoseResult? pose,
    PersonMask? personMask,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    bool postWarpInpaint = false,
  }) async {
    profiler.beginFrame();
    profiler.start('render_preview');

    final inputs = await _resolveRenderInputs(
      source: source,
      pipeline: pipeline,
      face: face,
      pose: pose,
      personMask: personMask,
      faceParts: faceParts,
      faceParsing: faceParsing,
    );
    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: inputs.face,
      pose: inputs.pose,
      personMask: inputs.personMask,
      faceParts: inputs.faceParts,
      faceParsing: inputs.faceParsing,
      interactivePreview: true,
      postWarpInpaint: postWarpInpaint,
    );

    final rgba = await gpuRenderer.readPixels(output);
    gpuRenderer.release(output);
    profiler.end('render_preview');

    return ProcessedFrame(
      bytes: rgba,
      width: output.width,
      height: output.height,
      face: inputs.face,
      pose: inputs.pose,
    );
  }

  /// Exporta JPEG; usa tiles automaticamente acima de 8MP (Sprint 25).
  Future<Uint8List> exportJpeg({
    required ImageSource source,
    required ProcessingPipeline pipeline,
    int quality = 90,
    bool forceTiledExport = false,
    FaceMeshResult? face,
    PoseResult? pose,
    PersonMask? personMask,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    bool interactivePreview = false,
  }) async {
    profiler.beginFrame();

    if (!interactivePreview &&
        (forceTiledExport ||
            tiledExportEngine.shouldUseTiledExport(
              ImageSourceRgba.ensureRgba(source),
            ))) {
      return tiledExportEngine.exportJpeg(
        controller: this,
        source: source,
        pipeline: pipeline,
        quality: quality,
        profiler: profiler,
      );
    }

    profiler.start('export_total');
    final inputs = await _resolveRenderInputs(
      source: source,
      pipeline: pipeline,
      face: face,
      pose: pose,
      personMask: personMask,
      faceParts: faceParts,
      faceParsing: faceParsing,
    );
    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: inputs.face,
      pose: inputs.pose,
      personMask: inputs.personMask,
      faceParts: inputs.faceParts,
      faceParsing: inputs.faceParsing,
      interactivePreview: interactivePreview,
    );

    final jpeg = await gpuRenderer.exportJpeg(output, quality: quality);
    gpuRenderer.release(output);
    profiler.end('export_total');
    return jpeg;
  }

  Future<_RenderInputs> _resolveRenderInputs({
    required ImageSource source,
    required ProcessingPipeline pipeline,
    FaceMeshResult? face,
    PoseResult? pose,
    PersonMask? personMask,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
  }) async {
    final params = pipeline.effectiveParameters;
    final resolvedFace = face ?? await detectFace(source);
    final resolvedPose = pose ?? await detectPose(source);
    final resolvedMask = personMask ??
        (_shouldDetectPersonMask(params)
            ? await detectPersonMask(source)
            : null);
    final resolvedFaceParts = faceParts ??
        (resolvedFace != null && _shouldDetectFaceParts(params)
            ? await detectFaceParts(source)
            : null);
    final resolvedFaceParsing = faceParsing ??
        (resolvedFace != null &&
                skinFilterPipeline.needsSemanticParsing(params)
            ? await detectFaceParsing(
                source,
                face: resolvedFace,
                parts: resolvedFaceParts,
              )
            : null);
    lastPersonMask = resolvedMask;
    return _RenderInputs(
      face: resolvedFace,
      pose: resolvedPose,
      personMask: resolvedMask,
      faceParts: resolvedFaceParts,
      faceParsing: resolvedFaceParsing,
    );
  }

  Future<FaceMeshResult?> detectFace(ImageSource source) {
    return faceLandmarkThrottle.resolve(() => faceDetector.detect(source));
  }

  Future<List<FaceMeshResult>> detectAllFaces(ImageSource source) {
    return faceDetector.detectAll(source);
  }

  Future<PoseResult?> detectPose(ImageSource source) {
    return poseLandmarkThrottle.resolve(() => poseDetector.detect(source));
  }

  Future<PersonMask?> detectPersonMask(ImageSource source) async {
    final detector = personMaskDetector;
    if (detector == null) {
      lastPersonMask = null;
      return null;
    }
    try {
      final mask = await personMaskThrottle.resolve(
        () => detector.detect(source),
      );
      lastPersonMask = mask;
      return mask;
    } catch (_) {
      lastPersonMask = null;
      return null;
    }
  }

  bool _shouldDetectPersonMask(Map<String, double> parameters) {
    return bodyFilterPipeline.hasActiveBodyWarp(parameters);
  }

  bool _shouldDetectFaceParts(Map<String, double> parameters) {
    return skinFilterPipeline.hasActiveSkin(parameters);
  }


  /// Segmentação semântica de partes para a máscara de pele. Falha volta
  /// `null` e a pele usa o fallback geométrico dos landmarks.
  Future<FacePartsSegmentation?> detectFaceParts(ImageSource source) async {
    final detector = facePartsDetector;
    if (detector == null) {
      lastFaceParts = null;
      return null;
    }
    try {
      final mask = await detector.detect(source);
      lastFaceParts = mask;
      return mask;
    } catch (_) {
      lastFaceParts = null;
      return null;
    }
  }

  /// Face parsing 19 classes — BiSeNet nativo ou mapper multiclass + landmarks.
  Future<FaceParsingResult?> detectFaceParsing(
    ImageSource source, {
    FaceMeshResult? face,
    FacePartsSegmentation? parts,
  }) async {
    final resolvedFace = face ?? await detectFace(source);
    if (resolvedFace == null) {
      lastFaceParsing = null;
      return null;
    }

    try {
      final detector = faceParsingDetector;
      final FaceParsingResult? result;
      if (detector != null) {
        result = await detector.detect(
          source: source,
          face: resolvedFace,
          parts: parts ?? await detectFaceParts(source),
        );
      } else {
        result = await const FaceParsingDetectorStub().detect(
          source: source,
          face: resolvedFace,
          parts: parts,
        );
      }
      lastFaceParsing = result;
      return result;
    } catch (_) {
      lastFaceParsing = null;
      return null;
    }
  }

  /// Capacidades agregadas dos providers V2 (pose/matte/partes/oclusão/fundo).
  VisionCapabilities get bodyVisionCapabilities =>
      bodyVisionCoordinator?.capabilities ?? VisionCapabilities.none;

  /// Carrega assets semânticos sem acoplar o Warp Engine a um SDK específico.
  ///
  /// Quando não há mapa de oclusão do provider, infere oclusão conservadora
  /// (mãos/braços/cabelo) a partir da pose/partes.
  Future<BodyFrameAssets?> loadBodyFrameAssets(ImageSource source) async {
    final coordinator = bodyVisionCoordinator;
    if (coordinator == null) {
      return null;
    }
    try {
      final assets = await coordinator.load(source);
      if (assets == null) {
        return null;
      }
      if (assets.occlusionMap != null && !assets.occlusionMap!.isEmpty) {
        return assets;
      }
      final inferred = conservativeOcclusionProvider.inferFromAssets(
        assets,
        imageSize: Size(source.width.toDouble(), source.height.toDouble()),
      );
      if (inferred == null) {
        return assets;
      }
      return assets.copyWith(
        occlusionMap: inferred.map,
        capabilities: assets.capabilities.merge(
          const VisionCapabilities(occlusionMap: true),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Plano V2 com gate de capacidades + oclusão; não altera o remap legado.
  WarpPlan createBodyReshapePlan({
    required Size imageSize,
    required Map<String, double> parameters,
    bool interactive = false,
    VisionCapabilities? capabilities,
    BodyFrameAssets? assets,
  }) {
    var plan = bodyFilterPipeline.createReshapePlan(
      imageSize: imageSize,
      parameters: parameters,
      interactive: interactive,
      capabilities: capabilities ??
          assets?.capabilities ??
          bodyVisionCapabilities,
    );
    if (assets != null) {
      plan = occlusionEngine.applyToPlan(plan: plan, assets: assets);
    }
    lastBodyWarpPlan = plan;
    return plan;
  }

  /// Assets a partir da pose (rápido) ou do coordinator (matte/oclusão).
  ///
  /// Quando [personMask] está disponível, anexa [PersonMatte] e (se possível)
  /// oclusão conservadora — necessário para o path V2 guiado por contorno.
  BodyFrameAssets? resolveBodyFrameAssets({
    required PoseResult? pose,
    ImageSource? source,
    PersonMask? personMask,
    Size? imageSize,
  }) {
    BodyFrameAssets? assets;
    if (pose != null) {
      assets = _poseJointMapper.fromPoseResult(pose);
    }
    if (assets == null) {
      return null;
    }

    final size = imageSize ??
        (source != null
            ? Size(source.width.toDouble(), source.height.toDouble())
            : null);

    if (personMask != null &&
        personMask.width > 0 &&
        personMask.height > 0 &&
        (assets.personMatte == null || assets.personMatte!.isEmpty)) {
      assets = assets.copyWith(
        personMatte: personMask.toPersonMatte(),
        capabilities: assets.capabilities.merge(
          const VisionCapabilities(personMatte: true),
        ),
      );
    }

    if (size != null &&
        (assets.occlusionMap == null || assets.occlusionMap!.isEmpty)) {
      final inferred = conservativeOcclusionProvider.inferFromAssets(
        assets,
        imageSize: size,
      );
      if (inferred != null) {
        assets = assets.copyWith(
          occlusionMap: inferred.map,
          capabilities: assets.capabilities.merge(
            const VisionCapabilities(occlusionMap: true),
          ),
        );
      }
    }

    return assets;
  }

  WarpField? composeBodyField({
    required PoseResult? pose,
    required Size imageSize,
    required Map<String, double> parameters,
    bool interactive = false,
    PersonMask? personMask,
    BodyFrameAssets? assets,
    BodyMultiPassConfig? multiPassConfig,
  }) {
    // O pincel manual é independente dos sliders: sem este bypass, um traço
    // sozinho nunca chegava ao render.
    final brushField = manualBrushField;
    final hasBrush = brushField != null && !brushField.isIdentity;

    if (pose == null || !bodyFilterPipeline.hasActiveBodyWarp(parameters)) {
      return hasBrush ? _guardField(brushField) : null;
    }
    if (!bodyFilterPipeline.canApply(pose, parameters)) {
      return hasBrush ? _guardField(brushField) : null;
    }

    var config = multiPassConfig ?? bodyMultiPassConfig;
    var frameAssets = assets ??
        resolveBodyFrameAssets(
          pose: pose,
          personMask: personMask,
          imageSize: imageSize,
        );

    // Garante matte/oclusão mesmo quando o caller passou assets só da pose.
    if (frameAssets != null &&
        personMask != null &&
        (frameAssets.personMatte == null || frameAssets.personMatte!.isEmpty)) {
      frameAssets = frameAssets.copyWith(
        personMatte: personMask.toPersonMatte(),
        capabilities: frameAssets.capabilities.merge(
          const VisionCapabilities(personMatte: true),
        ),
      );
    }
    if (frameAssets != null &&
        (frameAssets.occlusionMap == null ||
            frameAssets.occlusionMap!.isEmpty)) {
      final inferred = conservativeOcclusionProvider.inferFromAssets(
        frameAssets,
        imageSize: imageSize,
      );
      if (inferred != null) {
        frameAssets = frameAssets.copyWith(
          occlusionMap: inferred.map,
          capabilities: frameAssets.capabilities.merge(
            const VisionCapabilities(occlusionMap: true),
          ),
        );
      }
    }

    final hasUsableMatte = frameAssets?.personMatte != null &&
        !(frameAssets!.personMatte!.isEmpty);
    // Com matte: todos os controles de corpo vão para a malha (caminho único).
    // Sem matte: V2 só para keys exclusivas; demais ficam no MLS legado.
    final wantsMesh = hasUsableMatte
        ? bodyFilterPipeline.hasActiveBodyWarp(parameters)
        : LegacyBodyParameterAdapter.requiresV2Mesh(parameters);
    if (wantsMesh && !config.bodyMeshWarp) {
      config = config.copyWith(
        bodyMeshWarp: true,
        antiFolding: true,
        edgeRefinement: hasUsableMatte,
      );
    } else if (config.bodyMeshWarp && hasUsableMatte && !config.edgeRefinement) {
      config = config.copyWith(edgeRefinement: true);
    }

    // Fallback seguro: máscara fraca / corpo parcial → path legado.
    if (frameAssets != null &&
        config.bodyMeshWarp &&
        _shouldPreferLegacyBodyPath(frameAssets)) {
      config = config.copyWith(
        bodyMeshWarp: false,
        localMls: false,
        edgeRefinement: false,
        antiFolding: false,
      );
    }

    WarpField? autoField;
    if ((config.bodyMeshWarp || config.localMls) && frameAssets != null) {
      final v2 = composeBodyMultiPassField(
        assets: frameAssets,
        imageSize: imageSize,
        parameters: parameters,
        interactive: interactive,
        config: config,
      );
      if (v2 != null && !v2.isIdentity) {
        autoField = v2;
      }
    } else if (frameAssets != null) {
      // Mantém plano atualizado para hints da UI mesmo no path legado.
      createBodyReshapePlan(
        imageSize: imageSize,
        parameters: parameters,
        interactive: interactive,
        assets: frameAssets,
      );
    }

    if (autoField == null) {
      final bodyMesh = meshEngine.buildBodyMesh(pose, imageSize);
      var legacy = bodyFilterPipeline.compose(
        mesh: bodyMesh,
        pose: pose,
        imageSize: imageSize,
        parameters: parameters,
        interactive: interactive,
        personMask: personMask,
      );

      // Pós-processamento V2 parcial sobre o campo legado (anti-fold / edge).
      if (config.antiFolding || config.edgeRefinement) {
        final partial = BodyMultiPassConfig(
          bodyMeshWarp: false,
          localMls: false,
          antiFolding: config.antiFolding,
          edgeRefinement: config.edgeRefinement,
          profilePasses: config.profilePasses,
        );
        final result = warpEngine.composeBodyMultiPass(
          BodyMultiPassInput(
            imageSize: imageSize,
            config: partial,
            seedField: legacy,
            assets: frameAssets,
          ),
        );
        if (result != null) {
          lastBodyMultiPassResult = result;
          legacy = result.field;
        }
      }
      autoField = legacy;
    }

    // Compõe pincel manual (se houver) após o campo automático.
    if (hasBrush) {
      if (autoField.isIdentity) {
        return _guardField(brushField);
      }
      return _guardField(WarpField.composeSequential(autoField, brushField));
    }

    return _guardField(autoField);
  }

  /// Rede de segurança final: remove dobras/compressão extrema do campo.
  ///
  /// Vale para qualquer caminho (V2, legado ou pincel) — é o que evita o
  /// "redemoinho" de pixels quando o deslocamento fica agressivo.
  WarpField _guardField(WarpField field) {
    if (field.isIdentity) {
      return field;
    }
    return const AntiFoldingPass().resolve(field).field;
  }

  /// Preferir path legado quando evidência de silhueta/confiança é insuficiente.
  bool _shouldPreferLegacyBodyPath(BodyFrameAssets assets) {
    final matte = assets.personMatte;
    final hasMatte = matte != null && !matte.isEmpty;
    // Com matte, o caminho V2 é sempre preferível: o MLS legado é o que produz
    // fantasma/redemoinho. Confiança baixa já reduz amplitude via safetyScale.
    if (hasMatte) {
      return false;
    }
    // Sem matte e pose parcial: V2 cápsula óssea costuma amassar fundo.
    return assets.isPartial;
  }

  /// Executa o pipeline multi-passe V2 a partir de assets + plano semântico.
  WarpField? composeBodyMultiPassField({
    required BodyFrameAssets assets,
    required Size imageSize,
    required Map<String, double> parameters,
    bool interactive = false,
    BodyMultiPassConfig? config,
  }) {
    final resolved = config ?? bodyMultiPassConfig;
    if (!resolved.isV2Enabled) {
      return null;
    }

    final plan = createBodyReshapePlan(
      imageSize: imageSize,
      parameters: parameters,
      interactive: interactive,
      assets: assets,
    );
    if (plan.isIdentity) {
      return null;
    }

    final quality = interactive
        ? WarpQualityProfile.interactive
        : WarpQualityProfile.preview;
    final adaptive = meshEngine.buildAdaptiveBodyMesh(
      assets: assets,
      imageSize: imageSize,
      qualityProfile: quality,
    );

    // Protection maps com banda exterior (fecha gap ao afinar).
    final matte = assets.personMatte;
    final protection = matte == null || matte.isEmpty
        ? null
        : _mattePreprocessor.buildProtectionMaps(
            matte,
            imageSize: imageSize,
          );

    final result = warpEngine.composeBodyMultiPass(
      BodyMultiPassInput(
        imageSize: imageSize,
        config: resolved,
        sourceMesh: adaptive,
        assets: assets,
        plan: plan,
        protectionMaps: protection,
      ),
    );
    lastBodyMultiPassResult = result;
    return result?.field;
  }


  Future<Uint8List> renderPostWarpRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required ProcessingPipeline pipeline,
    required Map<String, double> params,
    required FaceMeshResult? face,
    required Size imageSize,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    WarpField? faceWarp,
    Offset tileOrigin = Offset.zero,
  }) async {
    final texture = await gpuRenderer.upload(
      TextureUpload(
        bytes: rgba,
        width: width,
        height: height,
      ),
    );

    final postStages = _buildPostWarpStages(
      pipeline,
      params,
      face: face,
      imageSize: imageSize,
      faceParts: faceParts,
      faceParsing: faceParsing,
      faceWarp: faceWarp,
      tileOrigin: tileOrigin,
    );

    if (postStages.isEmpty) {
      final pixels = await gpuRenderer.readPixels(texture);
      gpuRenderer.release(texture);
      return pixels;
    }

    final output = await gpuRenderer.runPipeline(
      input: texture,
      stages: postStages,
    );

    final pixels = await gpuRenderer.readPixels(output);
    if (output.id != texture.id) {
      gpuRenderer.release(output);
    }
    gpuRenderer.release(texture);
    return pixels;
  }

  /// Limpa cache de estágio (ex.: ao trocar foto).
  void invalidateRenderStageCache() {
    final gpu = gpuRenderer;
    if (gpu is GpuRendererImpl) {
      _renderStageCache.clear(gpu);
    }
    maskFactory.clearCache();
    lastQualityContext = null;
    lastToolGatePlan = null;
    lastFaceParsing = null;
    lastFaceParts = null;
    lastFaceWarpField = null;
    lastFaceWarpDebugStats = FaceWarpDebugStats.empty;
    lastPersonMask = null;
    personMaskThrottle.reset();
  }

  /// Face Quality Assessment — 1× por foto (cap. 7).
  Future<FaceQualityContext> assessImageQuality({
    required ImageSource source,
    FaceMeshResult? face,
    FacePartsSegmentation? faceParts,
  }) async {
    profiler.start('quality_assess');
    final rgba = ImageSourceRgba.ensureRgba(source);
    final context = FaceQualityAssessment.assess(
      rgba: rgba.bytes,
      width: rgba.width,
      height: rgba.height,
      face: face,
      faceParts: faceParts,
    );
    lastQualityContext = context;
    lastToolGatePlan = toolGateEngine.evaluate(context);
    profiler.end('quality_assess');
    return context;
  }

  /// Aplica caps de gating aos parâmetros do slider.
  Map<String, double> applyToolGating(Map<String, double> raw) {
    return lastToolGatePlan?.applyToParameters(raw) ?? raw;
  }

  /// Única pipeline facial: JawField + remap bilinear. Sem ROI/Mesh/MLS.
  Uint8List applyJawWarp({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshResult? face,
    required Map<String, double> parameters,
  }) {
    final t = (parameters['jaw'] ?? 0).clamp(0.0, 1.0);
    if (face == null || t <= 0 || sourceRgba.length != width * height * 4) {
      lastFaceWarpBackend = null;
      lastFaceWarpField = null;
      return sourceRgba;
    }
    final built = JawField.build(
      face: face,
      imageSize: Size(width.toDouble(), height.toDouble()),
      t: t,
    );
    final warped = v2.BackwardBilinearWarp.apply(
      v2.WarpRequest(
        sourceRgba: sourceRgba,
        width: width,
        height: height,
        field: built.field,
      ),
    );
    lastFaceWarpBackend = 'v2_jaw';
    lastFaceWarpField = null;
    return warped.rgba;
  }

  /// ChinField + remap bilinear. Independente do Jaw. t=0 não chama o renderer.
  Uint8List applyChinWarp({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshResult? face,
    required Map<String, double> parameters,
  }) {
    final t = (parameters['chin'] ?? 0).clamp(0.0, 1.0);
    if (face == null || t <= 0 || sourceRgba.length != width * height * 4) {
      return sourceRgba;
    }
    final built = ChinField.build(
      face: face,
      imageSize: Size(width.toDouble(), height.toDouble()),
      t: t,
    );
    final warped = v2.BackwardBilinearWarp.apply(
      v2.WarpRequest(
        sourceRgba: sourceRgba,
        width: width,
        height: height,
        field: built.field,
      ),
    );
    lastFaceWarpBackend = 'v2_chin';
    lastFaceWarpField = null;
    return warped.rgba;
  }

  /// CheekbonesField + remap bilinear. Independente de Jaw e Chin. t=0 não chama o renderer.
  Uint8List applyCheekbonesWarp({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshResult? face,
    required Map<String, double> parameters,
  }) {
    final t = (parameters['cheekbone'] ?? 0).clamp(-1.0, 1.0);
    final tPhotoLeft =
        (parameters['cheekbone_left'] ?? t).clamp(-1.0, 1.0);
    final tPhotoRight =
        (parameters['cheekbone_right'] ?? t).clamp(-1.0, 1.0);
    if (face == null ||
        (tPhotoLeft.abs() <= 1e-6 && tPhotoRight.abs() <= 1e-6) ||
        sourceRgba.length != width * height * 4) {
      return sourceRgba;
    }
    final built = CheekbonesField.build(
      face: face,
      imageSize: Size(width.toDouble(), height.toDouble()),
      t: t,
      tPhotoLeft: tPhotoLeft,
      tPhotoRight: tPhotoRight,
    );
    debugPrint(
      '[cheekbones] L=${tPhotoLeft.toStringAsFixed(2)} '
      'R=${tPhotoRight.toStringAsFixed(2)} '
      'max=${built.metrics.influenceMax.toStringAsFixed(1)}px '
      'active=${built.masks.count(built.masks.cheekActive)} '
      'amp=${built.metrics.cheekAmplitude.toStringAsFixed(1)}',
    );
    final warped = v2.BackwardBilinearWarp.apply(
      v2.WarpRequest(
        sourceRgba: sourceRgba,
        width: width,
        height: height,
        field: built.field,
      ),
    );
    lastFaceWarpBackend = 'v2_cheekbone';
    lastFaceWarpField = null;
    return warped.rgba;
  }

  Future<TextureHandle> _renderTexture({
    required ImageSource source,
    required ProcessingPipeline pipeline,
    required FaceMeshResult? face,
    PoseResult? pose,
    PersonMask? personMask,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    bool interactivePreview = false,
    bool postWarpInpaint = false,
  }) async {
    profiler.start('render_texture');
    final rgbaSource = ImageSourceRgba.ensureRgba(source);
    final params = pipeline.effectiveParameters;
    final imageSize = Size(
      rgbaSource.width.toDouble(),
      rgbaSource.height.toDouble(),
    );

    final gpuImpl =
        gpuRenderer is GpuRendererImpl ? gpuRenderer as GpuRendererImpl : null;
    final stageCacheKey = RenderStageCache.buildKey(
      sourceWidth: rgbaSource.width,
      sourceHeight: rgbaSource.height,
      sourceSampleHash: RenderStageCache.sampleRgbaHash(rgbaSource.bytes),
      params: params,
      lutAssetPath: pipeline.preset?.lutAssetPath,
      face: face,
      hasManualBrush:
          manualBrushField != null && !manualBrushField!.isIdentity,
    );

    if (interactivePreview &&
        gpuImpl != null &&
        _renderStageCache.isValid(stageCacheKey)) {
      final colorStages = _buildColorStages(
        params,
        face: face,
        imageSize: imageSize,
        faceParts: faceParts,
      );
      final base = _renderStageCache.preColorTexture!;
      if (colorStages.isEmpty) {
        profiler.end('render_texture');
        return gpuImpl.copyTexture(base);
      }
      final output = await gpuRenderer.runPipeline(
        input: base,
        stages: colorStages,
      );
      profiler.end('render_texture');
      return output;
    }

    final jawRgba = applyJawWarp(
      sourceRgba: rgbaSource.bytes,
      width: rgbaSource.width,
      height: rgbaSource.height,
      face: face,
      parameters: params,
    );
    final faceRgba = applyChinWarp(
      sourceRgba: jawRgba,
      width: rgbaSource.width,
      height: rgbaSource.height,
      face: face,
      parameters: params,
    );
    final cheekRgba = applyCheekbonesWarp(
      sourceRgba: faceRgba,
      width: rgbaSource.width,
      height: rgbaSource.height,
      face: face,
      parameters: params,
    );

    final texture = await gpuRenderer.upload(
      TextureUpload(
        bytes: cheekRgba,
        width: rgbaSource.width,
        height: rgbaSource.height,
      ),
    );

    var output = texture;

    final bodyAssets = bodyFilterPipeline.hasActiveBodyWarp(params)
        ? resolveBodyFrameAssets(
            pose: pose,
            personMask: personMask,
            imageSize: imageSize,
          )
        : null;
    final bodyField = composeBodyField(
      pose: pose,
      imageSize: imageSize,
      parameters: params,
      interactive: interactivePreview,
      personMask: personMask,
      assets: bodyAssets,
    );
    if (bodyField != null && !bodyField.isIdentity) {
      output = await gpuRenderer.runPipeline(
        input: texture,
        stages: [
          RenderPipelineStage(
            shaderName: WarpEngine.warpRemapShader,
            uniforms: {
              'warpField': bodyField,
              if (interactivePreview) 'fastMode': true,
            },
          ),
        ],
      );

      if (output.id != texture.id) {
        gpuRenderer.release(texture);
      }
    }

    final preColorStages = _buildPreColorPostWarpStages(
      pipeline,
      params,
      face: face,
      imageSize: imageSize,
      faceParts: faceParts,
      faceParsing: faceParsing,
      faceWarp: null,
    );
    if (preColorStages.isNotEmpty) {
      final previous = output;
      output = await gpuRenderer.runPipeline(
        input: output,
        stages: preColorStages,
      );
      if (previous.id != texture.id && previous.id != output.id) {
        gpuRenderer.release(previous);
      }
    }

    if (interactivePreview && gpuImpl != null) {
      _renderStageCache.store(gpuImpl, stageCacheKey, output);
    }

    final colorStages = _buildColorStages(
      params,
      face: face,
      imageSize: imageSize,
      faceParts: faceParts,
    );
    if (colorStages.isNotEmpty) {
      final previous = output;
      final cachedId = _renderStageCache.preColorTexture?.id;
      output = await gpuRenderer.runPipeline(
        input: output,
        stages: colorStages,
      );
      if (previous.id != texture.id &&
          previous.id != output.id &&
          previous.id != cachedId) {
        gpuRenderer.release(previous);
      }
    }

    profiler.end('render_texture');
    return output;
  }

  List<RenderPipelineStage> _buildPreColorPostWarpStages(
    ProcessingPipeline pipeline,
    Map<String, double> params, {
    FaceMeshResult? face,
    required Size imageSize,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    WarpField? faceWarp,
    Offset tileOrigin = Offset.zero,
  }) {
    final stages = <RenderPipelineStage>[];
    final lutPath = pipeline.preset?.lutAssetPath;
    final lutIntensity =
        params['lut_intensity'] ?? pipeline.preset?.lutIntensity ?? 1;

    if (lutPath != null && lutPath.isNotEmpty && lutIntensity > 0) {
      stages.add(
        RenderPipelineStage(
          shaderName: RenderShaders.lutApply,
          uniforms: {
            'lutAssetPath': lutPath,
            'intensity': lutIntensity,
          },
        ),
      );
    }

    final doubleEyelid = params['double_eyelid'] ?? 0;
    if (doubleEyelid > 0 && face != null) {
      stages.add(
        RenderPipelineStage(
          shaderName: RenderShaders.eyeOverlay,
          uniforms: {
            'intensity': doubleEyelid,
            'ellipses': FaceWarpUtils.eyeOverlayEllipses(face, imageSize),
          },
        ),
      );
    }

    // Cheekbone contour GPU overlay removido (Sprint 8) — warp regional isolado.

    if (face != null) {
      stages.addAll(
        skinFilterPipeline.buildPostStages(
          parameters: params,
          face: face,
          imageSize: imageSize,
          faceParts: faceParts,
          faceParsing: faceParsing,
          faceWarp: faceWarp,
          tileOrigin: tileOrigin,
        ),
      );
    }

    return stages;
  }

  List<RenderPipelineStage> _buildColorStages(
    Map<String, double> params, {
    FaceMeshResult? face,
    required Size imageSize,
    FacePartsSegmentation? faceParts,
  }) {
    return colorFilterPipeline.buildColorStages(
      parameters: params,
      face: face,
      imageSize: imageSize,
      faceParts: faceParts,
    );
  }

  List<RenderPipelineStage> _buildPostWarpStages(
    ProcessingPipeline pipeline,
    Map<String, double> params, {
    FaceMeshResult? face,
    required Size imageSize,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    WarpField? faceWarp,
    Offset tileOrigin = Offset.zero,
  }) {
    return [
      ..._buildPreColorPostWarpStages(
        pipeline,
        params,
        face: face,
        imageSize: imageSize,
        faceParts: faceParts,
        faceParsing: faceParsing,
        faceWarp: faceWarp,
        tileOrigin: tileOrigin,
      ),
      ..._buildColorStages(
        params,
        face: face,
        imageSize: imageSize,
        faceParts: faceParts,
      ),
    ];
  }
}

class _RenderInputs {
  const _RenderInputs({
    required this.face,
    required this.pose,
    required this.personMask,
    required this.faceParts,
    required this.faceParsing,
  });

  final FaceMeshResult? face;
  final PoseResult? pose;
  final PersonMask? personMask;
  final FacePartsSegmentation? faceParts;
  final FaceParsingResult? faceParsing;
}
