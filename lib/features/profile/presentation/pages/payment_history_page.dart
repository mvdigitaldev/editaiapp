import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      child: Row(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        payment.formattedAmount,
                        style: AppTextStyles.headingSmall.copyWith(
                          color: isDark
                              ? AppColors.textLight
                              : AppColors.textPrimary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.credit_card,
                      size: 14,
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${payment.paymentMethod} · ${payment.paymentProvider}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isDark
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      payment.formattedDate,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _StatusInfo _statusInfo(String status) {
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

class _StatusInfo {
  final IconData icon;
  final Color color;

  const _StatusInfo(this.icon, this.color);
}
