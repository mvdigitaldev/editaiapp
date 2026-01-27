import '../../domain/entities/user.dart';

class UserModel extends User {
  UserModel({
    required super.id,
    super.email,
    super.displayName,
    super.avatarUrl,
    super.subscriptionTier,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      subscriptionTier: json['subscription_tier'] as String? ?? 'free',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'subscription_tier': subscriptionTier,
    };
  }

  User toEntity() {
    return User(
      id: id,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
      subscriptionTier: subscriptionTier,
    );
  }
}
