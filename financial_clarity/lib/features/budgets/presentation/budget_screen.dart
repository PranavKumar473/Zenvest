/// Budget Screen — Category budget cards with dynamic color progress bars.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

// State
class BudgetState {
  final List<Map<String, dynamic>> budgets;
  final bool isLoading;
  final String? error;

  const BudgetState({
    this.budgets = const [],
    this.isLoading = false,
    this.error,
  });
}

// Controller
class BudgetController extends StateNotifier<BudgetState> {
  final Dio _dio;

  BudgetController(this._dio) : super(const BudgetState()) {
    loadBudgets();
  }

  Future<void> loadBudgets() async {
    state = BudgetState(isLoading: true, budgets: state.budgets);

    try {
      final now = DateTime.now();
      final monthYear = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final response = await _dio.get(
        '${ApiEndpoints.budgets}?month_year=$monthYear',
      );

      final budgets = List<Map<String, dynamic>>.from(response.data);
      state = BudgetState(budgets: budgets);
    } catch (e) {
      state = BudgetState(error: 'Failed to load budgets', budgets: state.budgets);
    }
  }
}

final budgetControllerProvider =
    StateNotifierProvider<BudgetController, BudgetState>((ref) {
  return BudgetController(ref.read(dioProvider));
});

// Screen
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(budgetControllerProvider);
    final controller = ref.read(budgetControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Budgets', style: AppTypography.titleLarge),
      ),
      body: _buildBody(state, controller),
    );
  }

  Widget _buildBody(BudgetState state, BudgetController controller) {
    if (state.isLoading && state.budgets.isEmpty) {
      return LoadingShimmer.list(count: 6, itemHeight: 120);
    }

    if (state.error != null && state.budgets.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: controller.loadBudgets,
      );
    }

    if (state.budgets.isEmpty) {
      return const Center(child: Text('No budgets set up yet.'));
    }

    // Calculate totals for summary card
    double totalLimit = 0;
    double totalSpent = 0;
    for (final b in state.budgets) {
      totalLimit += (b['limit_amount'] as num?)?.toDouble() ?? 0;
      totalSpent += (b['current_spent'] as num?)?.toDouble() ?? 0;
    }

    return RefreshIndicator(
      onRefresh: controller.loadBudgets,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          AnimatedCard(
            delayIndex: 0,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly Overview', style: AppTypography.titleMedium),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MetricColumn(
                      label: 'Total Budget',
                      value: '₹${totalLimit.toStringAsFixed(0)}',
                    ),
                    _MetricColumn(
                      label: 'Spent',
                      value: '₹${totalSpent.toStringAsFixed(0)}',
                      valueColor: AppColors.warning,
                    ),
                    _MetricColumn(
                      label: 'Remaining',
                      value: '₹${(totalLimit - totalSpent).toStringAsFixed(0)}',
                      valueColor: AppColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Category budget cards
          ...state.budgets.asMap().entries.map((entry) {
            return _BudgetCategoryCard(
              budget: entry.value,
              index: entry.key + 1,
            );
          }),
        ],
      ),
    );
  }
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
  final int index;

  const _BudgetCategoryCard({required this.budget, required this.index});

  @override
  Widget build(BuildContext context) {
    final category = budget['category'] ?? 'other';
    final icon = AppConstants.categoryIcons[category] ?? '💳';
    final name = AppConstants.categoryNames[category] ?? category;
    final limit = (budget['limit_amount'] as num?)?.toDouble() ?? 1;
    final spent = (budget['current_spent'] as num?)?.toDouble() ?? 0;
    final percentage = (budget['spent_percentage'] as num?)?.toDouble() ?? 0;
    final status = budget['threshold_status'] ?? 'safe';
    final remaining = (budget['remaining'] as num?)?.toDouble() ?? 0;

    final barColor = AppColors.budgetColor(status);

    return AnimatedCard(
      delayIndex: index,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name, style: AppTypography.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: barColor.withOpacity(0.1),
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

          // Animated progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              child: LinearProgressIndicator(
                value: (percentage / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₹${spent.toStringAsFixed(0)} spent',
                style: AppTypography.bodySmall,
              ),
              Text(
                '₹${remaining.toStringAsFixed(0)} remaining',
                style: AppTypography.bodySmall.copyWith(
                  color: barColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
