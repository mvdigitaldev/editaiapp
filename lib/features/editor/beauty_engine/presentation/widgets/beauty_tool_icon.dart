import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Glifos de linha estilo Meitu para as ferramentas de Rosto e Pele.
///
/// Desenhados em 24×24, tingíveis. Sem assets. Sem SVG.
abstract final class BeautyToolIcons {
  static const keys = <String>{
    'head',
    'eyebrow_height',
    'eyebrow_width',
    'eyebrow_end',
    'hairline',
    'jaw',
    'jaw_angle',
    'chin',
    'v_chin',
    'v_shape',
    'cheekbone',
    'skin_smooth',
    'skin_whitening',
    'remove_acne',
    'remove_wrinkles',
    'remove_dark_circles',
    'skin_shine',
    'teeth_whitening',
    'blush',
    'contour',
    'eyebrows',
    'eyelashes',
    'iris_enhance',
  };

  static bool hasGlyph(String key) => keys.contains(key);
}

/// Ícone vectorial de uma ferramenta beauty, desenhado em 24×24.
class BeautyToolIcon extends StatelessWidget {
  const BeautyToolIcon({
    super.key,
    required this.toolKey,
    required this.color,
    this.size = 26,
  });

  final String toolKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BeautyToolIconPainter(toolKey: toolKey, color: color),
    );
  }
}

class _BeautyToolIconPainter extends CustomPainter {
  const _BeautyToolIconPainter({
    required this.toolKey,
    required this.color,
  });

  final String toolKey;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    _paintGlyph(canvas, paint);
    canvas.restore();
  }

  void _paintGlyph(Canvas canvas, Paint paint) {
    switch (toolKey) {
      case 'head':
        _paintHead(canvas, paint);
      case 'eyebrow_height':
        _paintEyebrowHeight(canvas, paint);
      case 'eyebrow_width':
        _paintEyebrowWidth(canvas, paint);
      case 'eyebrow_end':
        _paintEyebrowEnd(canvas, paint);
      case 'hairline':
        _paintHairline(canvas, paint);
      case 'jaw':
        _paintJaw(canvas, paint);
      case 'jaw_angle':
        _paintJawAngle(canvas, paint);
      case 'chin':
        _paintChin(canvas, paint);
      case 'v_chin':
        _paintVChin(canvas, paint);
      case 'v_shape':
        _paintVShape(canvas, paint);
      case 'cheekbone':
        _paintCheekbone(canvas, paint);
      case 'skin_smooth':
        _paintSkinSmooth(canvas, paint);
      case 'skin_whitening':
        _paintSkinWhitening(canvas, paint);
      case 'remove_acne':
        _paintRemoveAcne(canvas, paint);
      case 'remove_wrinkles':
        _paintRemoveWrinkles(canvas, paint);
      case 'remove_dark_circles':
        _paintDarkCircles(canvas, paint);
      case 'skin_shine':
        _paintSkinShine(canvas, paint);
      case 'teeth_whitening':
        _paintTeeth(canvas, paint);
      case 'blush':
        _paintBlush(canvas, paint);
      case 'contour':
        _paintContour(canvas, paint);
      case 'eyebrows':
        _paintEyebrows(canvas, paint);
      case 'eyelashes':
        _paintEyelashes(canvas, paint);
      case 'iris_enhance':
        _paintIris(canvas, paint);
    }
  }

  /// Oval partilhado: mais largo em cima, a estreitar para o queixo.
  Path _faceOutline() {
    final path = Path();
    path.moveTo(12, 2.4);
    path.cubicTo(16.9, 2.4, 20.4, 6.2, 20.4, 10.8);
    path.cubicTo(20.4, 15.4, 17.2, 19.6, 12, 21.8);
    path.cubicTo(6.8, 19.6, 3.6, 15.4, 3.6, 10.8);
    path.cubicTo(3.6, 6.2, 7.1, 2.4, 12, 2.4);
    path.close();
    return path;
  }

  void _paintFace(Canvas canvas, Paint paint) {
    canvas.drawPath(_faceOutline(), paint);
  }

  void _arrow(
    Canvas canvas,
    Paint paint,
    Offset from,
    Offset to, {
    double head = 2.15,
  }) {
    canvas.drawLine(from, to, paint);
    final dir = to - from;
    final len = dir.distance;
    if (len < 0.001) {
      return;
    }
    final n = dir / len;
    final perp = Offset(-n.dy, n.dx);
    canvas.drawLine(to, to - n * head + perp * (head * 0.62), paint);
    canvas.drawLine(to, to - n * head - perp * (head * 0.62), paint);
  }

  void _doubleArrow(Canvas canvas, Paint paint, Offset a, Offset b) {
    _arrow(canvas, paint, a, b);
    _arrow(canvas, paint, b, a);
  }

  void _strokeDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 1.45,
    double gap = 1.05,
  }) {
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      var draw = true;
      while (dist < metric.length) {
        final next = math.min(dist + (draw ? dash : gap), metric.length);
        if (draw) {
          canvas.drawPath(metric.extractPath(dist, next), paint);
        }
        dist = next;
        draw = !draw;
      }
    }
  }

  void _sparkle(Canvas canvas, Paint paint, Offset c, double r) {
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), paint);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), paint);
    final d = r * 0.58;
    canvas.drawLine(
        Offset(c.dx - d, c.dy - d), Offset(c.dx + d, c.dy + d), paint);
    canvas.drawLine(
        Offset(c.dx + d, c.dy - d), Offset(c.dx - d, c.dy + d), paint);
  }

  Path _eye({required Offset center, double w = 5.4, double h = 2.45}) {
    final path = Path();
    path.moveTo(center.dx - w, center.dy);
    path.cubicTo(
      center.dx - w * 0.35,
      center.dy - h,
      center.dx + w * 0.35,
      center.dy - h,
      center.dx + w,
      center.dy,
    );
    path.cubicTo(
      center.dx + w * 0.35,
      center.dy + h,
      center.dx - w * 0.35,
      center.dy + h,
      center.dx - w,
      center.dy,
    );
    path.close();
    return path;
  }

  // --- Rosto ---------------------------------------------------------------

  void _paintHead(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    _arrow(canvas, paint, const Offset(12, 6.2), const Offset(12, 1.5));
    _arrow(canvas, paint, const Offset(12, 17.8), const Offset(12, 22.6));
    _arrow(canvas, paint, const Offset(6.4, 11.2), const Offset(1.8, 11.2));
    _arrow(canvas, paint, const Offset(17.6, 11.2), const Offset(22.2, 11.2));
  }

  void _paintEyebrowWidth(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final left = Path()
      ..moveTo(5.0, 9.6)
      ..cubicTo(7.0, 7.4, 9.4, 7.2, 10.8, 8.9);
    final right = Path()
      ..moveTo(19.0, 9.6)
      ..cubicTo(17.0, 7.4, 14.6, 7.2, 13.2, 8.9);
    final thick = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.55
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(left, thick);
    canvas.drawPath(right, thick);
    final leftDash = Path()
      ..moveTo(4.6, 8.5)
      ..cubicTo(7.0, 6.1, 9.6, 5.9, 11.2, 7.9);
    final rightDash = Path()
      ..moveTo(19.4, 8.5)
      ..cubicTo(17.0, 6.1, 14.4, 5.9, 12.8, 7.9);
    _strokeDashed(canvas, leftDash, paint);
    _strokeDashed(canvas, rightDash, paint);
  }

  void _paintEyebrowEnd(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final left = Path()
      ..moveTo(5.2, 9.4)
      ..cubicTo(7.0, 7.6, 9.2, 7.4, 10.6, 8.8);
    final right = Path()
      ..moveTo(18.8, 9.4)
      ..cubicTo(17.0, 7.6, 14.8, 7.4, 13.4, 8.8);
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    _arrow(canvas, paint, const Offset(8.2, 6.5), const Offset(10.8, 6.5));
    _arrow(canvas, paint, const Offset(15.8, 6.5), const Offset(13.2, 6.5));
  }

  void _paintEyebrowHeight(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final left = Path()
      ..moveTo(5.2, 9.4)
      ..cubicTo(7.0, 7.6, 9.2, 7.4, 10.6, 8.8);
    final right = Path()
      ..moveTo(18.8, 9.4)
      ..cubicTo(17.0, 7.6, 14.8, 7.4, 13.4, 8.8);
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    _doubleArrow(
      canvas,
      paint,
      const Offset(8.0, 6.6),
      const Offset(8.0, 3.2),
    );
    _doubleArrow(
      canvas,
      paint,
      const Offset(16.0, 6.6),
      const Offset(16.0, 3.2),
    );
  }

  void _paintHairline(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final cap = Path()
      ..moveTo(6.2, 6.4)
      ..quadraticBezierTo(12, 2.0, 17.8, 6.4);
    canvas.drawPath(cap, paint);
    _doubleArrow(
      canvas,
      paint,
      const Offset(12, 4.6),
      const Offset(12, 1.4),
    );
  }

  void _paintJaw(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    _arrow(canvas, paint, const Offset(3.0, 16.0), const Offset(6.6, 16.7));
    _arrow(canvas, paint, const Offset(21.0, 16.0), const Offset(17.4, 16.7));
  }

  void _paintJawAngle(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    canvas.drawLine(const Offset(6.2, 15.0), const Offset(7.6, 17.2), paint);
    canvas.drawLine(const Offset(17.8, 15.0), const Offset(16.4, 17.2), paint);
    _arrow(canvas, paint, const Offset(2.6, 13.8), const Offset(5.8, 15.8));
    _arrow(canvas, paint, const Offset(21.4, 13.8), const Offset(18.2, 15.8));
  }

  void _paintChin(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    _doubleArrow(
      canvas,
      paint,
      const Offset(12, 19.4),
      const Offset(12, 23.2),
    );
  }

  void _paintVChin(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final chin = Path()
      ..moveTo(7.6, 18.4)
      ..quadraticBezierTo(12, 22.4, 16.4, 18.4);
    _strokeDashed(canvas, chin, paint);
  }

  void _paintVShape(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    _arrow(canvas, paint, const Offset(5.6, 13.2), const Offset(9.6, 18.6));
    _arrow(canvas, paint, const Offset(18.4, 13.2), const Offset(14.4, 18.6));
  }

  void _paintCheekbone(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    canvas.drawLine(const Offset(6.4, 10.4), const Offset(8.4, 11.6), paint);
    canvas.drawLine(const Offset(17.6, 10.4), const Offset(15.6, 11.6), paint);
    _arrow(canvas, paint, const Offset(3.2, 12.8), const Offset(6.8, 10.6));
    _arrow(canvas, paint, const Offset(20.8, 12.8), const Offset(17.2, 10.6));
  }

  // --- Pele ----------------------------------------------------------------

  void _paintSkinSmooth(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final wave = Path()
      ..moveTo(7.2, 11.2)
      ..cubicTo(8.4, 10.2, 9.6, 12.2, 10.8, 11.2);
    canvas.drawPath(wave, paint);
    final wave2 = Path()
      ..moveTo(7.2, 13.4)
      ..cubicTo(8.4, 12.4, 9.6, 14.4, 10.8, 13.4);
    canvas.drawPath(wave2, paint);
  }

  void _paintSkinWhitening(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    _sparkle(canvas, paint, const Offset(8.4, 11.2), 2.1);
    _sparkle(canvas, paint, const Offset(16.2, 14.0), 1.4);
  }

  void _paintRemoveAcne(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    canvas.drawCircle(const Offset(8.6, 11.4), 1.15, paint);
    canvas.drawCircle(const Offset(15.8, 13.6), 0.95, paint);
    canvas.drawLine(const Offset(7.7, 10.5), const Offset(9.5, 12.3), paint);
  }

  void _paintRemoveWrinkles(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    canvas.drawLine(const Offset(8.0, 6.8), const Offset(16.0, 6.8), paint);
    canvas.drawLine(const Offset(8.6, 8.4), const Offset(15.4, 8.4), paint);
    final cheek = Path()
      ..moveTo(6.8, 12.6)
      ..quadraticBezierTo(8.4, 13.8, 9.6, 12.4);
    canvas.drawPath(cheek, paint);
  }

  void _paintDarkCircles(Canvas canvas, Paint paint) {
    canvas.drawPath(
      _eye(center: const Offset(8.2, 10.6), w: 3.6, h: 1.7),
      paint,
    );
    canvas.drawPath(
      _eye(center: const Offset(15.8, 10.6), w: 3.6, h: 1.7),
      paint,
    );
    final left = Path()
      ..moveTo(5.2, 13.0)
      ..quadraticBezierTo(8.2, 15.2, 11.0, 13.0);
    final right = Path()
      ..moveTo(13.0, 13.0)
      ..quadraticBezierTo(15.8, 15.2, 18.8, 13.0);
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
  }

  void _paintSkinShine(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    _sparkle(canvas, paint, const Offset(12, 7.4), 1.9);
    canvas.drawLine(const Offset(12, 9.6), const Offset(12, 13.8), paint);
  }

  void _paintTeeth(Canvas canvas, Paint paint) {
    final smile = Path()
      ..moveTo(5.2, 11.4)
      ..quadraticBezierTo(12, 18.8, 18.8, 11.4);
    canvas.drawPath(smile, paint);
    canvas.drawLine(const Offset(9.4, 13.8), const Offset(9.4, 16.2), paint);
    canvas.drawLine(const Offset(12.0, 14.4), const Offset(12.0, 16.8), paint);
    canvas.drawLine(const Offset(14.6, 13.8), const Offset(14.6, 16.2), paint);
    final upper = Path()
      ..moveTo(7.4, 13.0)
      ..quadraticBezierTo(12, 15.2, 16.6, 13.0);
    canvas.drawPath(upper, paint);
  }

  void _paintBlush(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(7.8, 13.2), width: 3.6, height: 2.2),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: const Offset(16.2, 13.2), width: 3.6, height: 2.2),
      paint,
    );
  }

  void _paintContour(Canvas canvas, Paint paint) {
    _paintFace(canvas, paint);
    final left = Path()
      ..moveTo(6.0, 9.6)
      ..cubicTo(5.2, 12.6, 6.4, 16.4, 8.4, 18.4);
    final right = Path()
      ..moveTo(18.0, 9.6)
      ..cubicTo(18.8, 12.6, 17.6, 16.4, 15.6, 18.4);
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
  }

  void _paintEyebrows(Canvas canvas, Paint paint) {
    final left = Path()
      ..moveTo(3.8, 12.4)
      ..cubicTo(6.2, 8.6, 9.4, 8.2, 11.2, 10.4);
    final right = Path()
      ..moveTo(20.2, 12.4)
      ..cubicTo(17.8, 8.6, 14.6, 8.2, 12.8, 10.4);
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
  }

  void _paintEyelashes(Canvas canvas, Paint paint) {
    canvas.drawPath(_eye(center: const Offset(12, 13.4)), paint);
    const lashes = <(Offset, Offset)>[
      (Offset(7.4, 12.2), Offset(6.4, 9.6)),
      (Offset(9.2, 11.2), Offset(8.6, 8.6)),
      (Offset(12.0, 10.9), Offset(12.0, 8.2)),
      (Offset(14.8, 11.2), Offset(15.4, 8.6)),
      (Offset(16.6, 12.2), Offset(17.6, 9.6)),
    ];
    for (final lash in lashes) {
      canvas.drawLine(lash.$1, lash.$2, paint);
    }
  }

  void _paintIris(Canvas canvas, Paint paint) {
    canvas.drawPath(_eye(center: const Offset(12, 12)), paint);
    canvas.drawCircle(const Offset(12, 12), 2.35, paint);
    canvas.drawCircle(const Offset(12, 12), 0.7, paint);
    _sparkle(canvas, paint, const Offset(13.1, 11.1), 1.05);
  }

  @override
  bool shouldRepaint(covariant _BeautyToolIconPainter oldDelegate) {
    return oldDelegate.toolKey != toolKey || oldDelegate.color != color;
  }
}
