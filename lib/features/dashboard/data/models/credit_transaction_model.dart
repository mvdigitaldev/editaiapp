import '../../../../core/utils/server_date_utils.dart';

class CreditTransactionModel {
  final String id;
  final String userId;
  final String type;
  final int amount;
  final String? description;
  final String? referenceId;
  final DateTime createdAt;

  const CreditTransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.description,
    this.referenceId,
    required this.createdAt,
  });

  factory CreditTransactionModel.fromJson(Map<String, dynamic> json) {
    return CreditTransactionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      amount: json['amount'] as int,
      description: json['description'] as String?,
      referenceId: json['reference_id'] as String?,
      createdAt: ServerDateUtils.parseServerDateOr(json['created_at'], DateTime.now()),
    );
  }

  /// Quantidade de créditos usados (sempre positivo para exibição).
  int get creditsUsed => amount < 0 ? amount.abs() : amount;

  String get formattedDate {
    return ServerDateUtils.formatForDisplay(createdAt, pattern: 'd MMM yyyy');
  }

  String get formattedTime {
    return ServerDateUtils.formatForDisplay(createdAt, pattern: 'HH:mm');
  }

  String get formattedDateTime {
    return ServerDateUtils.formatForDisplay(createdAt, pattern: 'd MMM yyyy, HH:mm');
  }
}
