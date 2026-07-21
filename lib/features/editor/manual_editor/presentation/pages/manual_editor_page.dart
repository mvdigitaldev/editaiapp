import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../presentation/utils/edit_submission_helpers.dart';
import '../../config/manual_editor_config.dart';
import '../../di/manual_editor_providers.dart';

/// Editor manual com pro_image_editor — export → nuvem → /comparison.
class ManualEditorPage extends ConsumerStatefulWidget {
  const ManualEditorPage({
    super.key,
    required this.imagePath,
    required this.originalBytes,
  });

  final String imagePath;
  final Uint8List originalBytes;

  @override
  ConsumerState<ManualEditorPage> createState() => _ManualEditorPageState();
}

class _ManualEditorPageState extends ConsumerState<ManualEditorPage> {
  bool _isSaving = false;

  Future<void> _handleEditingComplete(Uint8List editedBytes) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(manualEditRepositoryProvider);
      final result = await repository.saveEditedImage(
        editedJpeg: editedBytes,
        originalBytes: widget.originalBytes,
        clientRequestId: const Uuid().v4(),
      );

      await trackAcceptedEdit(
        ref,
        editId: result.editId,
        operationType: 'manual_edit',
        status: 'completed',
      );

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/comparison',
        (route) => route.settings.name == '/home' || route.isFirst,
        arguments: <String, dynamic>{
          'editId': result.editId,
          'before': widget.imagePath,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      var message = 'Não foi possível salvar a edição. Tente novamente.';
      if (error is DioException) {
        final status = error.response?.statusCode;
        final data = error.response?.data;
        if (status == 403) {
          final code = data is Map ? data['code'] : null;
          if (code == 'storage_limit_reached') {
            message =
                'Limite de armazenamento atingido. Exclua fotos na galeria para salvar novas.';
          } else if (data is Map && data['error'] is String) {
            message = data['error'] as String;
          }
        } else if (data is Map && data['error'] is String) {
          message = data['error'] as String;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text(
                'Salvando na nuvem...',
                style: TextStyle(color: AppColors.textLight),
              ),
            ],
          ),
        ),
      );
    }

    return ProImageEditor.file(
      File(widget.imagePath),
      configs: buildManualEditorConfigs(),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: _handleEditingComplete,
        onCloseEditor: (_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }
}
