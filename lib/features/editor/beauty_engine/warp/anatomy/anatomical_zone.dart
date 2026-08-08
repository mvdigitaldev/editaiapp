/// Zonas anatômicas do rosto para o Face Warp Engine V3.
///
/// Partição mais fina que [FaceWarpRegion] — ver
/// `docs/beauty/23-face-model-specification.md`.
enum AnatomicalZone {
  skullContour,
  forehead,
  templeLeft,
  templeRight,
  browLeft,
  browRight,
  eyeLeft,
  eyeRight,
  noseRoot,
  noseDorsum,
  noseTip,
  noseAlae,
  cheekLeft,
  cheekRight,
  jawLeft,
  jawRight,
  chin,
  upperLip,
  lowerLip,
  mouthCorner,
  oralCavity,
  philtrum,
}

/// Papel de deformação de um vértice dentro de uma zona.
enum VertexRole {
  /// Δv = 0 sempre.
  rigid,

  /// Δv × peso de borda (0–1).
  semiRigid,

  /// Δv completo após clamp da ferramenta.
  free,
}

/// Modo de deformação emitido por um filtro (intenção anatômica).
enum DeformationMode {
  scale,
  translate,
  radialInward,
  radialOutward,
  rotate,

  /// Deslocamento customizado por ferramenta piloto (Sprint 34).
  pilot,
}
