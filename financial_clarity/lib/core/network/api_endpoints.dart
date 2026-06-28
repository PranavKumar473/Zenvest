/// API endpoint constants.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'http://localhost:8000/api/v1';

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String biometricChallenge = '/auth/biometric/challenge';
  static const String biometricVerify = '/auth/biometric/verify';

  // Users
  static const String userProfile = '/users/me';
  static const String onboarding = '/users/me/onboarding';
  static const String riskQuestions = '/users/risk-questions';
  static const String riskAssessment = '/users/me/risk-assessment';

  // Budgets
  static const String budgets = '/budgets';

  // Transactions
  static const String transactions = '/transactions';

  // Portfolio
  static const String portfolioSummary = '/portfolio/summary';
  static const String netWorthHistory = '/portfolio/net-worth-history';
  static const String portfolioHoldings = '/portfolio/holdings';
  static const String investmentAdvisor = '/portfolio/advisor';

  // Account Aggregator
  static const String aaConsent = '/account-aggregator/consent';
  static String aaData(String consentId) =>
      '/account-aggregator/data/$consentId';
}
