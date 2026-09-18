/// Subscription domain model — mirrors backend schemas/subscription.py.
/// A recurring monthly consultation-fee engagement between investor and
/// advisor, billed via Razorpay Subscriptions.

class SubscriptionCheckout {
  final String subscriptionId;
  final String provider; // "mock" | "razorpay"
  final String providerSubscriptionId;
  final String? checkoutKey; // Razorpay key_id, needed by razorpay_flutter
  final double amountMonthly;
  final String advisorName;

  const SubscriptionCheckout({
    required this.subscriptionId,
    required this.provider,
    required this.providerSubscriptionId,
    this.checkoutKey,
    required this.amountMonthly,
    required this.advisorName,
  });

  factory SubscriptionCheckout.fromJson(Map<String, dynamic> json) {
    return SubscriptionCheckout(
      subscriptionId: json['subscription_id'] as String,
      provider: json['provider'] as String,
      providerSubscriptionId: json['provider_subscription_id'] as String,
      checkoutKey: json['checkout_key'] as String?,
      amountMonthly: (json['amount_monthly'] as num).toDouble(),
      advisorName: json['advisor_name'] as String? ?? 'Advisor',
    );
  }
}

enum SubscriptionStatus { created, active, pastDue, cancelled, completed }

SubscriptionStatus subscriptionStatusFromString(String value) {
  switch (value) {
    case 'active':
      return SubscriptionStatus.active;
    case 'past_due':
      return SubscriptionStatus.pastDue;
    case 'cancelled':
      return SubscriptionStatus.cancelled;
    case 'completed':
      return SubscriptionStatus.completed;
    default:
      return SubscriptionStatus.created;
  }
}

class Subscription {
  final String id;
  final String investorId;
  final String advisorId;
  final String? counterpartyName;
  final double amountMonthly;
  final String provider;
  final SubscriptionStatus status;
  final DateTime? currentPeriodEnd;
  final DateTime createdAt;

  const Subscription({
    required this.id,
    required this.investorId,
    required this.advisorId,
    this.counterpartyName,
    required this.amountMonthly,
    required this.provider,
    required this.status,
    this.currentPeriodEnd,
    required this.createdAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      investorId: json['investor_id'] as String,
      advisorId: json['advisor_id'] as String,
      counterpartyName: json['counterparty_name'] as String?,
      amountMonthly: (json['amount_monthly'] as num).toDouble(),
      provider: json['provider'] as String,
      status: subscriptionStatusFromString(json['status'] as String),
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.parse(json['current_period_end'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
