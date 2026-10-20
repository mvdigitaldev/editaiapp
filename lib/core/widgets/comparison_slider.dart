import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_compare_slider/image_compare_slider.dart';
import '../theme/app_colors.dart';

class ComparisonSlider extends StatelessWidget {
  final String? beforeImagePath;
  final String? beforeImageUrl;
  final String? beforeAsset;
  final String? afterImagePath;
  final String? afterImageUrl;
  final String? afterAsset;
  final double initialPosition;
  final BoxFit fit;

  const ComparisonSlider({
    super.key,
    this.beforeImagePath,
    this.beforeImageUrl,
    this.beforeAsset,
    this.afterImagePath,
    this.afterImageUrl,
    this.afterAsset,
    this.initialPosition = 0.5,
    this.fit = BoxFit.contain,
  });

  Image _buildImage(String? path, String? url, String? asset) {
    const alignment = Alignment.center;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (path != null) {
      return Image.file(
        File(path),
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (url != null) {
      return Image.network(
        url,
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, progress) =>
            progress == null
                ? child
                : Container(
                    color: AppColors.border,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.border,
          child: const Center(child: Icon(Icons.error)),
        ),
      );
    }
    return Image.network(
      'https://placehold.co/1x1/e0e0e0/e0e0e0',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemOne = _buildImage(beforeImagePath, beforeImageUrl, beforeAsset);
    final itemTwo = _buildImage(afterImagePath, afterImageUrl, afterAsset);

    // O pacote volta a desenhar com BoxFit.contain e ignora o tamanho.
    // Com outro fit, as duas fotos ocupam o mesmo retângulo.
    Widget fill(Image image) {
      return SizedBox.expand(
        child: Image(
          image: image.image,
          fit: fit,
          alignment: Alignment.center,
          gaplessPlayback: true,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox.expand(
        child: ImageCompareSlider(
          itemOne: itemOne,
          itemTwo: itemTwo,
          itemOneBuilder: fit == BoxFit.contain ? null : (_, __) => fill(itemOne),
          itemTwoBuilder: fit == BoxFit.contain ? null : (_, __) => fill(itemTwo),
          handlePosition: initialPosition,
          photoRadius: BorderRadius.zero,
          fillHandle: true,
          handleSize: const Size(28, 28),
          handleRadius: BorderRadius.circular(14),
          dividerColor: Colors.white,
          dividerWidth: 1.5,
          handleColor: AppColors.primary,
          handleOutlineColor: Colors.white,
        ),
      ),
    );
  }
}
