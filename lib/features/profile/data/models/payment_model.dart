import 'package:intl/intl.dart';

import '../../../../core/utils/app_time_utils.dart';
import '../../../../core/utils/server_date_utils.dart';

class PaymentModel {
  final String id;
  final double amount;
  final String currency;
  final String paymentMethod;
  final String paymentStatus;
  final String paymentProvider;
  final String? externalPaymentId;
  final String? invoiceUrl;
  final DateTime? paidAt;
  final DateTime createdAt;

  const PaymentModel({
    required this.id,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.paymentProvider,
    this.externalPaymentId,
    this.invoiceUrl,
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
      externalPaymentId: json['external_payment_id'] as String?,
      invoiceUrl: json['invoice_url'] as String?,
      paidAt: ServerDateUtils.parseServerDate(json['paid_at']),
      createdAt: ServerDateUtils.parseServerDateOr(
          json['created_at'], AppTimeUtils.nowUtc()),
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

  String get formattedDateWithTime {
    final date = paidAt ?? createdAt;
    return ServerDateUtils.formatForDisplay(date, pattern: 'dd/MM/yyyy HH:mm');
  }

  String? get formattedPaidAt {
    if (paidAt == null) return null;
    return ServerDateUtils.formatForDisplay(paidAt, pattern: 'dd/MM/yyyy HH:mm');
  }

  String get formattedCreatedAt =>
      ServerDateUtils.formatForDisplay(createdAt, pattern: 'dd/MM/yyyy HH:mm');

  String? get shortExternalId {
    if (externalPaymentId == null || externalPaymentId!.isEmpty) return null;
    final id = externalPaymentId!;
    return id.length > 12 ? '${id.substring(0, 8)}...' : id;
  }
}
