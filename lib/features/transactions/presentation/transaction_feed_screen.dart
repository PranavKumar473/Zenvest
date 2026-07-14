/// Transaction Feed — Redesigned, with SMS transaction sync, manual logger, spending pie chart, and category/type filters.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../core/sms/sms_parser_service.dart';

// Indian currency formatter
final currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

final transactionSyncEventProvider = StateProvider<int>((ref) => 0);

// Colors for category sections in the pie chart
const categoryColors = {
  'food': Color(0xFFFF6B6B),
  'transport': Color(0xFF4ECDC4),
  'shopping': Color(0xFFFFE66D),
  'bills': Color(0xFF6C5CE7),
  'health': Color(0xFF00B894),
  'entertainment': Color(0xFFE17055),
  'other': Color(0xFFB2BEC3),
};

// Transaction state
class TransactionState {
  final List<Map<String, dynamic>> transactions;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;
  final String? categoryFilter;

  // New state variables
  final double totalDebits; // default 0
  final double totalCredits; // default 0
  final List<Map<String, dynamic>> categoryBreakdown; // default []
  final bool isSyncing; // default false — for SMS sync loading state
  final String? syncMessage; // e.g. "Synced 12 new transactions"
  final bool
      syncSuccess; // default true — used to colour the snackbar green or red
  final bool liveSyncEnabled; // default false
  final String activeTab; // "all" | "debit" | "credit"  default "all"
  final String selectedMonth; // "YYYY-MM" default current month

  // Income / savings-floor — sourced from /budgets/suggestions so this
  // screen and the Budget screen always agree on the same numbers.
  final double
      monthlyIncomeUsed; // "Total Salary" — real credits this month, else the income-bracket estimate
  final double savingsFloorAmount; // locked-first savings, age/risk-adjusted
  final double
      spendableIncome; // "Budget for Expenses" = monthlyIncomeUsed - savingsFloorAmount

  const TransactionState({
    this.transactions = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
    this.categoryFilter,
    this.totalDebits = 0.0,
    this.totalCredits = 0.0,
    this.categoryBreakdown = const [],
    this.isSyncing = false,
    this.syncMessage,
    this.syncSuccess = true,
    this.liveSyncEnabled = false,
    this.activeTab = 'all',
    required this.selectedMonth,
    this.monthlyIncomeUsed = 0.0,
    this.savingsFloorAmount = 0.0,
    this.spendableIncome = 0.0,
  });

  TransactionState copyWith({
    List<Map<String, dynamic>>? transactions,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
    String? categoryFilter,
    double? totalDebits,
    double? totalCredits,
    List<Map<String, dynamic>>? categoryBreakdown,
    bool? isSyncing,
    String? syncMessage,
    bool? syncSuccess,
    bool? liveSyncEnabled,
    String? activeTab,
    String? selectedMonth,
    double? monthlyIncomeUsed,
    double? savingsFloorAmount,
    double? spendableIncome,
  }) {
    return TransactionState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      totalDebits: totalDebits ?? this.totalDebits,
      totalCredits: totalCredits ?? this.totalCredits,
      categoryBreakdown: categoryBreakdown ?? this.categoryBreakdown,
      isSyncing: isSyncing ?? this.isSyncing,
      syncMessage: syncMessage,
      syncSuccess: syncSuccess ?? this.syncSuccess,
      liveSyncEnabled: liveSyncEnabled ?? this.liveSyncEnabled,
      activeTab: activeTab ?? this.activeTab,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      monthlyIncomeUsed: monthlyIncomeUsed ?? this.monthlyIncomeUsed,
      savingsFloorAmount: savingsFloorAmount ?? this.savingsFloorAmount,
      spendableIncome: spendableIncome ?? this.spendableIncome,
    );
  }
}

// Controller
class TransactionController extends StateNotifier<TransactionState> {
  final Dio _dio;
  final Ref _ref;
  Timer? _liveSyncTimer;

  TransactionController(this._dio, this._ref)
      : super(TransactionState(
          selectedMonth: DateFormat('yyyy-MM').format(DateTime.now()),
        )) {
    _restoreLiveSyncPreference();
    loadTransactions();
  }

  Future<void> _restoreLiveSyncPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool('live_sync_enabled') ?? false;
    if (wasEnabled) {
      state = state.copyWith(liveSyncEnabled: true);
      _liveSyncTimer = Timer.periodic(const Duration(minutes: 30), (_) {
        syncFromSms();
      });
    }
  }

  Future<void> setLiveSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('live_sync_enabled', enabled);
    state = state.copyWith(liveSyncEnabled: enabled);

    if (enabled) {
      await syncFromSms(); // immediate sync
      _liveSyncTimer?.cancel();
      _liveSyncTimer = Timer.periodic(const Duration(minutes: 30), (_) {
        syncFromSms();
      });
    } else {
      _liveSyncTimer?.cancel();
      _liveSyncTimer = null;
    }
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> loadTransactions({bool refresh = false}) async {
    if (state.isLoading) return;
    if (!mounted) return;

    final page = refresh ? 1 : state.currentPage;
    state = state.copyWith(isLoading: true, error: null);

    try {
      String url = '${ApiEndpoints.transactions}?page=$page&page_size=20';
      if (state.categoryFilter != null) {
        url += '&category=${state.categoryFilter}';
      }

      if (state.activeTab == 'debit') {
        url += '&is_debit=true';
      } else if (state.activeTab == 'credit') {
        url += '&is_debit=false';
      }

      final response = await _dio.get(url);
      final data = response.data;
      final newTxns = List<Map<String, dynamic>>.from(data['transactions']);

      if (!mounted) return;
      state = state.copyWith(
        transactions: refresh ? newTxns : [...state.transactions, ...newTxns],
        isLoading: false,
        hasMore: data['has_next'] ?? false,
        currentPage: page + 1,
      );

      await loadSummary();
      await loadIncomeSummary();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load transactions',
      );
    }
  }

  Future<void> loadSummary() async {
    try {
      final response = await _dio.get(
        '${ApiEndpoints.transactions}/summary?month=${state.selectedMonth}',
      );
      final data = response.data;

      if (!mounted) return;
      state = state.copyWith(
        totalDebits: (data['total_debits'] as num?)?.toDouble() ?? 0.0,
        totalCredits: (data['total_credits'] as num?)?.toDouble() ?? 0.0,
        categoryBreakdown:
            List<Map<String, dynamic>>.from(data['category_breakdown'] ?? []),
      );
    } catch (e) {
      // Fail silently for summary to avoid blocking transaction list
    }
  }

  /// Total salary and salary-after-savings (budget for expenses) — same
  /// income/savings-floor numbers the Budget screen shows, so "Money
  /// Available" here is grounded in actual income rather than only the
  /// credit transactions logged this month (which is often ₹0 if salary
  /// was never manually logged/synced, making the figure look falsely
  /// negative the moment any expense is recorded).
  Future<void> loadIncomeSummary() async {
    try {
      final response = await _dio.get(ApiEndpoints.budgetSuggestions);
      final data = response.data;

      if (!mounted) return;
      state = state.copyWith(
        monthlyIncomeUsed:
            (data['monthly_income_used'] as num?)?.toDouble() ?? 0.0,
        savingsFloorAmount:
            (data['savings_floor_amount'] as num?)?.toDouble() ?? 0.0,
        spendableIncome: (data['spendable_income'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      // Fail silently — the summary card falls back to its zero defaults
    }
  }

  Future<void> syncFromSms() async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true, syncMessage: null);

    try {
      final parserService = SmsParserService();
      final result = await parserService.parseSmsTransactions();

      // Handle: iOS or platform that doesn't support SMS reading
      if (result.isPlatformUnsupported) {
        state = state.copyWith(
          isSyncing: false,
          syncMessage:
              'SMS sync is only available on Android. Use "Add Expense" to log manually.',
          syncSuccess: false,
        );
        return;
      }

      // Handle: user denied the SMS permission popup
      if (result.permissionDenied) {
        state = state.copyWith(
          isSyncing: false,
          syncMessage:
              'SMS permission was denied. Please enable it in phone Settings → Apps → Financial Clarity → Permissions → SMS.',
          syncSuccess: false,
        );
        return;
      }

      // Handle: no new transactions found
      if (result.transactions.isEmpty) {
        state = state.copyWith(
          isSyncing: false,
          syncMessage: result.skippedCount > 0
              ? 'Already up to date. ${result.skippedCount} transactions were previously synced.'
              : 'No bank/UPI transactions found in SMS for the last 90 days.',
          syncSuccess: true,
        );
        return;
      }

      // POST to /transactions/bulk — send all parsed transactions to our backend
      // The rawSmsBody field is intentionally excluded from the payload for privacy
      final payload = {
        'transactions': result.transactions
            .map((t) => {
                  'vendor': t.vendor,
                  'amount': t.amount,
                  'is_debit': t.isDebit,
                  'category': t.category,
                  'source': t.source,
                  'timestamp': t.timestamp.toUtc().toIso8601String(),
                  'description': null,
                })
            .toList(),
      };

      final response =
          await _dio.post('${ApiEndpoints.transactions}/bulk', data: payload);
      final created = response.data['created_count'] ?? 0;
      final skipped = response.data['skipped_duplicates'] ?? 0;

      state = state.copyWith(
        isSyncing: false,
        syncMessage: created > 0
            ? '✓ Synced $created new transaction${created == 1 ? '' : 's'}${skipped > 0 ? ' ($skipped duplicates skipped)' : ''}.'
            : 'All transactions already synced.',
        syncSuccess: true,
      );

      // Reload the transaction list and summary to reflect new data
      await loadTransactions(refresh: true);
      await loadSummary();

      // Trigger budget screen live updates
      _ref.read(transactionSyncEventProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Sync failed. Please check your connection and try again.',
        syncSuccess: false,
      );
    }
  }

  Future<void> loadTestData() async {
    state = state.copyWith(isSyncing: true, syncMessage: null);
    try {
      final now = DateTime.now().toUtc();
      final payload = {
        'transactions': [
          {
            'vendor': 'PhonePe Merchant',
            'amount': 150.0,
            'is_debit': true,
            'category': 'food',
            'source': 'phonepe',
            'timestamp': now.toIso8601String(),
            'description': 'UPI debit sample',
          },
          {
            'vendor': 'Salary Credit',
            'amount': 50000.0,
            'is_debit': false,
            'category': 'other',
            'source': 'gpay',
            'timestamp':
                now.subtract(const Duration(minutes: 5)).toIso8601String(),
            'description': 'Direct deposit sample',
          },
          {
            'vendor': 'Swiggy',
            'amount': 450.0,
            'is_debit': true,
            'category': 'food',
            'source': 'phonepe',
            'timestamp':
                now.subtract(const Duration(hours: 1)).toIso8601String(),
            'description': 'Dinner order',
          },
          {
            'vendor': 'Uber Ride',
            'amount': 320.0,
            'is_debit': true,
            'category': 'transport',
            'source': 'gpay',
            'timestamp':
                now.subtract(const Duration(hours: 2)).toIso8601String(),
            'description': 'Office commute',
          },
          {
            'vendor': 'Amazon Shopping',
            'amount': 1200.0,
            'is_debit': true,
            'category': 'shopping',
            'source': 'amazon_pay',
            'timestamp':
                now.subtract(const Duration(hours: 3)).toIso8601String(),
            'description': 'Household items',
          },
        ],
      };

      final response =
          await _dio.post('${ApiEndpoints.transactions}/bulk', data: payload);
      final created = response.data['created_count'] ?? 0;
      final skipped = response.data['skipped_duplicates'] ?? 0;

      state = state.copyWith(
        isSyncing: false,
        syncMessage:
            '✓ Loaded $created mock transactions (skipped $skipped duplicates).',
        syncSuccess: true,
      );

      await refresh();
      await loadSummary();

      // Trigger budget screen live updates
      _ref.read(transactionSyncEventProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Failed to load test data.',
        syncSuccess: false,
      );
    }
  }

  void setTab(String tab) {
    state = state.copyWith(activeTab: tab);
    loadTransactions(refresh: true);
  }

  void setFilter(String? category) {
    state = state.copyWith(
      categoryFilter: category,
      transactions: [],
      currentPage: 1,
      hasMore: true,
    );
    loadTransactions(refresh: true);
  }

  void setMonth(String month) {
    state = state.copyWith(
      selectedMonth: month,
      transactions: [],
      currentPage: 1,
      hasMore: true,
    );
    loadTransactions(refresh: true);
  }

  Future<void> refresh() => loadTransactions(refresh: true);
}

final transactionControllerProvider =
    StateNotifierProvider<TransactionController, TransactionState>((ref) {
  return TransactionController(ref.read(dioProvider), ref);
});

// Screen
class TransactionFeedScreen extends ConsumerStatefulWidget {
  const TransactionFeedScreen({super.key});

  @override
  ConsumerState<TransactionFeedScreen> createState() =>
      _TransactionFeedScreenState();
}

class _TransactionFeedScreenState extends ConsumerState<TransactionFeedScreen> {
  void _showMonthPicker(
      BuildContext context, WidgetRef ref, String currentMonth) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final now = DateTime.now();
        final months = List.generate(12, (index) {
          final date = DateTime(now.year, now.month - index, 1);
          return DateFormat('yyyy-MM').format(date);
        });

        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Month', style: AppTypography.titleMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: months.length,
                  itemBuilder: (context, idx) {
                    final monthStr = months[idx];
                    final date =
                        DateTime.tryParse('$monthStr-01') ?? DateTime.now();
                    final displayName = DateFormat('MMMM yyyy').format(date);
                    final isSelected = currentMonth == monthStr;

                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        title: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color:
                                isSelected ? AppColors.primary : Colors.black87,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_rounded,
                                color: AppColors.primary)
                            : null,
                        onTap: () {
                          ref
                              .read(transactionControllerProvider.notifier)
                              .setMonth(monthStr);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionControllerProvider);
    final controller = ref.read(transactionControllerProvider.notifier);

    ref.listen<TransactionState>(transactionControllerProvider, (prev, next) {
      // Show snackbar whenever isSyncing goes from true → false (sync just finished)
      if ((prev?.isSyncing ?? false) &&
          !next.isSyncing &&
          next.syncMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.syncMessage!),
            backgroundColor:
                next.syncSuccess ? Colors.green.shade700 : Colors.red.shade700,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = await SharedPreferences.getInstance();
        final shown = prefs.getBool('ios_sms_notice_shown') ?? false;
        if (!shown && context.mounted) {
          await prefs.setBool('ios_sms_notice_shown', true);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Automatic Sync Unavailable on iPhone'),
              content: const Text(
                'Apple does not allow apps to read SMS messages on iPhone. '
                'To track your transactions, please use the "Add Expense" button '
                'to log them manually after each payment.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it'),
                ),
              ],
            ),
          );
        }
      });
    }

    final selectedDate =
        DateTime.tryParse('${state.selectedMonth}-01') ?? DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transactions', style: AppTypography.titleLarge),
            Text(
              DateFormat('MMMM yyyy').format(selectedDate),
              style: AppTypography.bodySmall.copyWith(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () =>
                _showMonthPicker(context, ref, state.selectedMonth),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () =>
                _showFilterSheet(context, controller, state.categoryFilter),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Summary Header Card (Fixed at the top)
          _buildSummaryCard(state, controller),

          // 2. Scrollable content area
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              color: AppColors.primary,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scroll) {
                  if (scroll.metrics.pixels >=
                          scroll.metrics.maxScrollExtent - 200 &&
                      state.hasMore &&
                      !state.isLoading) {
                    controller.loadTransactions();
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Spending Pie Chart
                    SliverToBoxAdapter(
                      child: _buildPieChartSection(state),
                    ),
                    // Tab Filter Row
                    SliverToBoxAdapter(
                      child: _buildTabRow(state, controller),
                    ),
                    // Active Category filter indicator
                    if (state.categoryFilter != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Chip(
                              label: Text(
                                AppConstants
                                        .categoryNames[state.categoryFilter] ??
                                    state.categoryFilter!,
                              ),
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: () => controller.setFilter(null),
                              backgroundColor: AppColors.primarySurface,
                            ),
                          ),
                        ),
                      ),
                    // Transaction sliver list
                    _buildSliverList(state, controller),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showManualAddSheet(context),
        label: const Text('Add Expense'),
        icon: const Icon(Icons.add_rounded),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSummaryCard(
      TransactionState state, TransactionController controller) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Account Balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Budget Remaining',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Salary after savings, minus what you\'ve spent this month',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currencyFormatter
                      .format(state.spendableIncome - state.totalDebits),
                  style: TextStyle(
                    color: (state.spendableIncome - state.totalDebits) >= 0
                        ? AppColors.primary
                        : AppColors.error,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Salary & Savings Breakdown
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Salary',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFormatter.format(state.monthlyIncomeUsed),
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: Colors.grey.shade200),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Budget for Expenses',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFormatter.format(state.spendableIncome),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Salary − ${currencyFormatter.format(state.savingsFloorAmount)} savings floor = budget for expenses',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.inkMuted),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Spent & Received Breakdown
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Spent',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFormatter.format(state.totalDebits),
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: Colors.grey.shade200),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Received',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFormatter.format(state.totalCredits),
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed:
                      state.isSyncing ? null : () => controller.syncFromSms(),
                  icon: state.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Sync SMS'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
                Row(
                  children: [
                    Text(
                      state.liveSyncEnabled ? 'Live Sync On' : 'Live Sync Off',
                      style: AppTypography.bodySmall.copyWith(
                        color: state.liveSyncEnabled
                            ? AppColors.success
                            : AppColors.inkLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: state.liveSyncEnabled,
                      onChanged: (val) => controller.setLiveSync(val),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => controller.loadTestData(),
                  icon: const Icon(Icons.playlist_add_rounded,
                      color: Colors.blue),
                  label: const Text(
                    'Load Test Data (Debug Only)',
                    style: TextStyle(
                        color: Colors.blue, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.08),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPieChartSection(TransactionState state) {
    final nonZeroCategories = state.categoryBreakdown.where((item) {
      final amt = (item['total_amount'] as num?)?.toDouble() ?? 0.0;
      return amt > 0;
    }).toList();

    final showPieChart =
        (state.activeTab == 'all' || state.activeTab == 'debit') &&
            nonZeroCategories.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: showPieChart
          ? Column(
              key: const ValueKey('pie_chart_visible'),
              children: [
                SizedBox(
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                      sections: nonZeroCategories.map((item) {
                        final category = item['category'] ?? 'other';
                        final percentage =
                            (item['percentage'] as num?)?.toDouble() ?? 0.0;
                        final color = categoryColors[category] ??
                            categoryColors['other']!;
                        return PieChartSectionData(
                          color: color,
                          value: percentage,
                          title: percentage > 8
                              ? '${percentage.toStringAsFixed(0)}%'
                              : '',
                          radius: 50,
                          titleStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: nonZeroCategories.map((item) {
                      final category = item['category'] ?? 'other';
                      final color =
                          categoryColors[category] ?? categoryColors['other']!;
                      final displayName =
                          item['display_name'] ?? category.toUpperCase();
                      final amt =
                          (item['total_amount'] as num?)?.toDouble() ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$displayName: ${currencyFormatter.format(amt)}',
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            )
          : ((state.activeTab == 'all' || state.activeTab == 'debit')
              ? const Padding(
                  key: ValueKey('pie_chart_placeholder'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'No spending data yet',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                )
              : const SizedBox(key: ValueKey('pie_chart_empty'))),
    );
  }

  Widget _buildTabRow(
      TransactionState state, TransactionController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: state.activeTab == 'all',
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: state.activeTab == 'all' ? Colors.white : Colors.black87,
            ),
            onSelected: (selected) {
              if (selected) controller.setTab('all');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Debits'),
            selected: state.activeTab == 'debit',
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: state.activeTab == 'debit' ? Colors.white : Colors.black87,
            ),
            onSelected: (selected) {
              if (selected) controller.setTab('debit');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Credits'),
            selected: state.activeTab == 'credit',
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color:
                  state.activeTab == 'credit' ? Colors.white : Colors.black87,
            ),
            onSelected: (selected) {
              if (selected) controller.setTab('credit');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSliverList(
      TransactionState state, TransactionController controller) {
    if (state.error != null && state.transactions.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppErrorWidget(
          message: state.error!,
          onRetry: controller.refresh,
        ),
      );
    }

    if (state.isLoading && state.transactions.isEmpty) {
      return SliverToBoxAdapter(
        child: LoadingShimmer.list(count: 8),
      );
    }

    if (state.transactions.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('No transactions yet.'),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 80), // extra padding at the bottom for FAB spacing
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= state.transactions.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final txn = state.transactions[index];
            return _TransactionTile(transaction: txn, index: index);
          },
          childCount: state.transactions.length + (state.hasMore ? 1 : 0),
        ),
      ),
    );
  }

  void _showFilterSheet(
    BuildContext context,
    TransactionController controller,
    String? current,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter by Category', style: AppTypography.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: current == null,
                  onSelected: (_) {
                    controller.setFilter(null);
                    Navigator.pop(ctx);
                  },
                ),
                ...AppConstants.categoryNames.entries.map((e) => ChoiceChip(
                      label: Text(
                          '${AppConstants.categoryIcons[e.key] ?? ''} ${e.value}'),
                      selected: current == e.key,
                      onSelected: (_) {
                        controller.setFilter(e.key);
                        Navigator.pop(ctx);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showManualAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ManualAddSheet(),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final int index;

  const _TransactionTile({required this.transaction, required this.index});

  @override
  Widget build(BuildContext context) {
    final category = transaction['category'] ?? 'other';
    final icon = AppConstants.categoryIcons[category] ?? '💳';
    final vendor = transaction['vendor'] ?? '';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final timestamp = transaction['timestamp'] != null
        ? DateTime.tryParse(transaction['timestamp'])
        : null;
    final isDebit = transaction['is_debit'] ?? true;
    final source = transaction['source'] ?? 'manual';

    String sourceText = 'Manual';
    if (source == 'sms') {
      sourceText = 'SMS';
    } else if (source.toLowerCase() == 'phonepe') {
      sourceText = 'PhonePe';
    } else if (source.toLowerCase() == 'gpay') {
      sourceText = 'GPay';
    } else if (source.toLowerCase() == 'paytm') {
      sourceText = 'Paytm';
    } else if (source.toLowerCase() == 'aa') {
      sourceText = 'AA';
    } else {
      sourceText = source.toString().toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vendor,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sourceText,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${AppConstants.categoryNames[category] ?? category}'
                    '${timestamp != null ? '  •  ${DateFormat.MMMd().format(timestamp)}' : ''}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isDebit ? '-' : '+'}₹${currencyFormatter.format(amount).replaceAll('₹', '')}',
              style: AppTypography.moneyMedium.copyWith(
                color: isDebit ? AppColors.error : AppColors.success,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualAddSheet extends ConsumerStatefulWidget {
  const _ManualAddSheet({super.key});

  @override
  ConsumerState<_ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends ConsumerState<_ManualAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _vendorController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'other';
  bool _isDebit = true;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _vendorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid amount greater than 0')),
      );
      return;
    }

    final vendor = _vendorController.text.trim();
    if (vendor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a vendor name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = ref.read(dioProvider);
      final payload = {
        'vendor': vendor,
        'amount': amount,
        'category': _selectedCategory,
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'source': 'manual',
        'is_debit': _isDebit,
        'timestamp': _selectedDate.toUtc().toIso8601String(),
      };

      final response = await dio.post(ApiEndpoints.transactions, data: payload);
      final responseData = response.data;
      final warnings =
          List<Map<String, dynamic>>.from(responseData['warnings'] ?? []);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction saved!'),
            backgroundColor: AppColors.success,
          ),
        );

        // Trigger budget screen live updates
        ref.read(transactionSyncEventProvider.notifier).state++;
        ref.read(transactionControllerProvider.notifier).refresh();

        if (warnings.isNotEmpty) {
          for (final warning in warnings) {
            final threshold = warning['threshold'] ?? 0;
            final message = warning['message'] ?? '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      threshold >= 85
                          ? Icons.warning_rounded
                          : Icons.info_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(message)),
                  ],
                ),
                backgroundColor:
                    threshold >= 85 ? AppColors.error : AppColors.warning,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
              ),
            );
            await Future.delayed(const Duration(milliseconds: 600));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save transaction'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add Transaction',
                  style: AppTypography.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Amount Field
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    prefixText: '₹ ',
                    labelText: 'Amount',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Amount is required';
                    }
                    final amt = double.tryParse(val);
                    if (amt == null || amt <= 0) {
                      return 'Amount must be greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Vendor Field
                TextFormField(
                  controller: _vendorController,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Vendor / Paid To',
                    hintText: 'Who did you pay? (e.g. Zomato, Kirana shop)',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Vendor name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description Field (Optional)
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Add note or description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Transaction Type Toggle
                const Text('Transaction Type',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Expense (Debit)'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Income (Credit)'),
                    ),
                  ],
                  selected: <bool>{_isDebit},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _isDebit = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // Category Selector Wrap
                const Text('Category',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.categoryNames.entries.map((e) {
                    final key = e.key;
                    final val = e.value;
                    final emoji = AppConstants.categoryIcons[key] ?? '';
                    return ChoiceChip(
                      label: Text('$emoji $val'),
                      selected: _selectedCategory == key,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = key;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Date Picker
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    title: const Text('Transaction Date'),
                    subtitle:
                        Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                    trailing: const Icon(Icons.calendar_today_rounded),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade400, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onTap: () => _selectDate(context),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Save Transaction',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
