import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/support_ticket_message_model.dart';
import '../models/support_ticket_model.dart';

abstract class SupportDataSource {
  Future<List<SupportTicketModel>> getMyTickets();
  Future<List<SupportTicketModel>> getAdminTickets({String? status});
  Future<SupportTicketModel> getTicketById(String ticketId);
  Future<List<SupportTicketMessageModel>> getMessages(String ticketId);
  Future<String> createTicket({
    required String message,
    String? subject,
  });
  Future<void> sendMessage({
    required String ticketId,
    required String message,
  });
  Future<void> updateTicketStatus({
    required String ticketId,
    required String status,
  });
  Future<void> reopenTicket({
    required String ticketId,
    String? message,
  });
}

class SupportDataSourceImpl implements SupportDataSource {
  final SupabaseClient _supabase;

  SupportDataSourceImpl(this._supabase);

  static const _ticketSelect =
      'id, user_id, subject, status, closed_at, last_message_at, '
      'last_message_preview, created_at, updated_at, '
      'user:users!support_tickets_user_id_fkey(name, email)';

  static const _messageSelect = 'id, ticket_id, user_id, message, created_at, '
      'user:users!support_ticket_messages_user_id_fkey(name, email)';

  @override
  Future<String> createTicket({
    required String message,
    String? subject,
  }) async {
    final response = await _supabase.rpc(
      'create_support_ticket',
      params: {
        'p_subject': subject?.trim().isEmpty == true ? null : subject?.trim(),
        'p_message': message.trim(),
      },
    );

    return response as String;
  }

  @override
  Future<SupportTicketModel> getTicketById(String ticketId) async {
    final response = await _supabase
        .from('support_tickets')
        .select(_ticketSelect)
        .eq('id', ticketId)
        .single();

    return SupportTicketModel.fromJson(response);
  }

  @override
  Future<List<SupportTicketModel>> getMyTickets() async {
    final response = await _supabase
        .from('support_tickets')
        .select(_ticketSelect)
        .order('last_message_at', ascending: false);

    return (response as List)
        .map(
            (json) => SupportTicketModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SupportTicketModel>> getAdminTickets({String? status}) async {
    final query = _supabase.from('support_tickets').select(_ticketSelect);
    final response = await (status == null || status.isEmpty
            ? query
            : query.eq('status', status))
        .order('last_message_at', ascending: false);

    return (response as List)
        .map(
            (json) => SupportTicketModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SupportTicketMessageModel>> getMessages(String ticketId) async {
    final response = await _supabase
        .from('support_ticket_messages')
        .select(_messageSelect)
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);

    return (response as List)
        .map(
          (json) => SupportTicketMessageModel.fromJson(
            json as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<void> reopenTicket({
    required String ticketId,
    String? message,
  }) async {
    await _supabase.rpc(
      'reopen_support_ticket',
      params: {
        'p_ticket_id': ticketId,
        'p_message': message?.trim().isEmpty == true ? null : message?.trim(),
      },
    );
  }

  @override
  Future<void> sendMessage({
    required String ticketId,
    required String message,
  }) async {
    await _supabase.from('support_ticket_messages').insert({
      'ticket_id': ticketId,
      'user_id': _supabase.auth.currentUser?.id,
      'message': message.trim(),
    });
  }

  @override
  Future<void> updateTicketStatus({
    required String ticketId,
    required String status,
  }) async {
    await _supabase.from('support_tickets').update({
      'status': status,
      'closed_at':
          status == 'FECHADO' ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', ticketId);
  }
}
