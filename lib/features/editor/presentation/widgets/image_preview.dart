import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ImagePreview extends StatelessWidget {
  final String imagePath;

  const ImagePreview({
    super.key,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: imagePath.startsWith('http')
          ? CachedNetworkImage(
              imageUrl: imagePath,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            )
          : Image.asset(
              imagePath,
              fit: BoxFit.contain,
            ),
    );
  }
}
