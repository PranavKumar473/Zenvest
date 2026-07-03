/// Budget Screen — Redesigned with AI suggestion banner, limit editor, and framework breakdown sheet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';
import '../../transactions/presentation/transaction_feed_screen.dart'
    show transactionSyncEventProvider;

final currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

class BudgetState {
  final List<Map<String, dynamic>> budgets;
  final List<Map<String, dynamic>> suggestions;
  final bool isLoading;
  final bool isSuggestionsLoading;
  final bool isApplying;
  final String? error;
  final String? successMessage;
  final Map<String, dynamic>? frameworkBreakdown;
  final double monthlyIncomeUsed;
  final double savingsFloorPercentage;
  final String riskLevel;
  final double spendableIncome;
  final double savingsFloorAmount;
  final DateTime? lastUpdatedAt;

  const BudgetState({
    this.budgets = const [],
    this.suggestions = const [],
    this.isLoading = false,
    this.isSuggestionsLoading = false,
    this.isApplying = false,
    this.error,
    this.successMessage,
    this.frameworkBreakdown,
    this.monthlyIncomeUsed = 0.0,
    this.savingsFloorPercentage = 0.0,
    this.riskLevel = 'Moderate',
    this.spendableIncome = 0.0,
    this.savingsFloorAmount = 0.0,
    this.lastUpdatedAt,
  });

  BudgetState copyWith({
    List<Map<String, dynamic>>? budgets,
    List<Map<String, dynamic>>? suggestions,
    bool? isLoading,
    bool? isSuggestionsLoading,
    bool? isApplying,
    String? error,
    String? successMessage,
    Map<String, dynamic>? frameworkBreakdown,
    double? monthlyIncomeUsed,
    double? savingsFloorPercentage,
    String? riskLevel,
    double? spendableIncome,
    double? savingsFloorAmount,
    DateTime? lastUpdatedAt,
  }) {
    return BudgetState(
      budgets: budgets ?? this.budgets,
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      isSuggestionsLoading: isSuggestionsLoading ?? this.isSuggestionsLoading,
      isApplying: isApplying ?? this.isApplying,
      error: error ?? this.error,
      successMessage: successMessage ?? this.successMessage,
      frameworkBreakdown: frameworkBreakdown ?? this.frameworkBreakdown,
      monthlyIncomeUsed: monthlyIncomeUsed ?? this.monthlyIncomeUsed,
      savingsFloorPercentage: savingsFloorPercentage ?? this.savingsFloorPercentage,
      riskLevel: riskLevel ?? this.riskLevel,
      spendableIncome: spendableIncome ?? this.spendableIncome,
      savingsFloorAmount: savingsFloorAmount ?? this.savingsFloorAmount,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

class BudgetController extends StateNotifier<BudgetState> {
  final Dio _dio;
  final Ref _ref;

  BudgetController(this._dio, this._ref) : super(const BudgetState()) {
    loadBudgets();
    loadSuggestions();
    
    // Listen for transaction sync events
    _ref.listen(transactionSyncEventProvider, (prev, next) {
      if (next != prev) {
        loadBudgets();
        loadSuggestions();
      }
    });
  }

  Future<void> loadBudgets() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final now = DateTime.now();
      final monthYear = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final response = await _dio.get(
        '${ApiEndpoints.budgets}?month_year=$monthYear',
      );
      final budgets = List<Map<String, dynamic>>.from(response.data);
      state = state.copyWith(
        budgets: budgets,
        isLoading: false,
        lastUpdatedAt: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to load budgets', isLoading: false);
    }
  }

  Future<void> resyncLimits() async {
    try {
      await _dio.post('/budgets/resync-limits');
      await loadBudgets();
      await loadSuggestions();
    } catch (e) {
      // silent fail — loadBudgets will still refresh
    }
  }

  Future<void> loadSuggestions() async {
    state = state.copyWith(isSuggestionsLoading: true);
    try {
      final response = await _dio.get(ApiEndpoints.budgetSuggestions);
      final data = response.data;
      state = state.copyWith(
        suggestions: List<Map<String, dynamic>>.from(data['suggestions'] ?? []),
        frameworkBreakdown: data['framework_breakdown'],
        monthlyIncomeUsed: (data['monthly_income_used'] as num?)?.toDouble() ?? 0.0,
        savingsFloorPercentage: (data['savings_floor_percentage'] as num?)?.toDouble() ?? 0.0,
        riskLevel: data['risk_level'] ?? 'Moderate',
        spendableIncome: (data['spendable_income'] as num?)?.toDouble() ?? 0.0,
        savingsFloorAmount: (data['savings_floor_amount'] as num?)?.toDouble() ?? 0.0,
        isSuggestionsLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isSuggestionsLoading: false);
    }
  }

  Future<void> applySuggestions() async {
    state = state.copyWith(isApplying: true, successMessage: null);
    try {
      await _dio.post(ApiEndpoints.budgetApplySuggestions);
      await loadBudgets();
      state = state.copyWith(
        isApplying: false,
        successMessage: 'Budgets created for this month!',
      );
    } catch (e) {
      state = state.copyWith(
        isApplying: false,
        successMessage: 'Failed to apply suggestions.',
      );
    }
  }

  Future<void> updateLimit(String budgetId, double newLimit) async {
    try {
      await _dio.patch(
        ApiEndpoints.budgetById(budgetId),
        data: {'limit_amount': newLimit},
      );
      await loadBudgets();
    } catch (_) {}
  }
}

final budgetControllerProvider =
    StateNotifierProvider<BudgetController, BudgetState>((ref) {
  return BudgetController(ref.read(dioProvider), ref);
});

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(budgetControllerProvider);
    final controller = ref.read(budgetControllerProvider.notifier);

    // Show status snackbars if success message is updated
    ref.listen<BudgetState>(budgetControllerProvider, (prev, next) {
      if (next.successMessage != null && next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: next.successMessage!.contains('Failed')
                ? AppColors.error
                : AppColors.success,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Budgets', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              controller.loadBudgets();
              controller.loadSuggestions();
            },
          ),
        ],
      ),
      body: _buildBody(context, state, controller),
    );
  }

  Widget _buildBody(BuildContext context, BudgetState state, BudgetController controller) {
    if (state.isLoading && state.budgets.isEmpty) {
      return LoadingShimmer.list(count: 6, itemHeight: 120);
    }

    if (state.error != null && state.budgets.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: controller.loadBudgets,
      );
    }

    // Calculations for metrics overview
    double totalLimit = 0;
    double totalSpent = 0;
    for (final b in state.budgets) {
      totalLimit += (b['limit_amount'] as num?)?.toDouble() ?? 0;
      totalSpent += (b['current_spent'] as num?)?.toDouble() ?? 0;
    }
    double remaining = totalLimit - totalSpent;

    return RefreshIndicator(
      onRefresh: () async {
        await controller.loadBudgets();
        await controller.loadSuggestions();
      },
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section A: AI suggestion banner (shown when budgets are empty)
          if (state.budgets.isEmpty)
            _SuggestionBanner(state: state, controller: controller)
          else ...[
            // Section B: Monthly Overview Card (always visible when budgets exist)
            _OverviewCard(
              totalLimit: totalLimit,
              totalSpent: totalSpent,
              remaining: remaining,
              state: state,
              controller: controller,
            ),
            const SizedBox(height: 16),
            
            // Section C: Category Budget Cards
            Text('Spending Categories', style: AppTypography.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Transparency Note: These suggested maximum limits are derived from your income and risk profile to keep you from bankruptcy. They are ceilings, not spending targets!',
              style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            ...state.budgets.asMap().entries.map((entry) {
              final budget = entry.value;
              final category = budget['category'] ?? '';
              final suggestionItem = state.suggestions.firstWhere(
                (item) => item['category'] == category,
                orElse: () => <String, dynamic>{},
              );
              final suggestedLimit = (suggestionItem['suggested_limit'] as num?)?.toDouble();

              return _BudgetCategoryCard(
                budget: budget,
                suggestedLimit: suggestedLimit,
                index: entry.key + 1,
                onTap: () => _showEditLimitSheet(context, budget, suggestedLimit, controller),
              );
            }),
          ],
        ],
      ),
    );
  }

  void _showEditLimitSheet(
    BuildContext context,
    Map<String, dynamic> budget,
    double? suggestedLimit,
    BudgetController controller,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditLimitSheet(
        budget: budget,
        suggestedLimit: suggestedLimit,
        controller: controller,
      ),
    );
  }
}

class _SuggestionBanner extends StatelessWidget {
  final BudgetState state;
  final BudgetController controller;

  const _SuggestionBanner({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final savingsAmt = state.monthlyIncomeUsed * (state.savingsFloorPercentage / 100);
    final now = DateTime.now();
    final currentMonthYearStr = DateFormat('MMMM yyyy').format(now);

    return AnimatedCard(
      delayIndex: 0,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Smart Budget Suggestions', style: AppTypography.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          
          // Numbered Onboarding Flow Checklist
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildFlowStep(
                  stepNumber: '✓',
                  title: 'Profile analyzed matching income & risk level',
                  isCompleted: true,
                ),
                const SizedBox(height: 10),
                _buildFlowStep(
                  stepNumber: '2',
                  title: 'Review suggested limits below (tap to adjust)',
                  isCompleted: false,
                ),
                const SizedBox(height: 10),
                _buildFlowStep(
                  stepNumber: '3',
                  title: 'Tap "Apply" to save and activate budgets',
                  isCompleted: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.amber.shade800, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Transparency Note: These suggested maximum limits are derived from your income and risk profile to keep you from bankruptcy. They are ceilings, not spending targets!',
                    style: TextStyle(fontSize: 10, color: Colors.black87, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // User Profile Metrics
          const Text(
            'Personalized Allocation Parameters:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          _ProfileRow(label: 'Income Midpoint', value: currencyFormatter.format(state.monthlyIncomeUsed)),
          _ProfileRow(label: 'Risk Profile', value: state.riskLevel),
          _ProfileRow(label: 'Age-Driven Savings Floor', value: '${state.savingsFloorPercentage.toStringAsFixed(0)}% (${currencyFormatter.format(savingsAmt)})'),
          const SizedBox(height: 16),

          // Category limits mini cards
          const Text(
            'Suggested Allocations:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          if (state.isSuggestionsLoading)
            const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.suggestions.map((item) {
                final cat = item['category'] ?? '';
                final limit = (item['suggested_limit'] as num?)?.toDouble() ?? 0.0;
                final icon = AppConstants.categoryIcons[cat] ?? '💳';
                final name = AppConstants.categoryNames[cat] ?? cat;

                return Container(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 11, color: AppColors.inkLight)),
                            Text(currencyFormatter.format(limit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),

          // Action buttons
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.isApplying ? null : () => controller.applySuggestions(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: state.isApplying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Apply Suggestions for $currentMonthYearStr', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _FrameworkBreakdownSheet(state: state),
                );
              },
              child: const Text('How was this calculated? →', style: TextStyle(color: AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep({required String stepNumber, required String title, required bool isCompleted}) {
    return Row(
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: isCompleted ? Colors.green : Colors.grey.shade400,
          child: Text(
            stepNumber,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isCompleted ? Colors.black87 : Colors.black54,
              fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final double totalLimit;
  final double totalSpent;
  final double remaining;
  final BudgetState state;
  final BudgetController controller;

  const _OverviewCard({
    required this.totalLimit,
    required this.totalSpent,
    required this.remaining,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final savingsFloor = state.monthlyIncomeUsed * (state.savingsFloorPercentage / 100);

    return AnimatedCard(
      delayIndex: 0,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly Overview', style: AppTypography.titleMedium),
                  if (state.lastUpdatedAt != null)
                    Text(
                      'Updated ${_formatTimeAgo(state.lastUpdatedAt!)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, size: 16),
                    color: AppColors.primary,
                    tooltip: 'Recalculate Limits',
                    onPressed: () => controller.resyncLimits(),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      controller.loadSuggestions();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => _FrameworkBreakdownSheet(state: state),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                    label: const Text('Suggested', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MetricColumn(
                label: 'Total Budget',
                value: currencyFormatter.format(totalLimit),
              ),
              _MetricColumn(
                label: 'Spent',
                value: currencyFormatter.format(totalSpent),
                valueColor: AppColors.warning,
              ),
              _MetricColumn(
                label: 'Budget Headroom',
                value: currencyFormatter.format(remaining),
                valueColor: AppColors.success,
              ),
            ],
          ),
          
          // Fix 2C: Reconciliation row
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Why are these numbers different?'),
                  content: Text(
                    'Budget Headroom (${currencyFormatter.format(remaining)}) is how much you can still spend inside your categories.\n\n'
                    'Money Available (${currencyFormatter.format(state.spendableIncome + state.savingsFloorAmount - totalSpent)}) on the Transactions screen includes your '
                    '${currencyFormatter.format(state.savingsFloorAmount)} Savings Floor + any unallocated income not assigned to a budget.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Why doesn\'t this match my Account Balance?',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),

          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text('🏦', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Savings Floor (locked first)',
                          style: AppTypography.labelMedium),
                      Text('${currencyFormatter.format(state.savingsFloorAmount)}/month · ${state.savingsFloorPercentage.toStringAsFixed(0)}% of income',
                          style: AppTypography.bodySmall),
                    ],
                  ),
                ),
                Text(currencyFormatter.format(state.savingsFloorAmount),
                    style: AppTypography.moneyMedium.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimeAgo(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

class _MetricColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricColumn({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTypography.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.moneyMedium.copyWith(
            color: valueColor ?? AppColors.ink,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _BudgetCategoryCard extends StatelessWidget {
  final Map<String, dynamic> budget;
  final double? suggestedLimit;
  final int index;
  final VoidCallback onTap;

  const _BudgetCategoryCard({
    required this.budget,
    required this.suggestedLimit,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = budget['category'] ?? 'other';
    final icon = AppConstants.categoryIcons[category] ?? '💳';
    final name = AppConstants.categoryNames[category] ?? category;
    final limit = (budget['limit_amount'] as num?)?.toDouble() ?? 1.0;
    final spent = (budget['current_spent'] as num?)?.toDouble() ?? 0.0;
    final percentage = (budget['spent_percentage'] as num?)?.toDouble() ?? 0.0;
    final status = budget['threshold_status'] ?? 'safe';
    final remaining = (budget['remaining'] as num?)?.toDouble() ?? 0.0;

    final barColor = AppColors.budgetColor(status);

    Widget? varianceBadge;

    return AnimatedCard(
      delayIndex: index,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppTypography.titleSmall),
                        if (varianceBadge != null) ...[
                          const SizedBox(height: 4),
                          varianceBadge,
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: AppTypography.labelMedium.copyWith(color: barColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (percentage / 100).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${currencyFormatter.format(spent)} spent',
                    style: AppTypography.bodySmall,
                  ),
                  Text(
                    '${currencyFormatter.format(remaining.abs())} ${remaining >= 0 ? "remaining" : "overrun"}',
                    style: AppTypography.bodySmall.copyWith(
                      color: remaining >= 0 ? barColor : AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditLimitSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> budget;
  final double? suggestedLimit;
  final BudgetController controller;

  const _EditLimitSheet({
    required this.budget,
    required this.suggestedLimit,
    required this.controller,
  });

  @override
  ConsumerState<_EditLimitSheet> createState() => _EditLimitSheetState();
}

class _EditLimitSheetState extends ConsumerState<_EditLimitSheet> {
  late TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    final currentLimit = (widget.budget['limit_amount'] as num?)?.toDouble() ?? 0.0;
    _limitController = TextEditingController(text: currentLimit.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.budget['category'] ?? 'other';
    final name = AppConstants.categoryNames[category] ?? category;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 16),
          Text('Edit Limit for $name', style: AppTypography.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _limitController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            decoration: InputDecoration(
              labelText: 'Monthly Limit (INR)',
              prefixText: '₹',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (widget.suggestedLimit != null) ...[
            const SizedBox(height: 10),
            Text(
              'Suggested ceiling: ${currencyFormatter.format(widget.suggestedLimit!)} based on your profile.\n'
              '💡 Staying below this cap keeps your net savings plan safe.',
              style: const TextStyle(color: Colors.grey, fontSize: 11, height: 1.3),
            ),
          ],
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _limitController,
            builder: (context, value, _) {
              final allBudgets = ref.watch(budgetControllerProvider).budgets;
              final spendable = ref.watch(budgetControllerProvider).spendableIncome;

              final otherCatsTotal = allBudgets
                  .where((b) => b['id'] != widget.budget['id'])
                  .fold(0.0, (sum, b) => sum + (b['limit_amount'] as num).toDouble());
              final thisAmount = double.tryParse(value.text) ?? 0.0;
              final newTotal = otherCatsTotal + thisAmount;
              final isOver = spendable > 0 && newTotal > spendable;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('All categories total:', style: AppTypography.labelMedium),
                      Text(
                        '₹${newTotal.toStringAsFixed(0)} / ₹${spendable.toStringAsFixed(0)}',
                        style: AppTypography.labelMedium.copyWith(
                          color: isOver ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (isOver)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠️ This exceeds your spendable income by ₹${(newTotal - spendable).toStringAsFixed(0)}. '
                        'Consider reducing another category.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isOver ? null : () {
                        final newLimit = double.tryParse(_limitController.text);
                        if (newLimit != null && newLimit > 0) {
                          widget.controller.updateLimit(widget.budget['id'], newLimit);
                          Navigator.pop(context);
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              );
            }
          ),
        ],
      ),
    );
  }
}

class _FrameworkBreakdownSheet extends StatelessWidget {
  final BudgetState state;

  const _FrameworkBreakdownSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final frameworks = state.frameworkBreakdown ?? {};
    final suggested = state.suggestions;
    final income = state.monthlyIncomeUsed;
    final spendable = state.spendableIncome;
    final savingsFloor = state.savingsFloorAmount;

    final warren = Map<String, dynamic>.from(frameworks['50_30_20_warren'] ?? {});
    final rohn = Map<String, dynamic>.from(frameworks['70_20_10_rohn'] ?? {});
    final bach = Map<String, dynamic>.from(frameworks['pay_yourself_first_bach'] ?? {});
    final ramsey = Map<String, dynamic>.from(frameworks['zero_based_ramsey'] ?? {});

    final categories = suggested.map((item) => item['category'] as String).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 16),
          Text('Your Monthly Money Flow', style: AppTypography.titleMedium),
          const SizedBox(height: 16),

          // Top section - Budget Envelope
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Income', style: TextStyle(color: AppColors.inkLight)),
                    Text(currencyFormatter.format(income), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('− Savings (${state.savingsFloorPercentage.toStringAsFixed(0)}%)', style: const TextStyle(color: AppColors.inkLight)),
                    Text('− ${currencyFormatter.format(savingsFloor)}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(height: 1, color: Colors.grey),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Spendable Budget', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(currencyFormatter.format(spendable), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Middle section - Category Envelope Bars
          Expanded(
            child: ListView(
              children: [
                Text('Category Allocation', style: AppTypography.titleSmall),
                const SizedBox(height: 16),
                ...suggested.map((item) {
                  final cat = item['category'] as String;
                  final name = AppConstants.categoryNames[cat] ?? cat;
                  final amount = (item['suggested_limit'] as num).toDouble();
                  final pct = spendable > 0 ? amount / spendable : 0.0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                            Text('${currencyFormatter.format(amount)}  (${(pct * 100).toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12, color: AppColors.inkLight)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('${currencyFormatter.format(state.spendableIncome)} (100%) ✓', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 1.0,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
                  ),
                ),
                const SizedBox(height: 32),

                // Bottom section - Framework Explanation
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('See how frameworks were blended →', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Table(
                          defaultColumnWidth: const FixedColumnWidth(100),
                          border: TableBorder.all(color: Colors.grey.shade200, width: 1, borderRadius: BorderRadius.circular(8)),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: Colors.grey.shade50),
                              children: [
                                const TableHeaderCell('Framework'),
                                const TableHeaderCell('Weight'),
                                ...categories.map((c) => TableHeaderCell(AppConstants.categoryNames[c] ?? c)),
                              ],
                            ),
                            TableRow(
                              children: [
                                const TableBodyCell('50/30/20 Warren'),
                                const TableBodyCell('25%'),
                                ...categories.map((c) => TableBodyCell(currencyFormatter.format(warren[c] ?? 0.0))),
                              ],
                            ),
                            TableRow(
                              children: [
                                const TableBodyCell('70/20/10 Rohn'),
                                const TableBodyCell('20%'),
                                ...categories.map((c) => TableBodyCell(currencyFormatter.format(rohn[c] ?? 0.0))),
                              ],
                            ),
                            TableRow(
                              children: [
                                const TableBodyCell('Pay Yourself Bach'),
                                const TableBodyCell('30%'),
                                ...categories.map((c) => TableBodyCell(currencyFormatter.format(bach[c] ?? 0.0))),
                              ],
                            ),
                            TableRow(
                              children: [
                                const TableBodyCell('Zero-Based Ramsey'),
                                const TableBodyCell('25%'),
                                ...categories.map((c) => TableBodyCell(currencyFormatter.format(ramsey[c] ?? 0.0))),
                              ],
                            ),
                            TableRow(
                              decoration: const BoxDecoration(color: AppColors.primarySurface),
                              children: [
                                const TableBodyCell('Blended Suggestion', isBold: true),
                                const TableBodyCell('-'),
                                ...categories.map((c) {
                                  final item = suggested.firstWhere((s) => s['category'] == c);
                                  return TableBodyCell(currencyFormatter.format(item['suggested_limit']), isBold: true);
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension BudgetStateAge on BudgetState {
  String ageGroup(Map<String, dynamic> frameworks) {
    return frameworks['age_group'] ?? '26-35';
  }
}

class _ParameterCard extends StatelessWidget {
  final String label;
  final String value;

  const _ParameterCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 60) / 3,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink)),
        ],
      ),
    );
  }
}

class TableHeaderCell extends StatelessWidget {
  final String text;

  const TableHeaderCell(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.ink),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class TableBodyCell extends StatelessWidget {
  final String text;
  final bool isBold;

  const TableBodyCell(this.text, {super.key, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isBold ? AppColors.primary : AppColors.inkLight,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
