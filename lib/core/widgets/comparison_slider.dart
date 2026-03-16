import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_compare_slider/image_compare_slider.dart';
import '../theme/app_colors.dart';

class ComparisonSlider extends StatelessWidget {
  final String? beforeImagePath;
  final String? beforeImageUrl;
  final String? afterImagePath;
  final String? afterImageUrl;
  final double initialPosition;

  const ComparisonSlider({
    super.key,
    this.beforeImagePath,
    this.beforeImageUrl,
    this.afterImagePath,
    this.afterImageUrl,
    this.initialPosition = 0.5,
  });

  Image _buildImage(String? path, String? url) {
    const alignment = Alignment.center;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.contain,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.contain,
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
    final itemOne = _buildImage(beforeImagePath, beforeImageUrl);
    final itemTwo = _buildImage(afterImagePath, afterImageUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ImageCompareSlider(
          itemOne: itemOne,
          itemTwo: itemTwo,
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
