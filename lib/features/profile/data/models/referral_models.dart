import 'package:intl/intl.dart';

import '../../../../core/utils/app_time_utils.dart';
import '../../../../core/utils/server_date_utils.dart';

class ReferralSummary {
  final int friendsCount;
  final int totalRewardCredits;

  const ReferralSummary({
    required this.friendsCount,
    required this.totalRewardCredits,
  });

  static const empty = ReferralSummary(friendsCount: 0, totalRewardCredits: 0);
}

class ReferralDetailModel {
  final String id;
  final String? referredName;
  final String? referredEmailMasked;
  final int rewardCredits;
  final String rewardStatus;
  final DateTime createdAt;

  const ReferralDetailModel({
    required this.id,
    required this.referredName,
    required this.referredEmailMasked,
    required this.rewardCredits,
    required this.rewardStatus,
    required this.createdAt,
  });

  factory ReferralDetailModel.fromJson(Map<String, dynamic> json) {
    return ReferralDetailModel(
      id: json['id'] as String,
      referredName: json['referred_name'] as String?,
      referredEmailMasked: json['referred_email_masked'] as String?,
      rewardCredits: (json['reward_credits'] as int?) ?? 0,
      rewardStatus: (json['reward_status'] as String?) ?? 'pending',
      createdAt: ServerDateUtils.parseServerDateOr(
        json['created_at'],
        AppTimeUtils.nowUtc(),
      ),
    );
  }

  String get maskedEmail {
    final email = referredEmailMasked;
    if (email == null || !email.contains('@')) return '***@***';

    final parts = email.split('@');
    final local = parts[0];
    final domain = parts[1];

    final localVisible = local.length <= 4 ? local : local.substring(0, 4);
    final localMasked = '$localVisible****';

    final domainParts = domain.split('.');
    if (domainParts.length < 2) {
      return '$localMasked@***';
    }

    final tld = domainParts.last;
    return '$localMasked@***.$tld';
  }

  String get statusLabel {
    switch (rewardStatus) {
      case 'paid':
        return 'Pago';
      case 'pending':
        return 'Pendente';
      default:
        return rewardStatus;
    }
  }

  String get formattedDate {
    final formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(createdAt.toLocal());
  }
}

