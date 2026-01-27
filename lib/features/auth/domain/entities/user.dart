class User {
  final String id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String subscriptionTier;

  User({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.subscriptionTier = 'free',
  });

  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? subscriptionTier,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
    );
  }
}
