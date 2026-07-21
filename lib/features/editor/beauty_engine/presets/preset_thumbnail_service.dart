import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Gera e persiste thumbnails locais para presets do usuário (Sprint 22).
class PresetThumbnailService {
  const PresetThumbnailService({Future<Directory> Function()? resolveDirectory})
      : _resolveDirectory = resolveDirectory;

  final Future<Directory> Function()? _resolveDirectory;

  static const thumbSize = 256;

  Future<String?> saveFromJpeg({
    required String presetId,
    required Uint8List jpegBytes,
  }) async {
    if (jpegBytes.isEmpty) {
      return null;
    }

    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      return null;
    }

    final thumb = img.copyResize(
      decoded,
      width: thumbSize,
      height: thumbSize,
      interpolation: img.Interpolation.linear,
    );
    final bytes = Uint8List.fromList(img.encodeJpg(thumb, quality: 82));

    final directory = await resolveDirectory();
    final file = File('${directory.path}/$presetId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteForPreset(String presetId) async {
    final directory = await resolveDirectory();
    final file = File('${directory.path}/$presetId.jpg');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> resolveDirectory() async {
    if (_resolveDirectory != null) {
      final directory = await _resolveDirectory!();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/beauty_presets/thumbnails');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
