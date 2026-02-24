import 'package:equatable/equatable.dart';

class PlanModel extends Equatable {
  final String id;
  final String name;
  final String? description;
  final double? price;
  final int? durationMonths;
  final int? monthlyCredits;
  final List<String> features;
  final String? linkPayment;
  final bool isActive;

  const PlanModel({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.durationMonths,
    this.monthlyCredits,
    this.features = const [],
    this.linkPayment,
    required this.isActive,
  });

  bool get isFree => price == null || price == 0;

  String get durationText {
    if (durationMonths == null || durationMonths == 0 || durationMonths == 1) {
      return 'Mensal';
    }
    if (durationMonths == 3) {
      return 'Trimestral (3 meses)';
    }
    if (durationMonths == 6) {
      return 'Semestral (6 meses)';
    }
    return '$durationMonths meses';
  }

  String get formattedPrice {
    if (isFree) return 'Grátis';
    final value = price!;
    if (durationMonths == null || durationMonths == 0 || durationMonths == 1) {
      return 'R\$ ${value.toStringAsFixed(2)}/mês';
    }
    return 'R\$ ${value.toStringAsFixed(2)}';
  }

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    return PlanModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      durationMonths: json['duration_months'] as int?,
      monthlyCredits: json['monthly_credits'] as int?,
      features: rawFeatures is List
          ? rawFeatures.map((e) => e.toString()).toList()
          : const [],
      linkPayment: json['link_payment'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        price,
        durationMonths,
        monthlyCredits,
        features,
        linkPayment,
        isActive,
      ];
}

