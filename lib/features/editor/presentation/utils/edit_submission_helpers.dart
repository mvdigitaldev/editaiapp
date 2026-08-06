import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../providers/active_edits_provider.dart';

/// Mensagem padrão do teto de armazenamento, no formato `usadas/máximo`.
String storageLimitMessage({
  required int storedCount,
  required int maxPhotos,
}) {
  return 'Armazenamento cheio ($storedCount/$maxPhotos fotos). '
      'Exclua fotos na galeria para salvar novas.';
}

/// Extrai a mensagem de limite a partir da resposta 403 da edge function.
String? storageLimitMessageFromError(Object error) {
  if (error is! DioException || error.response?.statusCode != 403) {
    return null;
  }
  final data = error.response?.data;
  if (data is! Map || data['code'] != 'storage_limit_reached') {
    return null;
  }

  final stored = (data['stored_photos_count'] as num?)?.toInt();
  final max = (data['max_photos'] as num?)?.toInt();
  if (stored != null && max != null) {
    return storageLimitMessage(storedCount: stored, maxPhotos: max);
  }
  if (data['error'] is String) {
    return data['error'] as String;
  }
  return 'Armazenamento cheio. Exclua fotos na galeria para salvar novas.';
}

/// Exibe o aviso de teto de armazenamento do plano com atalho para a galeria.
///
/// Retorna `false` quando o erro tem outra causa, para o chamador seguir com o
/// tratamento genérico. Nada é apagado automaticamente — só impede o save.
bool showStorageLimitFeedback(BuildContext context, Object error) {
  final message = storageLimitMessageFromError(error);
  if (message == null) return false;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Galeria',
        onPressed: () => Navigator.of(context).pushNamed('/gallery'),
      ),
    ),
  );
  return true;
}

String? readAcceptedEditId(Map<String, dynamic>? data) {
  if (data == null) return null;
  final raw = data['edit_id'];
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return null;
}

String readAcceptedStatus(Map<String, dynamic>? data) {
  final raw = data?['status'];
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return 'queued';
}

DateTime? readAcceptedAt(Map<String, dynamic>? data) {
  final raw = data?['accepted_at'];
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

Future<void> trackAcceptedEdit(
  WidgetRef ref, {
  required String editId,
  required String operationType,
  String status = 'queued',
  DateTime? acceptedAt,
}) async {
  await ref.read(activeEditsProvider.notifier).trackEdit(
        editId: editId,
        operationType: operationType,
        status: status,
        createdAt: acceptedAt,
      );
  ref.invalidate(creditsUsageProvider);
  ref.invalidate(planLimitsProvider);
}

void openProcessingPage(
  BuildContext context, {
  required String editId,
  String? beforePath,
  String? status,
}) {
  if (status == 'completed') {
    Navigator.of(context).pushNamed(
      '/comparison',
      arguments: <String, dynamic>{
        'editId': editId,
        if (beforePath != null && beforePath.isNotEmpty) 'before': beforePath,
      },
    );
    return;
  }

  if (status == 'failed') {
    Navigator.of(context).pushNamed(
      '/edit-detail',
      arguments: editId,
    );
    return;
  }

  Navigator.of(context).pushReplacementNamed(
    '/processing',
    arguments: <String, dynamic>{
      'editId': editId,
      if (beforePath != null && beforePath.isNotEmpty) 'beforePath': beforePath,
    },
  );
}
