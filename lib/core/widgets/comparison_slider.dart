import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';

class ComparisonSlider extends StatefulWidget {
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

  @override
  State<ComparisonSlider> createState() => _ComparisonSliderState();
}

class _ComparisonSliderState extends State<ComparisonSlider> {
  late double _position;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  Widget _buildImage(String? path, String? url) {
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
      );
    }
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppColors.border,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => Container(
          color: AppColors.border,
          child: const Icon(Icons.error),
        ),
      );
    }
    return Container(color: AppColors.border);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanUpdate: (details) {
            final localPosition = details.localPosition.dx;
            final width = constraints.maxWidth;
            final newPosition = (localPosition / width).clamp(0.0, 1.0);
            setState(() {
              _position = newPosition;
            });
          },
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // After image (full)
                Positioned.fill(
                  child: _buildImage(
                    widget.afterImagePath,
                    widget.afterImageUrl,
                  ),
                ),
                // Before image (clipped)
                Positioned.fill(
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: _position,
                      child: _buildImage(
                        widget.beforeImagePath,
                        widget.beforeImageUrl,
                      ),
                    ),
                  ),
                ),
                // Handle
                Positioned(
                  left: _position * constraints.maxWidth - 18,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.unfold_more,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                // Labels
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.overlay,
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'ANTES',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.overlay,
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'DEPOIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
