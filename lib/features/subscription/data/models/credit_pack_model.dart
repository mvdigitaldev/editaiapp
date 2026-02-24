import 'package:intl/intl.dart';

class CreditPackModel {
  final String id;
  final String name;
  final int credits;
  final double price;
  final bool isPopular;
  final bool hasSavings;
  final String? linkPayment;
  final int sortOrder;

  const CreditPackModel({
    required this.id,
    required this.name,
    required this.credits,
    required this.price,
    this.isPopular = false,
    this.hasSavings = false,
    this.linkPayment,
    this.sortOrder = 0,
  });

  factory CreditPackModel.fromJson(Map<String, dynamic> json) {
    return CreditPackModel(
      id: json['id'] as String,
      name: json['name'] as String,
      credits: json['credits'] as int,
      price: (json['price'] as num).toDouble(),
      isPopular: (json['is_popular'] as bool?) ?? false,
      hasSavings: (json['has_savings'] as bool?) ?? false,
      linkPayment: json['link_payment'] as String?,
      sortOrder: (json['sort_order'] as int?) ?? 0,
    );
  }

  String get formattedPrice {
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    );
    return formatter.format(price);
  }
}
