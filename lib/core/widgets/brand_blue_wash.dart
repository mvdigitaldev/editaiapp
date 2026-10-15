import 'package:flutter/material.dart';

import '../theme/brand_visual.dart';

/// Manchas de azul do guia. Chegam ao topo e descem pelas laterais,
/// no branco e no azul-escuro.
class BrandBlueWash extends StatelessWidget {
  const BrandBlueWash({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final height = size.height;
    final right = isDark
        ? BrandVisual.blue.withValues(alpha: 0.72)
        : const Color(0xFF8EC8FF).withValues(alpha: 0.95);
    final left = isDark
        ? BrandVisual.blue.withValues(alpha: 0.48)
        : const Color(0xFFB9DCFF).withValues(alpha: 0.9);
    final lower = isDark
        ? BrandVisual.blue.withValues(alpha: 0.34)
        : const Color(0xFFD6EBFF).withValues(alpha: 0.95);

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -height * 0.06,
            left: -width * 0.34,
            child: _WashBlob(
              width: width * 0.78,
              height: height * 0.5,
              color: left,
            ),
          ),
          Positioned(
            top: -height * 0.08,
            right: -width * 0.22,
            child: _WashBlob(
              width: width * 0.86,
              height: height * 0.46,
              color: right,
            ),
          ),
          Positioned(
            top: height * 0.3,
            left: -width * 0.38,
            child: _WashBlob(
              width: width * 0.62,
              height: height * 0.38,
              color: lower,
            ),
          ),
          Positioned(
            top: height * 0.22,
            right: -width * 0.42,
            child: _WashBlob(
              width: width * 0.5,
              height: height * 0.3,
              color: lower,
            ),
          ),
          Positioned(
            top: height * 0.07,
            right: width * 0.06,
            child: const BrandSparkle(size: 18, color: BrandVisual.blue),
          ),
          Positioned(
            top: height * 0.11,
            right: width * 0.14,
            child: BrandSparkle(
              size: 12,
              color: BrandVisual.blue.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class BrandSparkle extends StatelessWidget {
  const BrandSparkle({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SparklePainter(color),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..moveTo(center.dx, 0)
      ..quadraticBezierTo(center.dx, center.dy, size.width, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, size.height)
      ..quadraticBezierTo(center.dx, center.dy, 0, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _WashBlob extends StatelessWidget {
  const _WashBlob({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: color.a * 0.55),
            color.withValues(alpha: 0),
          ],
          stops: const [0.15, 0.5, 1],
        ),
      ),
    );
  }
}
