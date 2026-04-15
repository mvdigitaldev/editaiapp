import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../providers/active_edits_provider.dart';

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
