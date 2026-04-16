import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../../core/utils/server_date_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/support_ticket_message_model.dart';
import '../../data/models/support_ticket_model.dart';
import '../../data/models/support_ticket_status.dart';
import '../providers/support_provider.dart';

class SupportTicketDetailPage extends ConsumerStatefulWidget {
  final String ticketId;

  const SupportTicketDetailPage({
    super.key,
    required this.ticketId,
  });

  @override
  ConsumerState<SupportTicketDetailPage> createState() =>
      _SupportTicketDetailPageState();
}

class _SupportTicketDetailPageState
    extends ConsumerState<SupportTicketDetailPage> {
  final _messageController = TextEditingController();
  SupportTicketModel? _ticket;
  List<SupportTicketMessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSavingStatus = false;
  String? _error;
  String? _selectedStatus;

  bool get _isAdmin => ref.read(authStateProvider).user?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ds = ref.read(supportDataSourceProvider);
      final results = await Future.wait([
        ds.getTicketById(widget.ticketId),
        ds.getMessages(widget.ticketId),
      ]);

      final ticket = results[0] as SupportTicketModel;
      final messages = results[1] as List<SupportTicketMessageModel>;

      setState(() {
        _ticket = ticket;
        _messages = messages;
        _selectedStatus = ticket.status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = postgrestUserMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(supportDataSourceProvider).sendMessage(
            ticketId: widget.ticketId,
            message: message,
          );
      _messageController.clear();
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(postgrestUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveStatus() async {
    final ticket = _ticket;
    final selectedStatus = _selectedStatus;
    if (ticket == null ||
        selectedStatus == null ||
        selectedStatus == ticket.status) {
      return;
    }

    setState(() => _isSavingStatus = true);
    try {
      await ref.read(supportDataSourceProvider).updateTicketStatus(
            ticketId: ticket.id,
            status: selectedStatus,
          );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(postgrestUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _isSavingStatus = false);
    }
  }

  Future<void> _reopenTicket() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(supportDataSourceProvider).reopenTicket(
            ticketId: widget.ticketId,
          );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(postgrestUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Chamado',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headingMedium.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
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

    if (_error != null || _ticket == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Não foi possível carregar o chamado.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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

    final ticket = _ticket!;
    final canReply = ticket.status != SupportTicketStatus.fechado;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _TicketHeader(
            ticket: ticket,
            isDark: isDark,
            isAdmin: _isAdmin,
            selectedStatus: _selectedStatus,
            isSavingStatus: _isSavingStatus,
            onStatusChanged: (value) => setState(() => _selectedStatus = value),
            onSaveStatus: _saveStatus,
            onReopen: canReply ? null : _reopenTicket,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMine =
                    message.userId == ref.read(authStateProvider).user?.id;
                return _TicketMessageBubble(
                  message: message,
                  isMine: isMine,
                  isDark: isDark,
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.borderDark : AppColors.border,
                ),
              ),
            ),
            child: Column(
              children: [
                if (!canReply)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isAdmin
                                ? 'Este chamado está fechado. Altere o status para voltar a responder.'
                                : 'Este chamado está fechado. Reabra para enviar novas mensagens.',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isDark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        enabled: canReply && !_isSubmitting,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: canReply
                              ? 'Escreva uma mensagem...'
                              : 'Reabra o chamado para responder',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed:
                          canReply && !_isSubmitting ? _sendMessage : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketHeader extends StatelessWidget {
  final SupportTicketModel ticket;
  final bool isDark;
  final bool isAdmin;
  final String? selectedStatus;
  final bool isSavingStatus;
  final ValueChanged<String?> onStatusChanged;
  final Future<void> Function() onSaveStatus;
  final Future<void> Function()? onReopen;

  const _TicketHeader({
    required this.ticket,
    required this.isDark,
    required this.isAdmin,
    required this.selectedStatus,
    required this.isSavingStatus,
    required this.onStatusChanged,
    required this.onSaveStatus,
    required this.onReopen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (ticket.subject?.trim().isNotEmpty ?? false)
                ? ticket.subject!.trim()
                : 'Chamado #${ticket.id.substring(0, 8)}',
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Criado em ${ServerDateUtils.formatForDisplay(ticket.createdAt)}',
            style: AppTextStyles.labelSmall.copyWith(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
            ),
          ),
          if (ticket.userName?.trim().isNotEmpty == true ||
              ticket.userEmail?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              '${ticket.userName?.trim().isNotEmpty == true ? ticket.userName!.trim() : 'Usuário'}'
              '${ticket.userEmail?.trim().isNotEmpty == true ? ' • ${ticket.userEmail!.trim()}' : ''}',
              style: AppTextStyles.labelSmall.copyWith(
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isAdmin) ...[
            DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              items: SupportTicketStatus.values
                  .map(
                    (status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(SupportTicketStatus.label(status)),
                    ),
                  )
                  .toList(),
              onChanged: onStatusChanged,
              decoration: InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isSavingStatus ? null : onSaveStatus,
                child: isSavingStatus
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar status'),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    SupportTicketStatus.label(ticket.status),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (ticket.status == SupportTicketStatus.fechado &&
                    onReopen != null)
                  TextButton.icon(
                    onPressed: onReopen,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reabrir chamado'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketMessageBubble extends StatelessWidget {
  final SupportTicketMessageModel message;
  final bool isMine;
  final bool isDark;

  const _TicketMessageBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isMine
        ? AppColors.primary.withOpacity(isDark ? 0.28 : 0.12)
        : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isMine
                  ? 'Você'
                  : (message.userName?.trim().isNotEmpty == true
                      ? message.userName!.trim()
                      : message.userEmail?.trim().isNotEmpty == true
                          ? message.userEmail!.trim()
                          : 'Suporte'),
              style: AppTextStyles.labelSmall.copyWith(
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message.message,
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ServerDateUtils.formatForDisplay(
                message.createdAt,
                pattern: 'd MMM, HH:mm',
              ),
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
