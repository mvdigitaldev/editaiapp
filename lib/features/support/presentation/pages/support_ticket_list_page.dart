import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../../core/utils/server_date_utils.dart';
import '../../data/models/support_ticket_model.dart';
import '../../data/models/support_ticket_status.dart';
import '../providers/support_provider.dart';

class SupportTicketListPage extends ConsumerStatefulWidget {
  const SupportTicketListPage({super.key});

  @override
  ConsumerState<SupportTicketListPage> createState() =>
      _SupportTicketListPageState();
}

class _SupportTicketListPageState extends ConsumerState<SupportTicketListPage> {
  List<SupportTicketModel> _tickets = [];
  bool _isLoading = true;
  String? _error;

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
      final tickets = await ds.getMyTickets();
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

  Future<void> _goToNewTicket() async {
    await Navigator.of(context).pushNamed('/support-tickets/new');
    if (mounted) _loadTickets();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToNewTicket,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Novo chamado'),
      ),
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
                    'Meus Chamados',
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.support_agent_outlined,
                size: 56,
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Você ainda não abriu nenhum chamado',
                textAlign: TextAlign.center,
                style: AppTextStyles.headingSmall.copyWith(
                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Quando precisar, abra um chamado e acompanhe toda a conversa por aqui.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color:
                      isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _goToNewTicket,
                child: const Text('Abrir primeiro chamado'),
              ),
            ],
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
          return SupportTicketCard(
            ticket: ticket,
            isDark: isDark,
            onTap: () => _openTicket(ticket.id),
          );
        },
      ),
    );
  }
}

class SupportTicketCard extends StatelessWidget {
  final SupportTicketModel ticket;
  final bool isDark;
  final VoidCallback onTap;

  const SupportTicketCard({
    super.key,
    required this.ticket,
    required this.isDark,
    required this.onTap,
  });

  Color _statusColor() {
    switch (ticket.status) {
      case SupportTicketStatus.novo:
        return const Color(0xFFE67E22);
      case SupportTicketStatus.aberto:
        return AppColors.primary;
      case SupportTicketStatus.aguardandoCliente:
        return const Color(0xFF8E44AD);
      case SupportTicketStatus.respondido:
        return const Color(0xFF16A085);
      case SupportTicketStatus.fechado:
        return const Color(0xFF7F8C8D);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (ticket.subject?.trim().isNotEmpty ?? false)
                        ? ticket.subject!.trim()
                        : 'Chamado #${ticket.id.substring(0, 8)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color:
                          isDark ? AppColors.textLight : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor().withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    SupportTicketStatus.label(ticket.status),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: _statusColor(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ticket.lastMessagePreview?.trim().isNotEmpty == true
                  ? ticket.lastMessagePreview!.trim()
                  : 'Sem mensagens ainda.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Atualizado em ${ServerDateUtils.formatForDisplay(ticket.lastMessageAt)}',
              style: AppTextStyles.labelSmall.copyWith(
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
