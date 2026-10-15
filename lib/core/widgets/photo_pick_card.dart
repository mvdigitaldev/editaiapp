import 'package:flutter/material.dart';

import '../theme/brand_visual.dart';

/// Cartão único para escolher a foto que vai ser editada.
class PhotoPickCard extends StatelessWidget {
  const PhotoPickCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Ink(
              decoration: BoxDecoration(
                color: const Color(0xFFE7F3FE),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white),
                boxShadow: [
                  BoxShadow(
                    color: BrandVisual.blue.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/home/escolha_foto.png',
                      height: 168,
                      fit: BoxFit.contain,
                    ),
                    Text(
                      'Escolha uma foto',
                      textAlign: TextAlign.center,
                      style:
                          BrandVisual.title(size: 22, color: BrandVisual.navy),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Toque aqui para selecionar\numa foto da sua galeria.',
                      textAlign: TextAlign.center,
                      style: BrandVisual.text(
                        size: 15,
                        height: 1.35,
                        color: BrandVisual.navy.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
