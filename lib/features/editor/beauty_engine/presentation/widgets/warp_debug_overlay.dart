import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/warp_field.dart';
import '../../warp/anatomy/face_warp_debug_stats.dart';

/// Overlay de debug warp — bounds da influência + magnitude (Sprint 30).
class WarpDebugOverlay extends StatelessWidget {
  const WarpDebugOverlay({
    super.key,
    required this.field,
    required this.boxSize,
    this.vertexStats,
  });

  final WarpField? field;
  final Size boxSize;
  final FaceWarpDebugStats? vertexStats;

  @override
  Widget build(BuildContext context) {
    final stats = vertexStats;
    final hasField = field != null && !field!.isIdentity;
    final hasVertex = stats != null && stats.hasDisplacement;

    if (!hasField && !hasVertex) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      size: boxSize,
      painter: _WarpDebugPainter(
        field: hasField ? field : null,
        vertexStats: stats,
      ),
    );
  }
}

class _WarpDebugPainter extends CustomPainter {
  _WarpDebugPainter({
    required this.field,
    required this.vertexStats,
  });

  final WarpField? field;
  final FaceWarpDebugStats? vertexStats;

  static const _maskThreshold = 0.02;

  @override
  void paint(Canvas canvas, Size size) {
    if (field != null) {
      _paintField(canvas, size, field!);
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: _statsLine(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);

    textPainter.paint(canvas, const Offset(8, 8));
  }

  void _paintField(Canvas canvas, Size size, WarpField field) {
    final bounds = _activeBounds(field);
    if (bounds != null) {
      final rect = Rect.fromLTRB(
        bounds.left * size.width,
        bounds.top * size.height,
        bounds.right * size.width,
        bounds.bottom * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xCC00E5FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    _paintGrid(canvas, size, field);
  }

  void _paintGrid(Canvas canvas, Size size, WarpField field) {
    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final maxMag = field.maxDisplacementMagnitude.clamp(1.0, double.infinity);

    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        final mask = field.mask[y * gw + x];
        if (mask < _maskThreshold) {
          continue;
        }
        final idx = (y * gw + x) * 2;
        final dx = field.displacement[idx];
        final dy = field.displacement[idx + 1];
        final mag = math.sqrt(dx * dx + dy * dy);
        final t = (mag / maxMag).clamp(0.0, 1.0);

        final cx = (x / (gw - 1)) * size.width;
        final cy = (y / (gh - 1)) * size.height;
        final cellW = size.width / (gw - 1);
        final cellH = size.height / (gh - 1);

        canvas.drawRect(
          Rect.fromLTWH(cx - cellW * 0.5, cy - cellH * 0.5, cellW, cellH),
          Paint()
            ..color = Color.lerp(
              const Color(0x3300E676),
              const Color(0xCCFF5252),
              t,
            )!
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  Rect? _activeBounds(WarpField field) {
    final gw = field.gridWidth;
    final gh = field.gridHeight;
    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    var found = false;

    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        if (field.mask[y * gw + x] < _maskThreshold) {
          continue;
        }
        found = true;
        final nx = x / (gw - 1);
        final ny = y / (gh - 1);
        minX = math.min(minX, nx);
        minY = math.min(minY, ny);
        maxX = math.max(maxX, nx);
        maxY = math.max(maxY, ny);
      }
    }

    if (!found) {
      return null;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  String _statsLine() {
    final parts = <String>[];

    final vs = vertexStats;
    if (vs != null && vs.hasDisplacement) {
      parts.add(
        '${vs.movedVertices} vértices · Δv ${vs.vertexMaxPx.toStringAsFixed(1)}px',
      );
    }

    final f = field;
    if (f != null && !f.isIdentity) {
      final active = f.activeCellCount ??
          f.mask.where((m) => m >= _maskThreshold).length;
      parts.add(
        'grade Δmax ${f.maxDisplacementMagnitude.toStringAsFixed(1)}px · '
        '${f.gridWidth}×${f.gridHeight} · $active células',
      );
    } else if (parts.isEmpty) {
      parts.add('sem warp ativo');
    }

    return parts.join(' · ');
  }

  @override
  bool shouldRepaint(covariant _WarpDebugPainter oldDelegate) {
    return oldDelegate.field != field || oldDelegate.vertexStats != vertexStats;
  }
}
