import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import 'photo_pick_card.dart';

class UploadArea extends StatelessWidget {
  final String? imagePath;
  final Function(File) onImageSelected;
  final String title;
  final String subtitle;

  const UploadArea({
    super.key,
    this.imagePath,
    required this.onImageSelected,
    this.title = 'Começar nova edição',
    this.subtitle = 'Toque para carregar uma foto',
  });

  Future<void> _pickImage(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image != null) {
      onImageSelected(File(image.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (imagePath != null) {
      return GestureDetector(
        onTap: () => _pickImage(context),
        child: Container(
          width: double.infinity,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.4),
              width: 2,
              style: BorderStyle.solid,
            ),
            image: DecorationImage(
              image: FileImage(File(imagePath!)),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.overlay,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PhotoPickCard(onTap: () => _pickImage(context));
  }
}
