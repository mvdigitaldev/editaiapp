import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

Future<bool> saveLocalImageToGallery(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }

    final bytes = await file.readAsBytes();
    final name = 'editai_${DateTime.now().millisecondsSinceEpoch}';

    final result = await ImageGallerySaver.saveImage(
      Uint8List.fromList(bytes),
      name: name,
    );

    if (result is Map) {
      final success = result['isSuccess'];
      if (success is bool) return success;
    }
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> saveRemoteImageToGallery(String url) async {
  try {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );

    final data = response.data;
    if (data == null) return false;

    final bytes = Uint8List.fromList(data);
    final name = 'editai_${DateTime.now().millisecondsSinceEpoch}';

    final result = await ImageGallerySaver.saveImage(
      bytes,
      name: name,
    );

    if (result is Map) {
      final success = result['isSuccess'];
      if (success is bool) return success;
    }
    return true;
  } catch (_) {
    return false;
  }
}

