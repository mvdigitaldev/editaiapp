import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/beauty_preset.dart';

/// Export/import de presets via arquivo JSON (Sprint 22).
class PresetFileService {
  const PresetFileService();

  Future<void> sharePresetJson(BeautyPreset preset) async {
    final directory = await getTemporaryDirectory();
    final safeName = preset.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${directory.path}/$safeName.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(preset.toJson()),
    );

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: preset.name,
      text: 'Beauty preset: ${preset.name}',
    );
  }

  Future<Map<String, dynamic>?> pickPresetJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes != null) {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }

    final path = file.path;
    if (path == null) {
      return null;
    }

    final raw = await File(path).readAsString();
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
