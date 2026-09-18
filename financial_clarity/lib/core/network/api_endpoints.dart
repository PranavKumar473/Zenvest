/// API endpoint constants.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'http://localhost:8000/api/v1';

  /// http(s):// -> ws(s):// — used for the call-signaling WebSocket.
  static String get wsBaseUrl => baseUrl.replaceFirst('http', 'ws');

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String biometricChallenge = '/auth/biometric/challenge';
  static const String biometricVerify = '/auth/biometric/verify';
  static const String advisorUploadLicense = '/auth/advisor/upload-license';
  static const String registerAdvisor = '/auth/register';

  // Users
  static const String userProfile = '/users/me';
  static const String onboarding = '/users/me/onboarding';
  static const String riskQuestions = '/users/risk-questions';
  static const String riskAssessment = '/users/me/risk-assessment';

  // Budgets
  static const String budgets = '/budgets';
  static const String budgetSuggestions    = '/budgets/suggestions';
  static const String budgetApplySuggestions = '/budgets/apply-suggestions';
  static String budgetById(String id) => '/budgets/$id';

  // Transactions
  static const String transactions = '/transactions';

  // Portfolio
  static const String portfolioSummary = '/portfolio/summary';
  static const String netWorthHistory = '/portfolio/net-worth-history';
  static const String portfolioHoldings = '/portfolio/holdings';
  static const String investmentAdvisor = '/portfolio/advisor';
  static const String confirmInvestment = '/portfolio/advisor/confirm-investment';

  // Human Advisors
  static const String advisors = '/advisors';
  static const String allAdvisors = '/advisors/all';
  static String advisorById(String id) => '/advisors/$id';
  static String advisorDemoCall(String id) => '/advisors/$id/demo-call';
  static const String verifyMyGst = '/advisors/me/verify-gst';
  static const String completeAdvisorOnboarding = '/advisors/me/complete-onboarding';
  static const String uploadProfilePicture = '/users/me/profile-picture';

  // Advisor Requests (Connect Request flow)
  static const String advisorRequests = '/advisor-requests';
  static const String incomingRequests = '/advisor-requests/incoming';
  static const String outgoingRequests = '/advisor-requests/outgoing';
  static String respondToRequest(String id) => '/advisor-requests/$id/respond';
  static String requestChat(String id) => '/advisor-requests/$id/chat';
  static String requestCall(String id) => '/advisor-requests/$id/call';

  // ARN/INA Linkage
  static const String arnLinkage = '/arn-linkage';
  static const String myLinkedAdvisors = '/arn-linkage/my-advisor';
  static const String myLinkedInvestors = '/arn-linkage/my-investors';
  static String linkedInvestorPortfolio(String investorId) =>
      '/arn-linkage/my-investors/$investorId/portfolio';

  // Subscriptions (Razorpay recurring consultation fee)
  static const String subscriptionCheckout = '/subscriptions/checkout';
  static const String verifySubscriptionPayment = '/subscriptions/verify-payment';
  static const String mySubscriptions = '/subscriptions/mine';
  static const String myClientSubscriptions = '/subscriptions/my-clients';

  // Account Aggregator
  static const String aaConsent = '/account-aggregator/consent';
  static String aaData(String consentId) =>
      '/account-aggregator/data/$consentId';

  // Mutual Funds — categorized directory, top-5 recommendations, detail
  static const String fundDirectory = '/mutual-funds/directory';
  static const String fundTop5 = '/mutual-funds/top5';
  static String fundDetail(int schemeCode) => '/mutual-funds/$schemeCode';
  static String fundCompare(List<int> schemeCodes) =>
      '/mutual-funds/compare?codes=${schemeCodes.join(',')}';

  // Universal Invest workflow — hidden corporate ARN + EUIN attribution
  static const String invest = '/invest';

  // Dual-consent chat + WebRTC call signaling (WebSocket)
  static String advisorRequestSocket(String requestId) =>
      '/ws/advisor-requests/$requestId';
}
