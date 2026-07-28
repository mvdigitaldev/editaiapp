/// Beauty Engine — motor de edição facial/corporal (open source).
library beauty_engine;

export 'body_reshape/body_reshape.dart';
export 'controllers/beauty_engine_controller.dart';
export 'di/beauty_engine_providers.dart';
export 'face_mesh/face_mesh_detector.dart';
export 'filters/face/face_filter_pipeline.dart';
export 'filters/beauty_filter.dart';
export 'mesh/mesh_engine.dart';
export 'models/beauty_preset.dart';
export 'models/face_mesh_result.dart';
export 'models/image_source.dart';
export 'models/pose_result.dart';
export 'models/processed_frame.dart';
export 'models/processing_pipeline.dart';
export 'pose/pose_detector.dart';
export 'presets/bundled_preset_loader.dart';
export 'presets/bundled_presets.dart';
export 'presets/beauty_preset_repository.dart';
export 'presets/beauty_preset_repository_impl.dart';
export 'rendering/gpu_renderer.dart';
export 'warp/warp_engine.dart';
