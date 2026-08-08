/// Telemetria de debug do warp facial V3 (lab).
class FaceWarpDebugStats {
  const FaceWarpDebugStats({
    this.movedVertices = 0,
    this.vertexMaxPx = 0,
    this.rigidPinnedVertices = 0,
  });

  final int movedVertices;
  final double vertexMaxPx;
  final int rigidPinnedVertices;

  static const empty = FaceWarpDebugStats();

  bool get hasDisplacement => movedVertices > 0 && vertexMaxPx > 0.01;
}
