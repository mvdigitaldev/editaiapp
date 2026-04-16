import '../../../../core/utils/server_date_utils.dart';

class SupportTicketModel {
  final String id;
  final String userId;
  final String? subject;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastMessageAt;
  final DateTime? closedAt;
  final String? lastMessagePreview;
  final String? userName;
  final String? userEmail;

  const SupportTicketModel({
    required this.id,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessageAt,
    this.subject,
    this.closedAt,
    this.lastMessagePreview,
    this.userName,
    this.userEmail,
  });

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final userMap = user is Map<String, dynamic> ? user : null;

    return SupportTicketModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      subject: json['subject'] as String?,
      status: json['status'] as String? ?? '',
      createdAt: ServerDateUtils.parseServerDateOr(
        json['created_at'],
        DateTime.now(),
      ),
      updatedAt: ServerDateUtils.parseServerDateOr(
        json['updated_at'],
        DateTime.now(),
      ),
      lastMessageAt: ServerDateUtils.parseServerDateOr(
        json['last_message_at'],
        DateTime.now(),
      ),
      closedAt: ServerDateUtils.parseServerDate(json['closed_at']),
      lastMessagePreview: json['last_message_preview'] as String?,
      userName: userMap?['name'] as String?,
      userEmail: userMap?['email'] as String?,
    );
  }
}
