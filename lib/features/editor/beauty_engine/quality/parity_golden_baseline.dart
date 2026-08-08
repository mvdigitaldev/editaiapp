/// Baselines do corpus golden Banuba/V3 para paridade automática (Sprint 39).
///
/// Faixas conservadoras derivadas dos goldens `test/golden/face_warp_v3_*`
/// no fixture sintético 640×960.
class ParityGoldenBaseline {
  const ParityGoldenBaseline({
    required this.toolKey,
    required this.minMovedVertices,
    required this.minVertexMaxPx,
    required this.maxVertexMaxPx,
  });

  final String toolKey;
  final int minMovedVertices;
  final double minVertexMaxPx;
  final double maxVertexMaxPx;

  static const _registry = <String, ParityGoldenBaseline>{
    'jaw': ParityGoldenBaseline(
      toolKey: 'jaw',
      minMovedVertices: 4,
      minVertexMaxPx: 0.4,
      maxVertexMaxPx: 96,
    ),
    'chin': ParityGoldenBaseline(
      toolKey: 'chin',
      minMovedVertices: 3,
      minVertexMaxPx: 0.3,
      maxVertexMaxPx: 72,
    ),
    'eye_scale': ParityGoldenBaseline(
      toolKey: 'eye_scale',
      minMovedVertices: 6,
      minVertexMaxPx: 0.5,
      maxVertexMaxPx: 48,
    ),
    'lip_thickness': ParityGoldenBaseline(
      toolKey: 'lip_thickness',
      minMovedVertices: 4,
      minVertexMaxPx: 0.3,
      maxVertexMaxPx: 40,
    ),
  };

  static ParityGoldenBaseline? forTool(String toolKey) => _registry[toolKey];

  static Iterable<ParityGoldenBaseline> get all => _registry.values;
}
