import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class MultiUploadArea extends StatefulWidget {
  final List<String> imagePaths;
  final ValueChanged<List<String>> onChanged;
  final int maxCount;

  const MultiUploadArea({
    super.key,
    required this.imagePaths,
    required this.onChanged,
    this.maxCount = 8,
  });

  @override
  State<MultiUploadArea> createState() => _MultiUploadAreaState();
}

class _MultiUploadAreaState extends State<MultiUploadArea> {
  Future<void> _pickImage() async {
    if (widget.imagePaths.length >= widget.maxCount) return;
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image != null && mounted) {
      final updated = List<String>.from(widget.imagePaths)..add(image.path);
      widget.onChanged(updated);
    }
  }

  void _removeAt(int index) {
    final updated = List<String>.from(widget.imagePaths)..removeAt(index);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paths = widget.imagePaths;
    final canAdd = paths.length < widget.maxCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.4),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Imagens (até ${widget.maxCount})',
            style: AppTextStyles.labelLarge.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: paths.length + (canAdd ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == paths.length) {
                return GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.4),
                      ),
                    ),
                    child: Icon(
                      Icons.add_photo_alternate,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                );
              }
              final path = paths[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeAt(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.overlay,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
