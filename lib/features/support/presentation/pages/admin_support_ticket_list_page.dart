import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../data/models/support_ticket_model.dart';
import '../../data/models/support_ticket_status.dart';
import '../providers/support_provider.dart';
import 'support_ticket_list_page.dart';

class AdminSupportTicketListPage extends ConsumerStatefulWidget {
  const AdminSupportTicketListPage({super.key});

  @override
  ConsumerState<AdminSupportTicketListPage> createState() =>
      _AdminSupportTicketListPageState();
}

class _AdminSupportTicketListPageState
    extends ConsumerState<AdminSupportTicketListPage> {
  List<SupportTicketModel> _tickets = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedStatus;

  static const List<String?> _filters = [
    null,
    ...SupportTicketStatus.values,
  ];

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ds = ref.read(supportDataSourceProvider);
      final tickets = await ds.getAdminTickets(status: _selectedStatus);
      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = postgrestUserMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _openTicket(String ticketId) async {
    await Navigator.of(context).pushNamed(
      '/support-ticket',
      arguments: {'ticketId': ticketId},
    );
    if (mounted) _loadTickets();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    'Chamados',
                    style: AppTextStyles.headingMedium.copyWith(
                      color:
                          isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = filter == _selectedStatus;
                  return ChoiceChip(
                    label: Text(
                      filter == null
                          ? 'Todos'
                          : SupportTicketStatus.label(filter),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _selectedStatus = filter);
                      _loadTickets();
                    },
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _filters.length,
              ),
            ),
            const SizedBox(height: 12),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadTickets,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tickets.isEmpty) {
      return Center(
        child: Text(
          'Nenhum chamado encontrado para este filtro.',
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTickets,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ticket = _tickets[index];
          return _AdminSupportTicketCard(
            ticket: ticket,
            isDark: isDark,
            onTap: () => _openTicket(ticket.id),
          );
        },
      ),
    );
  }
}

class _AdminSupportTicketCard extends StatelessWidget {
  final SupportTicketModel ticket;
  final bool isDark;
  final VoidCallback onTap;

  const _AdminSupportTicketCard({
    required this.ticket,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SupportTicketCard(
          ticket: ticket,
          isDark: isDark,
          onTap: onTap,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${ticket.userName?.trim().isNotEmpty == true ? ticket.userName!.trim() : 'Usuário'}'
              '${ticket.userEmail?.trim().isNotEmpty == true ? ' • ${ticket.userEmail!.trim()}' : ''}',
              style: AppTextStyles.labelSmall.copyWith(
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
