/// Application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Financial Clarity';
  static const String appVersion = '1.0.0';

  // Budget categories with their display names and icons
  static const Map<String, String> categoryNames = {
    'food': 'Food & Dining',
    'bills': 'Bills & Utilities',
    'shopping': 'Shopping',
    'entertainment': 'Entertainment',
    'transport': 'Transport',
    'health': 'Health & Fitness',
    'other': 'Other',
  };

  // Category emoji icons
  static const Map<String, String> categoryIcons = {
    'food': '🍔',
    'bills': '⚡',
    'shopping': '🛍️',
    'entertainment': '🎬',
    'transport': '🚗',
    'health': '💊',
    'other': '💰',
  };

  // Asset type display names
  static const Map<String, String> assetTypeNames = {
    'mutual_fund': 'Mutual Funds',
    'fixed_deposit': 'Fixed Deposits',
    'stocks': 'Stocks',
    'gold': 'Gold',
    'bonds': 'Bonds',
  };

  // Pagination
  static const int defaultPageSize = 20;

  // Animation durations
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 350);
  static const Duration animSlow = Duration(milliseconds: 500);
}
