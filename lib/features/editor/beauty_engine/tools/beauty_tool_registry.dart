import '../filters/color/color_filter_pipeline.dart';
import '../filters/face/face_filter_pipeline.dart';
import '../filters/face/skin_filter_pipeline.dart';
import 'tool_descriptor.dart';

/// Registry central de ferramentas (cap. 12) — deriva keys dos pipelines.
abstract final class BeautyToolRegistry {
  static final List<ToolDescriptor> all = [
    ..._proportion,
    ..._eyebrow,
    ..._face,
    ..._skin,
    ..._color,
  ];

  static final Map<String, ToolDescriptor> byKey = {
    for (final d in all) d.key: d,
  };

  static List<String> get allKeys =>
      all.map((d) => d.key).toList(growable: false);

  static const _proportion = [
    ToolDescriptor(
      key: 'head',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
  ];

  static const _eyebrow = [
    ToolDescriptor(
      key: 'eyebrow_height',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'eyebrow_width',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
  ];

  static const _face = [
    ToolDescriptor(
      key: 'jaw',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'jaw_angle',
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
      key: 'v_chin',
      category: ToolCategory.face,
      pipelineStage: ToolPipelineStage.warp,
      requiresFace: true,
    ),
    ToolDescriptor(
      key: 'v_shape',
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
      key: 'hairline',
      category: ToolCategory.face,
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
  static List<String> get faceWarpKeys => [
        ...FaceFilterPipeline.proportionParameterKeys,
        ...FaceFilterPipeline.eyebrowParameterKeys,
        ...FaceFilterPipeline.faceWarpParameterKeys,
      ];
}
