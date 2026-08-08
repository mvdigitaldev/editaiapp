import '../filters/color/color_filter_pipeline.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/face/skin_filter_pipeline.dart';
import 'tool_descriptor.dart';

/// Registry central de ferramentas (cap. 12) — deriva keys dos pipelines.
abstract final class BeautyToolRegistry {
  static final List<ToolDescriptor> all = [
    ..._face,
    ..._skin,
    ..._color,
  ];

  static final Map<String, ToolDescriptor> byKey = {
    for (final d in all) d.key: d,
  };

  static List<String> get allKeys => all.map((d) => d.key).toList(growable: false);

  static const _face = [
    ToolDescriptor(
      key: 'face_slim',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'narrow_face',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'v_face',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'jaw',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'chin',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'cheekbone',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'forehead',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'temple',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'head_size',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'nose_slim',
      category: ToolCategory.nose,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'nose_length',
      category: ToolCategory.nose,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'nose_height',
      category: ToolCategory.nose,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'nose_tip',
      category: ToolCategory.nose,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'nose_bridge',
      category: ToolCategory.nose,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'eye_scale',
      category: ToolCategory.eyes,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'eye_distance',
      category: ToolCategory.eyes,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'eye_height',
      category: ToolCategory.eyes,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'eye_rotation',
      category: ToolCategory.eyes,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'double_eyelid',
      category: ToolCategory.eyes,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'mouth_width',
      category: ToolCategory.mouth,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'lip_thickness',
      category: ToolCategory.mouth,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'smile',
      category: ToolCategory.mouth,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
  ];

  static final _skin = [
    for (final key in SkinFilterPipeline.skinParameterKeys)
      ToolDescriptor(
        key: key,
        category: ToolCategory.skin,
        pipelineStage: ToolPipelineStage.skin,
        requiresFace: true,
        requiresSkinMask: true,
      ),
  ];

  static final _color = [
    for (final key in ColorFilterPipeline.colorParameterKeys)
      ToolDescriptor(
        key: key,
        category: ToolCategory.color,
        pipelineStage: ToolPipelineStage.color,
      ),
  ];

  /// Keys faciais conhecidas (warp) — espelha [FaceFilterPipeline].
  static List<String> get faceWarpKeys =>
      FaceFilterPipeline.faceWarpParameterKeys;
}
