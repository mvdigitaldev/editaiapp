import '../../../../core/utils/server_date_utils.dart';

class SupportTicketMessageModel {
  final String id;
  final String ticketId;
  final String userId;
  final String message;
  final DateTime createdAt;
  final String? userName;
  final String? userEmail;

  const SupportTicketMessageModel({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.message,
    required this.createdAt,
    this.userName,
    this.userEmail,
  });

  factory SupportTicketMessageModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final userMap = user is Map<String, dynamic> ? user : null;

    return SupportTicketMessageModel(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      userId: json['user_id'] as String,
      message: json['message'] as String? ?? '',
      createdAt: ServerDateUtils.parseServerDateOr(
        json['created_at'],
        DateTime.now(),
      ),
      userName: userMap?['name'] as String?,
      userEmail: userMap?['email'] as String?,
    );
  }
}
