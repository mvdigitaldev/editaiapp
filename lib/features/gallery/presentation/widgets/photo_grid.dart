import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/entities/gallery_photo.dart';
import 'photo_card.dart';

class PhotoGrid extends StatelessWidget {
  final List<GalleryPhoto> photos;

  const PhotoGrid({
    super.key,
    required this.photos,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        return PhotoCard(photo: photos[index]);
      },
    );
  }
}
