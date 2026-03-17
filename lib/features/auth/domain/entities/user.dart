class User {
  final String id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String subscriptionTier;
  final DateTime? createdAt;
  final int? creditsBalance;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final DateTime? subscriptionStartedAt;
  final String? referralCode;
  final int? photoExpirationDays;
  final int? creditExpirationDays;
  final int? creditReferral;
  final int? addCredit;

  User({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.subscriptionTier = 'free',
    this.createdAt,
    this.creditsBalance,
    this.trialEndsAt,
    this.subscriptionEndsAt,
    this.subscriptionStartedAt,
    this.referralCode,
    this.photoExpirationDays,
    this.creditExpirationDays,
    this.creditReferral,
    this.addCredit,
  });

  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? subscriptionTier,
    DateTime? createdAt,
    int? creditsBalance,
    DateTime? trialEndsAt,
    DateTime? subscriptionEndsAt,
    DateTime? subscriptionStartedAt,
    String? referralCode,
    int? photoExpirationDays,
    int? creditExpirationDays,
    int? creditReferral,
    int? addCredit,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      createdAt: createdAt ?? this.createdAt,
      creditsBalance: creditsBalance ?? this.creditsBalance,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      subscriptionEndsAt: subscriptionEndsAt ?? this.subscriptionEndsAt,
      subscriptionStartedAt: subscriptionStartedAt ?? this.subscriptionStartedAt,
      referralCode: referralCode ?? this.referralCode,
      photoExpirationDays: photoExpirationDays ?? this.photoExpirationDays,
      creditExpirationDays: creditExpirationDays ?? this.creditExpirationDays,
      creditReferral: creditReferral ?? this.creditReferral,
      addCredit: addCredit ?? this.addCredit,
    );
  }
}
