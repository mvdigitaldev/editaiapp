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
import '../../../filter_presets/filter_grade_provider.dart';
import '../../../filter_presets/filter_preset.dart';
import '../../../filter_presets/filter_preset_mapper.dart';
import '../../../filter_presets/filter_presets_provider.dart';

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
  FilterPreset? _selectedEditAiPreset;
  List<FilterPreset> _editAiPresets = const [];

  Future<void> _handleEditingComplete(Uint8List editedBytes) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      var outputBytes = editedBytes;
      final selected = _selectedEditAiPreset;
      if (selected != null && selected.needsFullGradeExport) {
        final engine = ref.read(filterGradeEngineProvider);
        outputBytes = await engine.applyPresetForManualEditorExport(
          imageBytes: editedBytes,
          preset: selected,
          quality: 92,
        );
      }

      final repository = ref.read(manualEditRepositoryProvider);
      final result = await repository.saveEditedImage(
        editedJpeg: outputBytes,
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
      final storageMessage = storageLimitMessageFromError(error);
      if (storageMessage != null) {
        message = storageMessage;
      } else if (error is DioException) {
        final data = error.response?.data;
        if (data is Map && data['error'] is String) {
          message = data['error'] as String;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  ProImageEditorCallbacks _buildCallbacks() {
    return ProImageEditorCallbacks(
      onImageEditingComplete: _handleEditingComplete,
      onCloseEditor: (_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      filterEditorCallbacks: FilterEditorCallbacks(
        onFilterChanged: (filter) {
          _selectedEditAiPreset = findFilterPresetByFilterModel(
            _editAiPresets,
            filter,
          );
        },
      ),
    );
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

    final presetsAsync = ref.watch(filterPresetsProvider);
    final customFiltersAsync = ref.watch(manualEditorCustomFiltersProvider);

    return presetsAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (_, __) => customFiltersAsync.when(
        loading: () => Scaffold(
          backgroundColor: AppColors.backgroundDark,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
        error: (_, __) => ProImageEditor.file(
          File(widget.imagePath),
          configs: buildManualEditorConfigs(),
          callbacks: _buildCallbacks(),
        ),
        data: (customFilters) => ProImageEditor.file(
          File(widget.imagePath),
          configs: buildManualEditorConfigs(extraFilters: customFilters),
          callbacks: _buildCallbacks(),
        ),
      ),
      data: (presets) {
        _editAiPresets = presets;
        return customFiltersAsync.when(
          loading: () => Scaffold(
            backgroundColor: AppColors.backgroundDark,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (_, __) => ProImageEditor.file(
            File(widget.imagePath),
            configs: buildManualEditorConfigs(),
            callbacks: _buildCallbacks(),
          ),
          data: (customFilters) => ProImageEditor.file(
            File(widget.imagePath),
            configs: buildManualEditorConfigs(extraFilters: customFilters),
            callbacks: _buildCallbacks(),
          ),
        );
      },
    );
  }
}
