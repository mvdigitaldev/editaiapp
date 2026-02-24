import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/datasources/app_settings_datasource.dart';
import '../../data/datasources/faq_datasource.dart';
import '../../data/models/faq_item_model.dart';

final _appSettingsProvider = Provider<AppSettingsDataSource>((ref) {
  return AppSettingsDataSourceImpl(Supabase.instance.client);
});

final _faqDataSourceProvider = Provider<FaqDataSource>((ref) {
  return FaqDataSourceImpl(Supabase.instance.client);
});

class HelpCenterPage extends ConsumerStatefulWidget {
  const HelpCenterPage({super.key});

  @override
  ConsumerState<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends ConsumerState<HelpCenterPage> {
  List<FaqItemModel> _faqs = [];
  String? _whatsapp;
  String? _email;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = ref.read(_appSettingsProvider);
      final faqDs = ref.read(_faqDataSourceProvider);

      final results = await Future.wait([
        faqDs.getActiveFaqs(),
        settings.getValue('support_whatsapp'),
        settings.getValue('support_email'),
      ]);

      setState(() {
        _faqs = results[0] as List<FaqItemModel>;
        _whatsapp = results[1] as String?;
        _email = results[2] as String?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openWhatsApp() async {
    if (_whatsapp == null || _whatsapp!.isEmpty) return;

    final url = Uri.parse(
      'https://wa.me/$_whatsapp?text=${Uri.encodeComponent('Olá, preciso de ajuda com o EditAI')}',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openEmail() async {
    if (_email == null || _email!.isEmpty) return;

    final url = Uri.parse(
      'mailto:$_email?subject=${Uri.encodeComponent('Suporte EditAI')}',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
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
                  const Spacer(),
                  Text(
                    'Central de Ajuda',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark
                          ? AppColors.textLight
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
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
                'Não foi possível carregar a central de ajuda.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Perguntas Frequentes',
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Encontre respostas para as dúvidas mais comuns',
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (_faqs.isEmpty)
            _buildEmptyFaqs(isDark)
          else
            ..._faqs.map((faq) => _FaqCard(faq: faq, isDark: isDark)),
          const SizedBox(height: 32),
          _buildContactSection(isDark),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEmptyFaqs(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'Nenhuma pergunta frequente disponível no momento.',
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildContactSection(bool isDark) {
    final hasWhatsApp = _whatsapp != null && _whatsapp!.isNotEmpty;
    final hasEmail = _email != null && _email!.isNotEmpty;

    if (!hasWhatsApp && !hasEmail) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark
            : AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark
              : AppColors.primary.withOpacity(0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.support_agent,
            size: 40,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Precisa de mais ajuda?',
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Entre em contato com nossa equipe de suporte',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (hasWhatsApp)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(Icons.chat, size: 20),
                label: const Text('Falar no WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (hasWhatsApp && hasEmail) const SizedBox(height: 12),
          if (hasEmail)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openEmail,
                icon: Icon(Icons.email_outlined,
                    size: 20, color: AppColors.primary),
                label: Text(
                  'Enviar E-mail',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FaqCard extends StatefulWidget {
  final FaqItemModel faq;
  final bool isDark;

  const _FaqCard({required this.faq, required this.isDark});

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark
              ? AppColors.surfaceDark
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isExpanded
                ? AppColors.primary.withOpacity(0.3)
                : (widget.isDark ? AppColors.borderDark : AppColors.border),
          ),
          boxShadow: widget.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(
              _isExpanded
                  ? Icons.help
                  : Icons.help_outline,
              color: AppColors.primary,
              size: 22,
            ),
            title: Text(
              widget.faq.question,
              style: AppTextStyles.bodyMedium.copyWith(
                color: widget.isDark
                    ? AppColors.textLight
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: widget.isDark
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
              ),
            ),
            onExpansionChanged: (expanded) {
              setState(() => _isExpanded = expanded);
            },
            children: [
              Text(
                widget.faq.answer,
                style: AppTextStyles.bodySmall.copyWith(
                  color: widget.isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
