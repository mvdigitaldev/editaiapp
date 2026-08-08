/// Categoria de ferramenta no registry (cap. 12).
enum ToolCategory {
  face,
  nose,
  eyes,
  mouth,
  body,
  skin,
  color,
}

/// Estágio do pipeline onde a ferramenta atua.
enum ToolPipelineStage {
  warp,
  skin,
  color,
  lut,
}

/// Descritor declarativo de uma ferramenta beauty.
class ToolDescriptor {
  const ToolDescriptor({
    required this.key,
    required this.category,
    required this.pipelineStage,
    this.requiresFace = false,
    this.requiresSkinMask = false,
  });

  final String key;
  final ToolCategory category;
  final ToolPipelineStage pipelineStage;
  final bool requiresFace;
  final bool requiresSkinMask;
}
