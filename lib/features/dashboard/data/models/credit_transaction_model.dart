import '../../../../core/utils/app_time_utils.dart';
import '../../../../core/utils/server_date_utils.dart';
import 'credit_transaction_ui_mapper.dart';

class CreditTransactionModel {
  final String id;
  final String userId;
  final String type;
  final int amount;
  final String? description;
  final String? referenceId;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const CreditTransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.description,
    this.referenceId,
    required this.createdAt,
    this.expiresAt,
  });

  factory CreditTransactionModel.fromJson(Map<String, dynamic> json) {
    final parsedAmount = (json['amount'] as num?)?.toInt() ?? 0;

    return CreditTransactionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      amount: parsedAmount,
      description: json['description'] as String?,
      referenceId: json['reference_id'] as String?,
      createdAt: ServerDateUtils.parseServerDateOr(
          json['created_at'], AppTimeUtils.nowUtc()),
      expiresAt: ServerDateUtils.parseServerDate(json['expires_at']),
    );
  }

  bool get isCreditEntry => amount > 0;

  int get absoluteAmount => amount.abs();

  int get creditsUsed => amount < 0 ? absoluteAmount : amount;

  CreditTransactionUiType get uiType =>
      CreditTransactionUiMapper.fromDbType(type);

  String get typeLabel {
    return CreditTransactionUiMapper.typeLabelPtBr(uiType, type);
  }

  String get displayDescription {
    final translated = CreditTransactionUiMapper.descriptionPtBr(description);
    if (translated != null && translated.isNotEmpty) return translated;
    return typeLabel;
  }

  String get displayAmountSigned {
    final sign = amount >= 0 ? '+' : '-';
    final suffix = absoluteAmount == 1 ? 'credito' : 'creditos';
    return '$sign$absoluteAmount $suffix';
  }

  String get formattedDate {
    return ServerDateUtils.formatForDisplay(createdAt, pattern: 'd MMM yyyy');
  }

  String get formattedTime {
    return ServerDateUtils.formatForDisplay(createdAt, pattern: 'HH:mm');
  }

  String get formattedDateTime {
    return ServerDateUtils.formatForDisplay(createdAt,
        pattern: 'd MMM yyyy, HH:mm');
  }

  String get formattedExpiresAt {
    return ServerDateUtils.formatForDisplay(expiresAt,
        pattern: 'dd/MM/yyyy HH:mm');
  }
}
