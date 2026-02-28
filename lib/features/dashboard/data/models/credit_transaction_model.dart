import 'package:intl/intl.dart';

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
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Quantidade de créditos usados (sempre positivo para exibição).
  int get creditsUsed => amount < 0 ? amount.abs() : amount;

  String get formattedDate {
    return DateFormat('d MMM yyyy', 'pt_BR').format(createdAt);
  }

  String get formattedTime {
    return DateFormat('HH:mm', 'pt_BR').format(createdAt);
  }

  String get formattedDateTime {
    return DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(createdAt);
  }
}
