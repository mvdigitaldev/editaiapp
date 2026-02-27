import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:saver_gallery/saver_gallery.dart';

Future<bool> saveLocalImageToGallery(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }

    final bytes = await file.readAsBytes();
    final fileName = 'editai_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await SaverGallery.saveImage(
      Uint8List.fromList(bytes),
      fileName: fileName,
      skipIfExists: false,
    );

    return result.isSuccess;
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
    final fileName = 'editai_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await SaverGallery.saveImage(
      bytes,
      fileName: fileName,
      skipIfExists: false,
    );

    return result.isSuccess;
  } catch (_) {
    return false;
  }
}

