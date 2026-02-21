import '../../domain/entities/user.dart';

class UserModel extends User {
  UserModel({
    required super.id,
    super.email,
    super.displayName,
    super.avatarUrl,
    super.subscriptionTier,
    super.createdAt,
    super.creditsBalance,
    super.trialEndsAt,
    super.subscriptionEndsAt,
  });

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      subscriptionTier: json['subscription_tier'] as String? ?? 'free',
      createdAt: _parseDateTime(json['created_at']),
      creditsBalance: _parseInt(json['credits_balance']),
      trialEndsAt: _parseDateTime(json['trial_ends_at']),
      subscriptionEndsAt: _parseDateTime(json['subscription_ends_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'subscription_tier': subscriptionTier,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (creditsBalance != null) 'credits_balance': creditsBalance,
      if (trialEndsAt != null) 'trial_ends_at': trialEndsAt!.toIso8601String(),
      if (subscriptionEndsAt != null) 'subscription_ends_at': subscriptionEndsAt!.toIso8601String(),
    };
  }

  User toEntity() {
    return User(
      id: id,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
      subscriptionTier: subscriptionTier,
      createdAt: createdAt,
      creditsBalance: creditsBalance,
      trialEndsAt: trialEndsAt,
      subscriptionEndsAt: subscriptionEndsAt,
    );
  }
}
