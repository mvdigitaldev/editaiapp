import 'dart:ui' as ui;

import '../body_reshape/rendering/fragment_program_warp_backend.dart';

/// Um remap já empacotado. [amplitude] é o uniform: 1 reproduz o campo
/// gravado na textura. O arrasto muda só este número.
class DragGpuLayer {
  DragGpuLayer({
    required this.displacement,
    required this.scale,
    required this.owner,
    required Map<String, double> packed,
  }) : packed = Map<String, double>.of(packed);

  ui.Image displacement;
  ui.Offset scale;
  final String owner;
  Map<String, double> packed;
  double amplitude = 1;

  void replace({
    required ui.Image displacement,
    required ui.Offset scale,
    required Map<String, double> packed,
  }) {
    this.displacement.dispose();
    this.displacement = displacement;
    this.scale = scale;
    this.packed = Map<String, double>.of(packed);
    amplitude = 1;
  }

  void dispose() => displacement.dispose();
}

/// Foto e deslocamentos que ficam na GPU enquanto o dedo não solta.
class DragGpuSession {
  DragGpuSession({
    required this.source,
    required this.mask,
    required this.influence,
    required this.protection,
    required this.layers,
    required this.dragKey,
    required this.width,
    required this.height,
    required this.frozen,
    required this.face,
    required this.pose,
    required this.maskSource,
    this.activeEntryFace,
    this.activeFaceStage,
  });

  final ui.Image source;
  final ui.Image mask;
  final ui.Image influence;
  final ui.Image protection;
  final List<DragGpuLayer> layers;
  final String dragKey;
  final int width;
  final int height;

  /// Parâmetros que não são do slider a ser arrastado.
  final String frozen;
  final Object? face;
  final Object? pose;
  final Object? maskSource;

  /// Cara com que o efeito arrastado foi medido. Os de jusante ficam nesta
  /// geometria até o dedo soltar.
  final Object? activeEntryFace;
  final int? activeFaceStage;

  bool get hasActiveLayer => layers.any((layer) => layer.owner == dragKey);

  Map<String, double> get activePacked {
    for (final layer in layers) {
      if (layer.owner == dragKey) {
        return layer.packed;
      }
    }
    return const {};
  }

  void setAmplitude(double scale) {
    for (final layer in layers) {
      if (layer.owner == dragKey) {
        layer.amplitude = scale;
      }
    }
  }

  /// Encadeia os remaps. Não lê os pixels de volta. Devolve `null` se o
  /// shader não estiver disponível ou se nenhum passe mexer na foto.
  Future<ui.Image?> paint(FragmentProgramWarpBackend backend) async {
    ui.Image current = source;
    var ownsCurrent = false;
    for (final layer in layers) {
      if (layer.amplitude.abs() <= 1e-8) {
        continue;
      }
      final next = await backend.paintDisplacement(
        source: current,
        displacement: layer.displacement,
        mask: mask,
        influence: influence,
        protection: protection,
        scale: layer.scale,
        amplitude: layer.amplitude,
      );
      if (next == null) {
        if (ownsCurrent) {
          current.dispose();
        }
        return null;
      }
      if (ownsCurrent) {
        current.dispose();
      }
      current = next;
      ownsCurrent = true;
    }
    if (!ownsCurrent) {
      return null;
    }
    return current;
  }

  void dispose() {
    for (final layer in layers) {
      layer.dispose();
    }
    source.dispose();
    mask.dispose();
    influence.dispose();
    protection.dispose();
  }
}

/// Razão única `actual / gravado` para as chaves do efeito. `null` quando
/// os lados não andam juntos — aí o campo activo é reempacotado e os
/// outros ficam.
double? dragUniformScale(
  Map<String, double> packed,
  Map<String, double> current,
  List<String> keys,
) {
  double? scale;
  for (final key in keys) {
    final before = packed[key] ?? 0;
    final after = current[key] ?? 0;
    if (before.abs() <= 1e-8 && after.abs() <= 1e-8) {
      continue;
    }
    if (before.abs() <= 1e-8) {
      return null;
    }
    final ratio = after / before;
    if (scale == null) {
      scale = ratio;
    } else if ((ratio - scale).abs() > 1e-4) {
      return null;
    }
  }
  return scale ?? 1;
}
