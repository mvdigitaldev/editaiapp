import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

/// Upload de imagem para buckets públicos do catálogo (apenas admins têm política de escrita).
class AdminCatalogImageUpload {
  AdminCatalogImageUpload._();

  static const _uuid = Uuid();

  static String? _contentTypeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return null;
    }
  }

  static String _extFromXFile(XFile file) {
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'png';
    if (name.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  /// Abre a galeria, faz upload e devolve a URL pública, ou `null` se cancelar/erro.
  static Future<String?> pickAndUpload({
    required SupabaseClient client,
    required String bucket,
  }) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (file == null) return null;

    final ext = _extFromXFile(file);
    final contentType = _contentTypeForExt(ext);
    if (contentType == null ||
        !AppConfig.allowedImageTypes.contains(contentType)) {
      throw const FormatException(
        'Formato não suportado. Use JPEG, PNG ou WebP.',
      );
    }

    final bytes = await file.readAsBytes();
    // Alinhado ao file_size_limit do bucket (5 MB)
    const maxCatalogBytes = 5 * 1024 * 1024;
    if (bytes.length > maxCatalogBytes) {
      throw const FormatException('Imagem muito grande (máx. 5 MB).');
    }

    final path = '${_uuid.v4()}.$ext';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    return client.storage.from(bucket).getPublicUrl(path);
  }
}
