/// Capacidades do backend de preview Body Reshape (GPU vs fallback).
class RenderCapabilities {
  /// Remap via [FragmentProgram] / Impeller disponível e inicializado.
  final bool fragmentProgramWarp;

  /// Força caminho CPU (testes, dispositivo incompatível, flag explícita).
  final bool forceCpuFallback;

  /// Preview multi-passe com mapas de proteção/influência.
  final bool protectionMaps;
  final bool influenceMaps;

  const RenderCapabilities({
    this.fragmentProgramWarp = false,
    this.forceCpuFallback = false,
    this.protectionMaps = true,
    this.influenceMaps = true,
  });

  static const cpuOnly = RenderCapabilities(forceCpuFallback: true);

  static const gpuPreview = RenderCapabilities(
    fragmentProgramWarp: true,
    protectionMaps: true,
    influenceMaps: true,
  );

  /// Caminho ativo de preview: GPU quando disponível e não forçado a CPU.
  bool get usesGpuPreview => fragmentProgramWarp && !forceCpuFallback;

  RenderCapabilities copyWith({
    bool? fragmentProgramWarp,
    bool? forceCpuFallback,
    bool? protectionMaps,
    bool? influenceMaps,
  }) {
    return RenderCapabilities(
      fragmentProgramWarp: fragmentProgramWarp ?? this.fragmentProgramWarp,
      forceCpuFallback: forceCpuFallback ?? this.forceCpuFallback,
      protectionMaps: protectionMaps ?? this.protectionMaps,
      influenceMaps: influenceMaps ?? this.influenceMaps,
    );
  }
}
