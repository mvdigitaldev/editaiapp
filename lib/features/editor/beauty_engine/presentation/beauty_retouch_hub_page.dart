import 'package:flutter/material.dart';

import '../../../../core/theme/brand_visual.dart';
import '../../../../core/widgets/brand_blue_wash.dart';

/// Escolha entre retoque de rosto e ajuste de corpo. As rotas não mudam.
class BeautyRetouchHubPage extends StatelessWidget {
  const BeautyRetouchHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : BrandVisual.navy;

    return Scaffold(
      backgroundColor: isDark ? BrandVisual.navy : Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        foregroundColor: onSurface,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: BrandBlueWash(isDark: isDark)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, kToolbarHeight, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Retoques',
                        style: BrandVisual.title(size: 32, color: onSurface),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: _Sparkle(size: 16, color: BrandVisual.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'O que você quer ajustar?',
                    style: BrandVisual.title(size: 22, color: onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escolha uma categoria. As edições são processadas no '
                    'dispositivo e não usam créditos de IA.',
                    style: BrandVisual.text(
                      size: 15,
                      height: 1.35,
                      color: onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _RetouchCard(
                    isDark: isDark,
                    title: 'Rosto, pele e maquiagem',
                    description:
                        'Suavização, detalhes faciais e retoque com nosso editor.',
                    icon: Icons.face_retouching_natural,
                    imageAsset: 'assets/home/retoque_rosto.png',
                    imageAspect: 408 / 456,
                    arrowX: 0.7917,
                    arrowY: 0.8289,
                    arrowDiameter: 0.2843,
                    route: '/face-retouch',
                  ),
                  const SizedBox(height: 14),
                  _RetouchCard(
                    isDark: isDark,
                    title: 'Ajustar corpo',
                    description:
                        'Cintura, braços, pernas, altura e proporções corporais.',
                    icon: Icons.accessibility_new,
                    imageAsset: 'assets/home/retoque_corpo.png',
                    imageAspect: 312 / 512,
                    arrowX: 0.6923,
                    arrowY: 0.8262,
                    arrowDiameter: 0.4487,
                    route: '/body-reshape',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetouchCard extends StatelessWidget {
  const _RetouchCard({
    required this.isDark,
    required this.title,
    required this.description,
    required this.icon,
    required this.imageAsset,
    required this.imageAspect,
    required this.arrowX,
    required this.arrowY,
    required this.arrowDiameter,
    required this.route,
  });

  final bool isDark;
  final String title;
  final String description;
  final IconData icon;
  final String imageAsset;

  /// Largura / altura do ficheiro. A imagem entra inteira, à direita.
  final double imageAspect;

  /// Centro da seta, em fracção da imagem.
  final double arrowX;
  final double arrowY;

  /// Diâmetro da seta em fracção da largura da imagem.
  final double arrowDiameter;
  final String route;

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      BrandVisual.blue.withValues(alpha: isDark ? 0.28 : 0.16),
      isDark ? BrandVisual.navy : Colors.white,
    );
    final titleColor = isDark ? Colors.white : BrandVisual.navy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(route),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? BrandVisual.blue.withValues(alpha: 0.4)
                  : Colors.white,
            ),
            boxShadow: [
              BoxShadow(
                color: BrandVisual.blue.withValues(alpha: isDark ? 0.22 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 1.62,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final imageWidth = height * imageAspect;
                  final button = imageWidth * arrowDiameter + 8;
                  final centerX = (width - imageWidth) + arrowX * imageWidth;
                  final centerY = arrowY * height;

                  return Stack(
                    children: [
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: imageWidth,
                        child: Image.asset(
                          imageAsset,
                          fit: BoxFit.fill,
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 14,
                        bottom: 14,
                        width: width * 0.52,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: width * 0.52,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: BrandVisual.blue,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  title,
                                  style: BrandVisual.title(
                                    size: 20,
                                    height: 1.15,
                                    color: titleColor,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: BrandVisual.text(
                                    size: 14,
                                    height: 1.3,
                                    color: titleColor.withValues(alpha: 0.72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: centerX - button / 2,
                        top: centerY - button / 2,
                        width: button,
                        height: button,
                        child: IgnorePointer(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: BrandVisual.blue,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: button * 0.42,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size, required this.color});

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
