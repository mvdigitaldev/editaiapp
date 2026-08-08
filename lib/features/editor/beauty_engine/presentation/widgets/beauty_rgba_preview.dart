import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Preview interativo a partir de [ui.Image] RGBA — evita encode/decode JPEG.
class BeautyRgbaPreview extends StatelessWidget {
  const BeautyRgbaPreview({
    super.key,
    required this.image,
    this.fit = BoxFit.fill,
  });

  final ui.Image image;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return RawImage(
      image: image,
      fit: fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
