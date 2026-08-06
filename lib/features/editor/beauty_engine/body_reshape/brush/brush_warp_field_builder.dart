import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/warp_field.dart';

/// Modo de operação do pincel de deformação corporal.
enum WarpBrushMode {
  /// Empurra pixels na direção do arrasto (estilo Facetune Reshape).
  push,

  /// Expande radialmente a partir do centro do pincel.
  expand,

  /// Encolhe radialmente em direção ao centro.
  pinch,

  /// Restaura (atenuação do campo existente sob o pincel).
  restore,
}

/// Um traço de pincel em coordenadas normalizadas [0,1].
class WarpStroke {
  const WarpStroke({
    required this.points,
    required this.radiusNormalized,
    required this.strength,
    this.mode = WarpBrushMode.push,
  });

  /// Pontos do traço em UV normalizado (ordem temporal).
  final List<Offset> points;

  /// Raio do pincel como fração da menor dimensão da imagem.
  final double radiusNormalized;

  /// Intensidade [0,1].
  final double strength;

  final WarpBrushMode mode;

  bool get isEmpty => points.length < 2 && mode == WarpBrushMode.push;

  WarpStroke copyWith({
    List<Offset>? points,
    double? radiusNormalized,
    double? strength,
    WarpBrushMode? mode,
  }) {
    return WarpStroke(
      points: points ?? this.points,
      radiusNormalized: radiusNormalized ?? this.radiusNormalized,
      strength: strength ?? this.strength,
      mode: mode ?? this.mode,
    );
  }
}

/// Acumula [WarpStroke]s em um [WarpField] com semântica inversa
/// (`src = p + d`) compatível com o shader de remap.
class BrushWarpFieldBuilder {
  const BrushWarpFieldBuilder({
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.maxDragFraction = 0.06,
  });

  final int gridWidth;
  final int gridHeight;

  /// Cap do deslocamento por traço como fração da menor dimensão.
  final double maxDragFraction;

  /// Constrói campo a partir de uma lista de traços.
  WarpField build({
    required List<WarpStroke> strokes,
    required Size imageSize,
    MeshRegion region = MeshRegion.torso,
  }) {
    final cellCount = gridWidth * gridHeight;
    final disp = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);

    if (strokes.isEmpty) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    final minDim = math.min(imageSize.width, imageSize.height);
    var maxIntensity = 0.0;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }
      maxIntensity = math.max(maxIntensity, stroke.strength);
      _applyStroke(
        stroke: stroke,
        disp: disp,
        mask: mask,
        imageSize: imageSize,
        minDim: minDim,
      );
    }

    var active = 0;
    for (final m in mask) {
      if (m > 1e-6) {
        active++;
      }
    }

    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: disp,
      mask: mask,
      imageSize: imageSize,
      region: region,
      intensity: maxIntensity.clamp(0.0, 1.0),
      passId: 'brush_warp',
      activeCellCount: active,
    );
  }

  void _applyStroke({
    required WarpStroke stroke,
    required Float32List disp,
    required Float32List mask,
    required Size imageSize,
    required double minDim,
  }) {
    final radiusPx = (stroke.radiusNormalized * minDim).clamp(4.0, minDim * 0.35);
    final maxDrag = minDim * maxDragFraction * stroke.strength.clamp(0.0, 1.0);
    final points = stroke.points;

    // Segmentos entre pontos consecutivos (ou ponto único para expand/pinch).
    final segments = <(Offset, Offset)>[];
    if (points.length == 1) {
      segments.add((points.first, points.first));
    } else {
      for (var i = 1; i < points.length; i++) {
        segments.add((points[i - 1], points[i]));
      }
    }

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final nx = gx / (gridWidth - 1);
        final ny = gy / (gridHeight - 1);
        final px = nx * imageSize.width;
        final py = ny * imageSize.height;
        final cell = Offset(px, py);
        final idx = gy * gridWidth + gx;

        var accumDx = 0.0;
        var accumDy = 0.0;
        var accumMask = 0.0;

        for (final (a, b) in segments) {
          final aPx = Offset(a.dx * imageSize.width, a.dy * imageSize.height);
          final bPx = Offset(b.dx * imageSize.width, b.dy * imageSize.height);
          final closest = _closestOnSegment(cell, aPx, bPx);
          final dist = (cell - closest).distance;
          if (dist >= radiusPx) {
            continue;
          }
          final u = 1.0 - dist / radiusPx;
          final falloff = u * u * (3 - 2 * u); // smoothstep
          final w = falloff * stroke.strength;

          late final Offset delta;
          switch (stroke.mode) {
            case WarpBrushMode.push:
              final drag = bPx - aPx;
              final dragLen = drag.distance;
              if (dragLen < 1e-6) {
                continue;
              }
              // Campo inverso: empurrar conteúdo na direção do arrasto
              // ⇒ amostrar da origem oposta (d = −drag).
              final scale = math.min(1.0, maxDrag / dragLen);
              delta = Offset(-drag.dx * scale * w, -drag.dy * scale * w);
            case WarpBrushMode.expand:
              final fromCenter = cell - aPx;
              final len = fromCenter.distance;
              if (len < 1e-6) {
                continue;
              }
              final dir = Offset(fromCenter.dx / len, fromCenter.dy / len);
              // Expandir visualmente: amostrar mais perto do centro (d inward).
              delta = Offset(-dir.dx * maxDrag * w, -dir.dy * maxDrag * w);
            case WarpBrushMode.pinch:
              final fromCenter = cell - aPx;
              final len = fromCenter.distance;
              if (len < 1e-6) {
                continue;
              }
              final dir = Offset(fromCenter.dx / len, fromCenter.dy / len);
              // Encolher: amostrar mais longe do centro (d outward).
              delta = Offset(dir.dx * maxDrag * w, dir.dy * maxDrag * w);
            case WarpBrushMode.restore:
              // Atenua campo existente sob o pincel.
              disp[idx * 2] *= (1.0 - w);
              disp[idx * 2 + 1] *= (1.0 - w);
              mask[idx] *= (1.0 - w * 0.85);
              continue;
          }

          accumDx += delta.dx;
          accumDy += delta.dy;
          // Máscara = alcance do pincel (a força já está no delta). Incluir
          // strength aqui atenuaria o traço 2× via edgeScale² do shader.
          accumMask = math.max(accumMask, falloff);
        }

        if (accumMask <= 0) {
          continue;
        }
        disp[idx * 2] += accumDx;
        disp[idx * 2 + 1] += accumDy;
        mask[idx] = math.min(1.0, math.max(mask[idx], accumMask));
      }
    }
  }

  static Offset _closestOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) {
      return a;
    }
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    return Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  }
}

/// Histórico simples de traços com undo.
class BrushStrokeHistory {
  BrushStrokeHistory({this.maxEntries = 32});

  final int maxEntries;
  final List<WarpStroke> _strokes = [];

  List<WarpStroke> get strokes => List.unmodifiable(_strokes);

  bool get canUndo => _strokes.isNotEmpty;

  void add(WarpStroke stroke) {
    _strokes.add(stroke);
    while (_strokes.length > maxEntries) {
      _strokes.removeAt(0);
    }
  }

  WarpStroke? undo() {
    if (_strokes.isEmpty) {
      return null;
    }
    return _strokes.removeLast();
  }

  void clear() => _strokes.clear();

  WarpField buildField({
    required Size imageSize,
    BrushWarpFieldBuilder builder = const BrushWarpFieldBuilder(),
  }) {
    return builder.build(strokes: _strokes, imageSize: imageSize);
  }
}
