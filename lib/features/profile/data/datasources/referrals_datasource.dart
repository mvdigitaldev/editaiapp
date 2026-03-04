import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/referral_models.dart';

abstract class ReferralsDataSource {
  Future<ReferralSummary> getSummary(String userId);

  Future<List<ReferralDetailModel>> getDetails(String userId);
}

class ReferralsDataSourceImpl implements ReferralsDataSource {
  final SupabaseClient _supabase;

  ReferralsDataSourceImpl(this._supabase);

  @override
  Future<ReferralSummary> getSummary(String userId) async {
    final response = await _supabase
        .from('referrals')
        .select('id, reward_credits')
        .eq('referrer_user_id', userId);

    final list = (response as List)
        .map((json) => json as Map<String, dynamic>)
        .toList();

    final friendsCount = list.length;
    final totalRewardCredits = list.fold<int>(
      0,
      (sum, row) => sum + (row['reward_credits'] as int? ?? 0),
    );

    return ReferralSummary(
      friendsCount: friendsCount,
      totalRewardCredits: totalRewardCredits,
    );
  }

  @override
  Future<List<ReferralDetailModel>> getDetails(String userId) async {
    final response = await _supabase
        .from('referral_contacts')
        .select(
          '''
id,
reward_credits,
reward_status,
created_at,
referred_name,
referred_email_masked
''',
        )
        .order('created_at', ascending: false);

    return (response as List)
        .map(
          (json) => ReferralDetailModel.fromJson(
            json as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}

