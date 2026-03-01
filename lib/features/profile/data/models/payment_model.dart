import 'package:intl/intl.dart';

import '../../../../core/utils/server_date_utils.dart';

class PaymentModel {
  final String id;
  final double amount;
  final String currency;
  final String paymentMethod;
  final String paymentStatus;
  final String paymentProvider;
  final DateTime? paidAt;
  final DateTime createdAt;

  const PaymentModel({
    required this.id,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.paymentProvider,
    this.paidAt,
    required this.createdAt,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: (json['currency'] as String?)?.trim() ?? 'BRL',
      paymentMethod: json['payment_method'] as String,
      paymentStatus: json['payment_status'] as String,
      paymentProvider: json['payment_provider'] as String,
      paidAt: ServerDateUtils.parseServerDate(json['paid_at']),
      createdAt: ServerDateUtils.parseServerDateOr(json['created_at'], DateTime.now()),
    );
  }

  String get formattedAmount {
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: currency == 'BRL' ? 'R\$' : currency,
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  String get statusLabel {
    switch (paymentStatus) {
      case 'paid':
        return 'Pago';
      case 'pending':
        return 'Pendente';
      case 'failed':
        return 'Falhou';
      case 'refunded':
        return 'Reembolsado';
      default:
        return paymentStatus;
    }
  }

  String get formattedDate {
    final date = paidAt ?? createdAt;
    return ServerDateUtils.formatForDisplay(date, pattern: 'dd/MM/yyyy');
  }
}
