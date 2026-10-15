import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/admin_usage_overview.dart';

class AdminUsagePage extends ConsumerStatefulWidget {
  const AdminUsagePage({super.key});

  @override
  ConsumerState<AdminUsagePage> createState() => _AdminUsagePageState();
}

class _AdminUsagePageState extends ConsumerState<AdminUsagePage> {
  AdminUsageOverview? _overview;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isAdmin = ref.read(authStateProvider).user?.isAdmin ?? false;
    if (!isAdmin) {
      setState(() {
        _isLoading = false;
        _error = 'Sem permissão para esta ação.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response =
          await Supabase.instance.client.rpc('get_admin_usage_overview');
      final json = response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);
      if (!mounted) return;
      setState(() {
        _overview = AdminUsageOverview.fromJson(json);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = postgrestUserMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textLight : BrandVisual.navy;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    'Uso',
                    style: BrandVisual.title(size: 22, color: titleColor),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: _OverviewBody(overview: _overview!),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.overview});

  final AdminUsageOverview overview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.textTertiary : const Color(0xFF5C6B82);
    final maxTool = overview.tools.fold<int>(
      0,
      (max, tool) => tool.total > max ? tool.total : max,
    );
    final updated = overview.generatedAt == null
        ? null
        : DateFormat("d 'de' MMM, HH:mm", 'pt_BR').format(
            overview.generatedAt!.toLocal(),
          );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          'Online é quem renovou a sessão nos últimos ${overview.onlineWindowMinutes} min. Os números de edição são dos últimos 30 dias.',
          style: BrandVisual.text(size: 14, color: muted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Online agora',
                value: '${overview.onlineUsers}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Ativos hoje',
                value: '${overview.activeToday}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Edições em 30 dias',
                value: '${overview.edits30d}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Créditos gastos',
                value: '${overview.credits30d}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Hoje ${overview.editsToday} · 7 dias ${overview.edits7d} · ${overview.editors30d} pessoas editaram · ${overview.failed30d} falhas',
          style: BrandVisual.text(size: 13, color: muted),
        ),
        const SizedBox(height: 24),
        Text(
          'FERRAMENTAS',
          style: BrandVisual.text(
            size: 12,
            weight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (var i = 0; i < overview.tools.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                _ToolRow(tool: overview.tools[i], maxTotal: maxTool),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'CONVITES DO PRO',
          style: BrandVisual.text(
            size: 12,
            weight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < overview.bannerClicks.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                _BannerClickRow(clicks: overview.bannerClicks[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'PLANOS',
          style: BrandVisual.text(
            size: 12,
            weight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < overview.plans.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                ListTile(
                  title: Text(
                    overview.plans[i].name,
                    style: BrandVisual.text(
                      size: 16,
                      weight: FontWeight.w700,
                      color: isDark ? AppColors.textLight : BrandVisual.navy,
                    ),
                  ),
                  trailing: Text(
                    '${overview.plans[i].users}',
                    style: BrandVisual.title(size: 20, color: BrandVisual.blue),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (updated != null) ...[
          const SizedBox(height: 16),
          Text(
            'Atualizado $updated',
            style: BrandVisual.text(size: 12, color: muted),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: BrandVisual.title(
              size: 28,
              color: isDark ? AppColors.textLight : BrandVisual.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: BrandVisual.text(
              size: 13,
              color: isDark ? AppColors.textTertiary : const Color(0xFF5C6B82),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerClickRow extends StatelessWidget {
  const _BannerClickRow({required this.clicks});

  final AdminBannerClicks clicks;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.textTertiary : const Color(0xFF5C6B82);
    final average = clicks.people == 0
        ? 'Ninguém clicou'
        : '${clicks.people} pessoas · ${clicks.clicks} cliques · ${NumberFormat('#0.0', 'pt_BR').format(clicks.clicksPerPerson)} por pessoa';
    return ListTile(
      title: Text(
        clicks.label,
        style: BrandVisual.text(
          size: 16,
          weight: FontWeight.w700,
          color: isDark ? AppColors.textLight : BrandVisual.navy,
        ),
      ),
      subtitle: Text(
        average,
        style: BrandVisual.text(size: 13, color: muted),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool, required this.maxTotal});

  final AdminToolUsage tool;
  final int maxTotal;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textLight : BrandVisual.navy;
    final muted = isDark ? AppColors.textTertiary : const Color(0xFF5C6B82);
    final fraction = maxTotal == 0 ? 0.0 : tool.total / maxTotal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tool.label,
                  style: BrandVisual.text(
                    size: 16,
                    weight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
              Text(
                '${tool.total}',
                style: BrandVisual.title(size: 18, color: BrandVisual.blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor:
                  isDark ? AppColors.borderDark : const Color(0xFFE6EEF8),
              color: BrandVisual.blue,
            ),
          ),
          const SizedBox(height: 8),
            Text(
              '${tool.completed} concluídas · ${tool.credits} créditos gastos · ${tool.creditCostLabel}',
              style: BrandVisual.text(size: 13, color: muted),
            ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
