import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../body_reshape/providers/background_analysis_provider.dart';
import '../body_reshape/providers/body_mesh_provider.dart';
import '../body_reshape/providers/body_part_segmentation_provider.dart';
import '../body_reshape/providers/body_vision_coordinator.dart';
import '../body_reshape/providers/instance_selection_policy.dart';
import '../body_reshape/providers/mediapipe_body_mesh_provider.dart';
import '../body_reshape/providers/mediapipe_person_matte_provider.dart';
import '../body_reshape/providers/occlusion_provider.dart';
import '../body_reshape/providers/person_matte_provider.dart';
import '../body_reshape/providers/unavailable_vision_providers.dart';
import '../controllers/beauty_engine_controller.dart';
import '../face_mesh/face_mesh_detector.dart';
import '../face_mesh/face_mesh_detector_impl.dart';
import '../face_mesh/face_mesh_detector_stub.dart';
import '../mesh/mesh_engine.dart';
import '../mesh/mesh_engine_impl.dart';
import '../pose/pose_detector.dart';
import '../pose/pose_detector_impl.dart';
import '../pose/pose_detector_stub.dart';
import '../segment/person_mask.dart';
import '../segment/person_mask_detector_impl.dart';
import '../segment/person_mask_detector_stub.dart';
import '../presets/beauty_preset_local_store.dart';
import '../presets/beauty_preset_remote_datasource.dart';
import '../presets/beauty_preset_repository.dart';
import '../presets/beauty_preset_repository_impl.dart';
import '../models/beauty_preset.dart';
import '../models/beauty_preset_marketplace_entry.dart';
import '../presets/lut_engine.dart';
import '../presets/preset_file_service.dart';
import '../presets/preset_sync_service.dart';
import '../presets/preset_thumbnail_service.dart';
import '../performance/beauty_benchmark_aggregator.dart';
import '../performance/beauty_profiler.dart';
import '../performance/shader_prewarm_service.dart';
import '../performance/tiled_export_engine.dart';
import '../rendering/gpu_renderer.dart';
import '../rendering/gpu_renderer_impl.dart';
import '../warp/mls_warp_engine.dart';
import '../warp/warp_engine.dart';
import 'mediapipe_init_coordinator.dart';

final mediapipeBindingsProvider = Provider<BeautyMediapipeBindings>(
  (ref) => BeautyMediapipeMethodChannel(),
);

final mediapipeFaceModelPathProvider = Provider<Future<String>>(
  (ref) => MediapipeModelLoader.ensureFaceModelOnDisk(),
);

final mediapipePoseModelPathProvider = Provider<Future<String>>(
  (ref) => MediapipeModelLoader.ensurePoseModelOnDisk(),
);

final mediapipeSegmenterModelPathProvider = Provider<Future<String>>(
  (ref) => MediapipeModelLoader.ensureSegmenterModelOnDisk(),
);

final mediapipeInitCoordinatorProvider = Provider<MediapipeInitCoordinator>(
  (ref) => MediapipeInitCoordinator(
    bindings: ref.watch(mediapipeBindingsProvider),
    resolveFaceModelPath: () => ref.read(mediapipeFaceModelPathProvider),
    resolvePoseModelPath: () => ref.read(mediapipePoseModelPathProvider),
    resolveSegmenterModelPath: () =>
        ref.read(mediapipeSegmenterModelPathProvider),
  ),
);

bool get _supportsNativeMediapipe {
  if (kIsWeb) {
    return false;
  }
  return Platform.isAndroid || Platform.isIOS;
}

final faceMeshDetectorProvider = Provider<FaceMeshDetector>(
  (ref) {
    if (!_supportsNativeMediapipe) {
      return const FaceMeshDetectorStub();
    }

    return FaceMeshDetectorImpl(
      bindings: ref.watch(mediapipeBindingsProvider),
      coordinator: ref.watch(mediapipeInitCoordinatorProvider),
    );
  },
);

final poseDetectorProvider = Provider<PoseDetector>(
  (ref) {
    if (!_supportsNativeMediapipe) {
      return const PoseDetectorStub();
    }

    return PoseDetectorImpl(
      bindings: ref.watch(mediapipeBindingsProvider),
      coordinator: ref.watch(mediapipeInitCoordinatorProvider),
    );
  },
);

final personMaskDetectorProvider = Provider<PersonMaskDetector>(
  (ref) {
    if (!_supportsNativeMediapipe) {
      return const PersonMaskDetectorStub();
    }

    return PersonMaskDetectorImpl(
      bindings: ref.watch(mediapipeBindingsProvider),
      coordinator: ref.watch(mediapipeInitCoordinatorProvider),
    );
  },
);

final bodyMeshProviderProvider = Provider<BodyMeshProvider>(
  (ref) {
    if (!_supportsNativeMediapipe) {
      return const UnavailableBodyMeshProvider();
    }
    return MediaPipeBodyMeshProvider(
      poseDetector: ref.watch(poseDetectorProvider),
    );
  },
);

final personMatteProviderProvider = Provider<PersonMatteProvider>(
  (ref) {
    if (!_supportsNativeMediapipe) {
      return const UnavailablePersonMatteProvider();
    }
    return MediaPipePersonMatteProvider(
      detector: ref.watch(personMaskDetectorProvider),
    );
  },
);

final bodyPartSegmentationProviderProvider =
    Provider<BodyPartSegmentationProvider>(
  // Nenhum modelo é fixado antes do benchmark de precisão/licença/latência.
  (ref) => const UnavailableBodyPartSegmentationProvider(),
);

final instanceSelectionPolicyProvider = Provider<InstanceSelectionPolicy>(
  (ref) => const InstanceSelectionPolicy(),
);

final occlusionProviderProvider = Provider<OcclusionProvider>(
  (ref) => const UnavailableOcclusionProvider(),
);

final backgroundAnalysisProviderProvider = Provider<BackgroundAnalysisProvider>(
  (ref) => const UnavailableBackgroundAnalysisProvider(),
);

final bodyVisionCoordinatorProvider = Provider<BodyVisionCoordinator>(
  (ref) => BodyVisionCoordinator(
    bodyMeshProvider: ref.watch(bodyMeshProviderProvider),
    personMatteProvider: ref.watch(personMatteProviderProvider),
    bodyPartSegmentationProvider:
        ref.watch(bodyPartSegmentationProviderProvider),
    occlusionProvider: ref.watch(occlusionProviderProvider),
    backgroundAnalysisProvider: ref.watch(backgroundAnalysisProviderProvider),
    instanceSelectionPolicy: ref.watch(instanceSelectionPolicyProvider),
  ),
);

final meshEngineProvider = Provider<MeshEngine>(
  (ref) => MeshEngineImpl(),
);

final warpEngineProvider = Provider<WarpEngine>(
  (ref) => MlsWarpEngine(),
);

final gpuRendererProvider = Provider<GPURenderer>(
  (ref) => GpuRendererImpl(),
);

final lutEngineProvider = Provider<LutEngine>(
  (ref) => LutEngine(),
);

final beautyPresetRemoteDataSourceProvider =
    Provider<BeautyPresetRemoteDataSource>((ref) {
  return BeautyPresetRemoteDataSource(ref.watch(supabaseClientProvider));
});

final beautyPresetRepositoryProvider = Provider<BeautyPresetRepository>(
  (ref) => BeautyPresetRepositoryImpl(
    store: BeautyPresetLocalStore(
      resolveDirectory: () async {
        final documents = await getApplicationDocumentsDirectory();
        return Directory('${documents.path}/beauty_presets');
      },
    ),
    remote: ref.watch(beautyPresetRemoteDataSourceProvider),
    syncService: const PresetSyncService(),
    currentUserId: () => ref.read(supabaseClientProvider).auth.currentUser?.id,
  ),
);

final bundledBeautyPresetsProvider = FutureProvider<List<BeautyPreset>>(
  (ref) => ref.read(beautyPresetRepositoryProvider).listBundledPresets(),
);

final userBeautyPresetsProvider = FutureProvider<List<BeautyPreset>>(
  (ref) => ref.read(beautyPresetRepositoryProvider).listUserPresets(),
);

final allBeautyPresetsProvider = FutureProvider<List<BeautyPreset>>(
  (ref) => ref.read(beautyPresetRepositoryProvider).listPresets(),
);

final marketplacePresetsProvider =
    FutureProvider<List<BeautyPresetMarketplaceEntry>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(beautyPresetRepositoryProvider).listMarketplacePresets();
});

final presetThumbnailServiceProvider = Provider<PresetThumbnailService>(
  (ref) => const PresetThumbnailService(),
);

final presetFileServiceProvider = Provider<PresetFileService>(
  (ref) => const PresetFileService(),
);

final beautyProfilerProvider = Provider<BeautyProfiler>(
  (ref) => BeautyProfiler(),
);

final beautyBenchmarkProvider = Provider<BeautyBenchmarkAggregator>(
  (ref) => BeautyBenchmarkAggregator(),
);

final shaderPrewarmServiceProvider = Provider<ShaderPrewarmService>(
  (ref) => const ShaderPrewarmService(),
);

final tiledExportEngineProvider = Provider<TiledExportEngine>(
  (ref) => TiledExportEngine(),
);

final beautyEngineControllerProvider = Provider<BeautyEngineController>(
  (ref) => BeautyEngineController(
    faceDetector: ref.watch(faceMeshDetectorProvider),
    poseDetector: ref.watch(poseDetectorProvider),
    personMaskDetector: ref.watch(personMaskDetectorProvider),
    bodyVisionCoordinator: ref.watch(bodyVisionCoordinatorProvider),
    meshEngine: ref.watch(meshEngineProvider),
    warpEngine: ref.watch(warpEngineProvider),
    gpuRenderer: ref.watch(gpuRendererProvider),
    profiler: ref.watch(beautyProfilerProvider),
    tiledExportEngine: ref.watch(tiledExportEngineProvider),
  ),
);
