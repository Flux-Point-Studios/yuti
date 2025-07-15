class User {
  final String id;
  final String email;
  final String? customerId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Subscription data
  final String tier;
  final String? subscriptionStatus;
  final String? subscriptionId;
  final DateTime? endedAt;

  // Cardano wallet data
  final String? walletAddress;
  final String? stakeAddress;
  final Map<String, dynamic>? premiumAccessDetails;

  User({
    required this.id,
    required this.email,
    this.customerId,
    required this.createdAt,
    this.updatedAt,
    required this.tier,
    this.subscriptionStatus,
    this.subscriptionId,
    this.endedAt,
    this.walletAddress,
    this.stakeAddress,
    this.premiumAccessDetails,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'customer_id': customerId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'tier': tier,
      'subscription_status': subscriptionStatus,
      'subscription_id': subscriptionId,
      'ended_at': endedAt?.toIso8601String(),
      'wallet_address': walletAddress,
      'stake_address': stakeAddress,
      'premium_access_details': premiumAccessDetails,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      customerId: json['customer_id'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      tier: json['tier'] ?? 'FREE',
      subscriptionStatus: json['subscription_status'],
      subscriptionId: json['subscription_id'],
      endedAt:
          json['ended_at'] != null ? DateTime.parse(json['ended_at']) : null,
      walletAddress: json['wallet_address'],
      stakeAddress: json['stake_address'],
      premiumAccessDetails: json['premium_access_details'],
    );
  }

  factory User.fromSupabaseUser(
    Map<String, dynamic> userData,
    Map<String, dynamic>? subscriptionData,
  ) {
    return User(
      id: userData['id'] ?? '',
      email: userData['email'] ?? '',
      customerId: userData['customer_id'],
      createdAt: userData['created_at'] != null
          ? DateTime.parse(userData['created_at'])
          : DateTime.now(),
      updatedAt: userData['updated_at'] != null
          ? DateTime.parse(userData['updated_at'])
          : null,
      tier: subscriptionData?['tier'] ?? 'FREE',
      subscriptionStatus: subscriptionData?['status'],
      subscriptionId: subscriptionData?['subscription_id'],
      endedAt: subscriptionData?['ended_at'] != null
          ? DateTime.parse(subscriptionData!['ended_at'])
          : null,
      walletAddress: userData['wallet_address'],
      stakeAddress: userData['stake_address'],
      premiumAccessDetails: userData['premium_access_details'],
    );
  }

  User copyWith({
    String? id,
    String? email,
    String? customerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? tier,
    String? subscriptionStatus,
    String? subscriptionId,
    DateTime? endedAt,
    String? walletAddress,
    String? stakeAddress,
    Map<String, dynamic>? premiumAccessDetails,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      customerId: customerId ?? this.customerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tier: tier ?? this.tier,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      endedAt: endedAt ?? this.endedAt,
      walletAddress: walletAddress ?? this.walletAddress,
      stakeAddress: stakeAddress ?? this.stakeAddress,
      premiumAccessDetails: premiumAccessDetails ?? this.premiumAccessDetails,
    );
  }

  // Computed properties for tier checking
  bool get isPremium => tier != 'FREE';
  bool get isVIP => tier == 'VIP';
  bool get isBasic => tier == 'BASIC';
  bool get isPremiumTier => tier == 'PREMIUM';

  // Check if subscription is active
  bool get hasActiveSubscription {
    if (tier == 'FREE') return true; // Free tier is always "active"
    if (subscriptionStatus == null) return false;
    if (subscriptionStatus == 'active' || subscriptionStatus == 'trialing') {
      return true;
    }
    return false;
  }

  // Days left in subscription
  int get daysLeft {
    if (endedAt == null) return 0;
    final now = DateTime.now();
    final difference = endedAt!.difference(now);
    return difference.inDays.clamp(0, double.infinity).toInt();
  }

  // Check if subscription has expired
  bool get hasExpired {
    if (tier == 'FREE') return false;
    if (endedAt == null) return true;
    return DateTime.now().isAfter(endedAt!);
  }
}
