import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/dio_client.dart';
import 'export_pipeline.dart';

class ManualEditSaveRequest {
  const ManualEditSaveRequest({
    required this.editedBytes,
    required this.originalBytes,
    required this.width,
    required this.height,
    this.clientRequestId,
  });

  final Uint8List editedBytes;
  final Uint8List originalBytes;
  final int width;
  final int height;
  final String? clientRequestId;
}

class ManualEditSaveResult {
  const ManualEditSaveResult({
    required this.editId,
    required this.imageUrl,
    required this.originalImageUrl,
  });

  final String editId;
  final String imageUrl;
  final String originalImageUrl;
}

/// Persiste edição manual na nuvem via Edge Function.
class ManualEditDataSource {
  ManualEditDataSource({DioClient? dioClient})
      : _dio = (dioClient ?? DioClient()).instance;

  final Dio _dio;

  Future<ManualEditSaveResult> save(ManualEditSaveRequest request) async {
    final clientRequestId = request.clientRequestId ?? const Uuid().v4();

    final response = await _dio.post<Map<String, dynamic>>(
      '/functions/v1/salvar-edicao-manual',
      data: {
        'client_request_id': clientRequestId,
        'image_base64': base64Encode(request.editedBytes),
        'original_base64': base64Encode(request.originalBytes),
        'width': request.width,
        'height': request.height,
        'mime_type': 'image/jpeg',
        'file_size': request.editedBytes.length,
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 2),
      ),
    );

    final data = response.data;
    final editId = data?['edit_id'] as String?;
    final imageUrl = data?['image_url'] as String?;
    final originalImageUrl = data?['original_image_url'] as String?;

    if (editId == null || imageUrl == null || originalImageUrl == null) {
      throw StateError('Resposta inválida ao salvar edição manual');
    }

    return ManualEditSaveResult(
      editId: editId,
      imageUrl: imageUrl,
      originalImageUrl: originalImageUrl,
    );
  }
}

/// Orquestra export local + upload.
class ManualEditRepository {
  ManualEditRepository({
    ExportPipeline? exportPipeline,
    ManualEditDataSource? dataSource,
  })  : _exportPipeline = exportPipeline ?? ExportPipeline(),
        _dataSource = dataSource ?? ManualEditDataSource();

  final ExportPipeline _exportPipeline;
  final ManualEditDataSource _dataSource;

  Future<ManualEditSaveResult> saveEditedImage({
    required Uint8List editedJpeg,
    required Uint8List originalBytes,
    String? clientRequestId,
  }) async {
    final exported = await _exportPipeline.processEditedJpeg(editedJpeg);
    final original = await _exportPipeline.processOriginalJpeg(originalBytes);

    return _dataSource.save(
      ManualEditSaveRequest(
        editedBytes: exported.bytes,
        originalBytes: original.bytes,
        width: exported.width,
        height: exported.height,
        clientRequestId: clientRequestId,
      ),
    );
  }
}
