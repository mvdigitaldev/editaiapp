import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../models/tri_mesh.dart';
import 'anatomical_zone.dart';

/// Intenção anatômica emitida por um filtro V3 — não move vértices diretamente.
class AnatomicalIntent {
  const AnatomicalIntent({
    required this.toolKey,
    required this.primaryZone,
    required this.mode,
    required this.magnitude,
    this.rawIntensity,
    this.axis = Offset.zero,
    this.affectedZones = const {},
    this.priority = 0,
  });

  final String toolKey;
  final AnatomicalZone primaryZone;
  final DeformationMode mode;

  /// 0..1 pós-curve, antes do clamp do ACE.
  final double magnitude;

  /// Slider bruto 0..1 (pré-curve). Usado por filtros com thresholds (ex.: smile).
  final double? rawIntensity;

  /// Direção normalizada (translate) ou eixo local (rotate).
  final Offset axis;

  /// Zonas afetadas; vazio → primaryZone apenas.
  final Set<AnatomicalZone> affectedZones;

  /// Maior valor vence conflitos no mesmo vértice.
  final int priority;

  Set<AnatomicalZone> get resolvedZones =>
      affectedZones.isEmpty ? {primaryZone} : affectedZones;
}

/// Contexto geométrico para resolução de intents.
class FaceAnatomyContext {
  const FaceAnatomyContext({
    required this.face,
    required this.imageSize,
    required this.mesh,
    this.intensityScale = 1.0,
    this.linkEyes = true,
  });

  final FaceMeshResult face;
  final Size imageSize;
  final TriMesh mesh;

  /// Fator do ToolGate (yaw, rosto pequeno, oclusão).
  final double intensityScale;
  final bool linkEyes;
}
