import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/datasources/payments_datasource.dart';
import '../../data/models/payment_model.dart';

final _paymentsDataSourceProvider = Provider<PaymentsDataSource>((ref) {
  return PaymentsDataSourceImpl(Supabase.instance.client);
});

class PaymentHistoryPage extends ConsumerStatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  ConsumerState<PaymentHistoryPage> createState() =>
      _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends ConsumerState<PaymentHistoryPage> {
  static const _pageSize = 10;

  final List<PaymentModel> _payments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ds = ref.read(_paymentsDataSourceProvider);
      final result = await ds.getPayments(offset: 0, limit: _pageSize);
      setState(() {
        _payments
          ..clear()
          ..addAll(result);
        _hasMore = result.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final ds = ref.read(_paymentsDataSourceProvider);
      final result = await ds.getPayments(
        offset: _payments.length,
        limit: _pageSize,
      );
      setState(() {
        _payments.addAll(result);
        _hasMore = result.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar mais pagamentos: $e')),
        );
      }
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
                    'Histórico de Pagamentos',
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
                'Não foi possível carregar os pagamentos.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadPayments,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_payments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: isDark
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhum pagamento encontrado',
                style: AppTextStyles.headingSmall.copyWith(
                  color: isDark
                      ? AppColors.textLight
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seus pagamentos aparecerão aqui.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _payments.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _payments.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: _isLoadingMore
                  ? CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                    )
                  : TextButton(
                      onPressed: _loadMore,
                      child: Text(
                        'Ver mais',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PaymentCard(
            payment: _payments[index],
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
        );
      },
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentModel payment;
  final bool isDark;

  const _PaymentCard({required this.payment, required this.isDark});

  Color _secondaryColor() =>
      isDark ? AppColors.textTertiary : AppColors.textSecondary;

  TextStyle _labelStyle() => AppTextStyles.labelSmall.copyWith(
        color: _secondaryColor(),
      );

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(payment.paymentStatus);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusInfo.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusInfo.icon, color: statusInfo.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.formattedAmount,
                      style: AppTextStyles.headingSmall.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      payment.formattedDateWithTime,
                      style: _labelStyle(),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusInfo.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  payment.statusLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: statusInfo.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.backgroundDark : AppColors.backgroundLight)
                  .withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.credit_card_outlined,
                  label: 'Método',
                  value: payment.paymentMethod,
                  labelStyle: _labelStyle(),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.store_outlined,
                  label: 'Provedor',
                  value: payment.paymentProvider,
                  labelStyle: _labelStyle(),
                ),
                if (payment.paidAt != null &&
                    payment.paidAt != payment.createdAt) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.check_circle_outline,
                    label: 'Pago em',
                    value: payment.formattedPaidAt!,
                    labelStyle: _labelStyle(),
                  ),
                ],
                if (payment.shortExternalId != null) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.tag_outlined,
                    label: 'ID',
                    value: payment.shortExternalId!,
                    labelStyle: _labelStyle(),
                  ),
                ],
                if (payment.invoiceUrl != null &&
                    payment.invoiceUrl!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _openUrl(payment.invoiceUrl!),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ver fatura',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static _StatusInfo _statusInfo(String status) {
    switch (status) {
      case 'paid':
        return _StatusInfo(Icons.check_circle, AppColors.success);
      case 'pending':
        return _StatusInfo(Icons.schedule, AppColors.warning);
      case 'failed':
        return _StatusInfo(Icons.cancel, AppColors.error);
      case 'refunded':
        return _StatusInfo(Icons.replay, AppColors.info);
      default:
        return _StatusInfo(Icons.help_outline, AppColors.textSecondary);
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final TextStyle labelStyle;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: labelStyle.color),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(label, style: labelStyle),
        ),
        Expanded(
          child: Text(
            value,
            style: labelStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StatusInfo {
  final IconData icon;
  final Color color;

  const _StatusInfo(this.icon, this.color);
}
