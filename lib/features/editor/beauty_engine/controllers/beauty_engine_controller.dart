import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/models/body_frame_assets.dart';
import '../body_reshape/models/body_reshape_request.dart';
import '../body_reshape/models/warp_plan.dart';
import '../body_reshape/occlusion/conservative_occlusion_provider.dart';
import '../body_reshape/occlusion/occlusion_engine.dart';
import '../body_reshape/providers/body_vision_coordinator.dart';
import '../body_reshape/providers/vision_capabilities.dart';
import '../filters/body/body_filter_pipeline.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/face/face_warp_utils.dart';
import '../filters/face/skin_filter_pipeline.dart';
import '../models/face_mesh_result.dart';
import '../face_mesh/face_mesh_detector.dart';
import '../mesh/mesh_engine.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/processed_frame.dart';
import '../models/processing_pipeline.dart';
import '../models/pose_result.dart';
import '../performance/beauty_profiler.dart';
import '../performance/landmark_throttle.dart';
import '../performance/tiled_export_engine.dart';
import '../pose/pose_detector.dart';
import '../rendering/gpu_renderer.dart';
import '../segment/person_mask.dart';
import '../warp/warp_engine.dart';

/// Orquestrador do Beauty Engine — ponto unico para a UI (sem Widget).
class BeautyEngineController {
  final FaceMeshDetector faceDetector;
  final PoseDetector poseDetector;
  final PersonMaskDetector? personMaskDetector;
  final BodyVisionCoordinator? bodyVisionCoordinator;
  final MeshEngine meshEngine;
  final WarpEngine warpEngine;
  final GPURenderer gpuRenderer;
  final FaceFilterPipeline faceFilterPipeline;
  final BodyFilterPipeline bodyFilterPipeline;
  final SkinFilterPipeline skinFilterPipeline;
  final BeautyProfiler profiler;
  final LandmarkThrottle<FaceMeshResult?> faceLandmarkThrottle;
  final LandmarkThrottle<PoseResult?> poseLandmarkThrottle;
  final TiledExportEngine tiledExportEngine;
  final OcclusionEngine occlusionEngine;
  final ConservativeOcclusionProvider conservativeOcclusionProvider;

  /// Toggles do pipeline multi-passe V2 (Sprint 10). Default = legado.
  BodyMultiPassConfig bodyMultiPassConfig;

  /// Último resultado multi-passe (telemetria / debug).
  BodyMultiPassResult? lastBodyMultiPassResult;

  BeautyEngineController({
    required this.faceDetector,
    required this.poseDetector,
    required this.meshEngine,
    required this.warpEngine,
    required this.gpuRenderer,
    this.personMaskDetector,
    this.bodyVisionCoordinator,
    this.faceFilterPipeline = const FaceFilterPipeline(),
    this.bodyFilterPipeline = const BodyFilterPipeline(),
    this.skinFilterPipeline = const SkinFilterPipeline(),
    this.occlusionEngine = const OcclusionEngine(),
    this.conservativeOcclusionProvider = const ConservativeOcclusionProvider(),
    this.bodyMultiPassConfig = BodyMultiPassConfig.legacy,
    BeautyProfiler? profiler,
    LandmarkThrottle<FaceMeshResult?>? faceLandmarkThrottle,
    LandmarkThrottle<PoseResult?>? poseLandmarkThrottle,
    TiledExportEngine? tiledExportEngine,
  })  : profiler = profiler ?? BeautyProfiler(),
        faceLandmarkThrottle =
            faceLandmarkThrottle ?? LandmarkThrottle<FaceMeshResult?>(),
        poseLandmarkThrottle =
            poseLandmarkThrottle ?? LandmarkThrottle<PoseResult?>(),
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
    final personMask = bodyFilterPipeline.hasActiveBodyWarp(
      pipeline.effectiveParameters,
    )
        ? await detectPersonMask(source)
        : null;

    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: face,
      pose: pose,
      personMask: personMask,
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

  /// Exporta JPEG; usa tiles automaticamente acima de 8MP (Sprint 25).
  Future<Uint8List> exportJpeg({
    required ImageSource source,
    required ProcessingPipeline pipeline,
    int quality = 90,
    bool forceTiledExport = false,
    FaceMeshResult? face,
    PoseResult? pose,
    PersonMask? personMask,
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
    final resolvedFace = face ?? await detectFace(source);
    final resolvedPose = pose ?? await detectPose(source);
    final params = pipeline.effectiveParameters;
    final resolvedMask = personMask ??
        (bodyFilterPipeline.hasActiveBodyWarp(params)
            ? await detectPersonMask(source)
            : null);
    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: resolvedFace,
      pose: resolvedPose,
      personMask: resolvedMask,
      interactivePreview: interactivePreview,
    );

    final jpeg = await gpuRenderer.exportJpeg(output, quality: quality);
    gpuRenderer.release(output);
    profiler.end('export_total');
    return jpeg;
  }

  Future<FaceMeshResult?> detectFace(ImageSource source) {
    return faceLandmarkThrottle.resolve(() => faceDetector.detect(source));
  }

  Future<PoseResult?> detectPose(ImageSource source) {
    return poseLandmarkThrottle.resolve(() => poseDetector.detect(source));
  }

  Future<PersonMask?> detectPersonMask(ImageSource source) async {
    final detector = personMaskDetector;
    if (detector == null) {
      return null;
    }
    try {
      return await detector.detect(source);
    } catch (_) {
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
    final plan = bodyFilterPipeline.createReshapePlan(
      imageSize: imageSize,
      parameters: parameters,
      interactive: interactive,
      capabilities: capabilities ??
          assets?.capabilities ??
          bodyVisionCapabilities,
    );
    if (assets == null) {
      return plan;
    }
    return occlusionEngine.applyToPlan(plan: plan, assets: assets);
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
    if (pose == null || !bodyFilterPipeline.hasActiveBodyWarp(parameters)) {
      return null;
    }
    if (!bodyFilterPipeline.canApply(pose, parameters)) {
      return null;
    }

    final config = multiPassConfig ?? bodyMultiPassConfig;
    if ((config.bodyMeshWarp || config.localMls) && assets != null) {
      final v2 = composeBodyMultiPassField(
        assets: assets,
        imageSize: imageSize,
        parameters: parameters,
        interactive: interactive,
        config: config,
      );
      if (v2 != null && !v2.isIdentity) {
        return v2;
      }
    }

    final bodyMesh = meshEngine.buildBodyMesh(pose, imageSize);
    var field = bodyFilterPipeline.compose(
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
          seedField: field,
          assets: assets,
        ),
      );
      if (result != null) {
        lastBodyMultiPassResult = result;
        field = result.field;
      }
    }

    return field;
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

    final result = warpEngine.composeBodyMultiPass(
      BodyMultiPassInput(
        imageSize: imageSize,
        config: resolved,
        sourceMesh: adaptive,
        assets: assets,
        plan: plan,
      ),
    );
    lastBodyMultiPassResult = result;
    return result?.field;
  }

  WarpField? composeFaceField({
    required FaceMeshResult? face,
    required Size imageSize,
    required Map<String, double> parameters,
  }) {
    if (face == null || !faceFilterPipeline.hasActiveWarp(parameters)) {
      return null;
    }

    final mesh = meshEngine.buildFaceMesh(face, imageSize);
    return faceFilterPipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: parameters,
    );
  }

  Future<Uint8List> renderPostWarpRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required ProcessingPipeline pipeline,
    required Map<String, double> params,
    required FaceMeshResult? face,
    required Size imageSize,
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

  Future<TextureHandle> _renderTexture({
    required ImageSource source,
    required ProcessingPipeline pipeline,
    required FaceMeshResult? face,
    PoseResult? pose,
    PersonMask? personMask,
    bool interactivePreview = false,
  }) async {
    profiler.start('render_texture');
    final rgbaSource = ImageSourceRgba.ensureRgba(source);
    final texture = await gpuRenderer.upload(
      TextureUpload(
        bytes: rgbaSource.bytes,
        width: rgbaSource.width,
        height: rgbaSource.height,
      ),
    );

    var output = texture;
    final params = pipeline.effectiveParameters;
    final imageSize = Size(
      rgbaSource.width.toDouble(),
      rgbaSource.height.toDouble(),
    );

    final bodyField = composeBodyField(
      pose: pose,
      imageSize: imageSize,
      parameters: params,
      interactive: interactivePreview,
      personMask: personMask,
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

    final faceField = composeFaceField(
      face: face,
      imageSize: imageSize,
      parameters: params,
    );
    if (faceField != null && !faceField.isIdentity) {
      final warpInput = output;
      output = await gpuRenderer.runPipeline(
        input: warpInput,
        stages: [
          RenderPipelineStage(
            shaderName: WarpEngine.warpRemapShader,
            uniforms: {
              'warpField': faceField,
              if (interactivePreview) 'fastMode': true,
            },
          ),
        ],
      );

      if (warpInput.id != texture.id && warpInput.id != output.id) {
        gpuRenderer.release(warpInput);
      }
    }

    final postStages = _buildPostWarpStages(
      pipeline,
      params,
      face: face,
      imageSize: imageSize,
    );
    if (postStages.isNotEmpty) {
      final previous = output;
      output = await gpuRenderer.runPipeline(
        input: output,
        stages: postStages,
      );
      if (previous.id != texture.id && previous.id != output.id) {
        gpuRenderer.release(previous);
      }
    }

    profiler.end('render_texture');
    return output;
  }

  List<RenderPipelineStage> _buildPostWarpStages(
    ProcessingPipeline pipeline,
    Map<String, double> params, {
    FaceMeshResult? face,
    required Size imageSize,
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

    final cheekbone = params['cheekbone'] ?? 0;
    if (cheekbone > 0 && face != null) {
      final contour = FaceWarpUtils.cheekboneContourRegions(face, imageSize);
      stages.add(
        RenderPipelineStage(
          shaderName: RenderShaders.cheekboneContour,
          uniforms: {
            'intensity': cheekbone,
            'highlights': contour.highlights,
            'shadows': contour.shadows,
          },
        ),
      );
    }

    if (face != null) {
      stages.addAll(
        skinFilterPipeline.buildPostStages(
          parameters: params,
          face: face,
          imageSize: imageSize,
        ),
      );
    }

    final brightness = params['brightness'] ?? 0;
    final contrast = 1 + (params['contrast'] ?? 0);
    if (brightness != 0 || contrast != 1) {
      stages.add(
        RenderPipelineStage(
          shaderName: RenderShaders.colorAdjust,
          uniforms: {
            'brightness': brightness,
            'contrast': contrast,
          },
        ),
      );
    }

    return stages;
  }
}
