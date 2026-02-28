import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/datasources/credit_transactions_datasource.dart';
import '../../data/models/credit_transaction_model.dart';

final _creditTransactionsDataSourceProvider =
    Provider<CreditTransactionsDataSource>((ref) {
  return CreditTransactionsDataSourceImpl(Supabase.instance.client);
});

class CreditHistoryPage extends ConsumerStatefulWidget {
  const CreditHistoryPage({super.key});

  @override
  ConsumerState<CreditHistoryPage> createState() => _CreditHistoryPageState();
}

class _CreditHistoryPageState extends ConsumerState<CreditHistoryPage> {
  static const _pageSize = 15;

  late int _selectedYear;
  late int _selectedMonth;
  int _total = 0;
  final List<CreditTransactionModel> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadMonth();
  }

  bool get _canGoNext {
    final now = DateTime.now();
    return _selectedYear < now.year ||
        (_selectedYear == now.year && _selectedMonth < now.month);
  }

  bool get _canGoPrevious {
    final now = DateTime.now();
    final earliestYear = now.year - 1;
    final earliestMonth = now.month;
    return _selectedYear > earliestYear ||
        (_selectedYear == earliestYear && _selectedMonth > earliestMonth);
  }

  void _goNext() {
    if (!_canGoNext) return;
    setState(() {
      if (_selectedMonth == 12) {
        _selectedYear++;
        _selectedMonth = 1;
      } else {
        _selectedMonth++;
      }
    });
    _loadMonth();
  }

  void _goPrevious() {
    if (!_canGoPrevious) return;
    setState(() {
      if (_selectedMonth == 1) {
        _selectedYear--;
        _selectedMonth = 12;
      } else {
        _selectedMonth--;
      }
    });
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _transactions.clear();
      _hasMore = true;
    });

    try {
      final ds = ref.read(_creditTransactionsDataSourceProvider);
      final total = await ds.getMonthlyUsageTotal(_selectedYear, _selectedMonth);
      final list = await ds.getUsageTransactionsForMonth(
        _selectedYear,
        _selectedMonth,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _total = total;
        _transactions.addAll(list);
        _hasMore = list.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
      final ds = ref.read(_creditTransactionsDataSourceProvider);
      final list = await ds.getUsageTransactionsForMonth(
        _selectedYear,
        _selectedMonth,
        offset: _transactions.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _transactions.addAll(list);
        _hasMore = list.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar mais: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String get _monthLabel {
    final date = DateTime(_selectedYear, _selectedMonth);
    return DateFormat('MMM yyyy', 'pt_BR').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                    color: isDark
                        ? AppColors.textLight
                        : AppColors.textPrimary,
                  ),
                  const Spacer(),
                  Text(
                    'Histórico de créditos',
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
    if (_isLoading && _transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Carregando...',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null && _transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Não foi possível carregar o histórico.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadMonth,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthSelector(isDark),
          const SizedBox(height: 20),
          _buildTotalCard(isDark),
          const SizedBox(height: 24),
          Text(
            'Uso no mês',
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _transactions.isEmpty
              ? _buildEmptyState(isDark)
              : _buildTransactionList(isDark),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _canGoPrevious ? _goPrevious : null,
            icon: Icon(
              Icons.chevron_left,
              color: _canGoPrevious
                  ? (isDark ? AppColors.textLight : AppColors.textPrimary)
                  : AppColors.textTertiary,
            ),
          ),
          Text(
            _monthLabel,
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          IconButton(
            onPressed: _canGoNext ? _goNext : null,
            icon: Icon(
              Icons.chevron_right,
              color: _canGoNext
                  ? (isDark ? AppColors.textLight : AppColors.textPrimary)
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.15),
            AppColors.primary.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bolt, color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_total créditos gastos',
                  style: AppTextStyles.headingMedium.copyWith(
                    color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'em $_monthLabel',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_outlined,
              size: 56,
              color: isDark
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum uso de créditos em $_monthLabel',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
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

  Widget _buildTransactionList(bool isDark) {
    return Column(
      children: [
        ..._transactions.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CreditTransactionCard(transaction: t, isDark: isDark),
          ),
        ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: _isLoadingMore
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
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
          ),
      ],
    );
  }
}

class _CreditTransactionCard extends StatelessWidget {
  final CreditTransactionModel transaction;
  final bool isDark;

  const _CreditTransactionCard({
    required this.transaction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final used = transaction.creditsUsed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
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
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.edit_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description?.isNotEmpty == true
                      ? transaction.description!
                      : 'Uso em edição',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isDark
                        ? AppColors.textLight
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.formattedDateTime,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            used == 1 ? '1 crédito' : '$used créditos',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
