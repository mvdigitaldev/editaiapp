import 'dart:typed_data';
import 'dart:ui';

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
import '../models/warp_field.dart';
import '../performance/beauty_profiler.dart';
import '../performance/landmark_throttle.dart';
import '../performance/tiled_export_engine.dart';
import '../pose/pose_detector.dart';
import '../rendering/gpu_renderer.dart';
import '../warp/warp_engine.dart';

/// Orquestrador do Beauty Engine — ponto unico para a UI (sem Widget).
class BeautyEngineController {
  final FaceMeshDetector faceDetector;
  final PoseDetector poseDetector;
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

  BeautyEngineController({
    required this.faceDetector,
    required this.poseDetector,
    required this.meshEngine,
    required this.warpEngine,
    required this.gpuRenderer,
    this.faceFilterPipeline = const FaceFilterPipeline(),
    this.bodyFilterPipeline = const BodyFilterPipeline(),
    this.skinFilterPipeline = const SkinFilterPipeline(),
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

    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: face,
      pose: pose,
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
  }) async {
    profiler.beginFrame();

    if (forceTiledExport ||
        tiledExportEngine.shouldUseTiledExport(
          ImageSourceRgba.ensureRgba(source),
        )) {
      return tiledExportEngine.exportJpeg(
        controller: this,
        source: source,
        pipeline: pipeline,
        quality: quality,
        profiler: profiler,
      );
    }

    profiler.start('export_total');
    final face = await detectFace(source);
    final pose = await detectPose(source);
    final output = await _renderTexture(
      source: source,
      pipeline: pipeline,
      face: face,
      pose: pose,
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

  WarpField? composeBodyField({
    required PoseResult? pose,
    required Size imageSize,
    required Map<String, double> parameters,
  }) {
    if (pose == null || !bodyFilterPipeline.hasActiveBodyWarp(parameters)) {
      return null;
    }
    if (!bodyFilterPipeline.canApply(pose, parameters)) {
      return null;
    }

    final bodyMesh = meshEngine.buildBodyMesh(pose, imageSize);
    return bodyFilterPipeline.compose(
      mesh: bodyMesh,
      pose: pose,
      imageSize: imageSize,
      parameters: parameters,
    );
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
    );
    if (bodyField != null && !bodyField.isIdentity) {
      output = await gpuRenderer.runPipeline(
        input: texture,
        stages: [
          RenderPipelineStage(
            shaderName: WarpEngine.warpRemapShader,
            uniforms: {'warpField': bodyField},
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
            uniforms: {'warpField': faceField},
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
