/// Investor domain model — mirrors backend UserResponse for user_type == "user"
/// (see backend/app/schemas/user.py).
class InvestorRiskProfile {
  final int score;
  final String level;
  final List<int>? answers;

  const InvestorRiskProfile({
    required this.score,
    required this.level,
    this.answers,
  });

  factory InvestorRiskProfile.fromJson(Map<String, dynamic> json) {
    return InvestorRiskProfile(
      score: (json['score'] as num?)?.toInt() ?? 0,
      level: json['level'] as String? ?? 'Not Assessed',
      answers: (json['answers'] as List?)?.map((e) => (e as num).toInt()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'level': level,
        if (answers != null) 'answers': answers,
      };
}

class Investor {
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? incomeBracket;
  final String? ageGroup;
  final InvestorRiskProfile? riskProfile;
  final bool onboardingCompleted;

  const Investor({
    required this.id,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.incomeBracket,
    this.ageGroup,
    this.riskProfile,
    this.onboardingCompleted = false,
  });

  factory Investor.fromJson(Map<String, dynamic> json) {
    return Investor(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Investor',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
      incomeBracket: json['income_bracket'] as String?,
      ageGroup: json['age_group'] as String?,
      riskProfile: json['risk_profile'] != null
          ? InvestorRiskProfile.fromJson(json['risk_profile'] as Map<String, dynamic>)
          : null,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
    );
  }
}
