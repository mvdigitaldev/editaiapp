import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/datasources/legal_documents_datasource.dart';
import '../../data/models/legal_document_model.dart';

final _legalDocumentsDataSourceProvider =
    Provider<LegalDocumentsDataSource>((ref) {
  return LegalDocumentsDataSourceImpl(Supabase.instance.client);
});

class LegalDocumentPage extends ConsumerStatefulWidget {
  final String slug;

  const LegalDocumentPage({super.key, required this.slug});

  @override
  ConsumerState<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends ConsumerState<LegalDocumentPage> {
  LegalDocumentModel? _document;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ds = ref.read(_legalDocumentsDataSourceProvider);
      final doc = await ds.getBySlug(widget.slug);
      setState(() {
        _document = doc;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _document?.title ?? '',
                      style: AppTextStyles.headingSmall.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Não foi possível carregar o documento.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadDocument,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final doc = _document!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContent(doc.content, isDark),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Última atualização: ${DateFormat('dd/MM/yyyy').format(doc.updatedAt)}',
              style: AppTextStyles.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildContent(String content, bool isDark) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 12));
        continue;
      }

      final trimmed = line.trim();

      if (_isSectionTitle(trimmed)) {
        widgets.add(const SizedBox(height: 20));
        widgets.add(
          Text(
            trimmed,
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
              fontSize: 16,
            ),
          ),
        );
        widgets.add(const SizedBox(height: 8));
      } else if (_isDocumentTitle(trimmed)) {
        widgets.add(
          Text(
            trimmed,
            style: AppTextStyles.headingMedium.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
        );
        widgets.add(const SizedBox(height: 4));
      } else {
        widgets.add(
          Text(
            trimmed,
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
              height: 1.6,
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  bool _isSectionTitle(String line) {
    return RegExp(r'^\d+\.').hasMatch(line) &&
        !RegExp(r'^\d+\.\d+').hasMatch(line) &&
        line.length < 60;
  }

  bool _isDocumentTitle(String line) {
    return line.startsWith('Política de Privacidade') ||
        line.startsWith('Termos de Uso');
  }
}
