/// Investment Advisor — Reactive allocation dashboard based on risk profile.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

// State
class AdvisorState {
  final bool hasProfile;
  final String riskLevel;
  final int riskScore;
  final String description;
  final Map<String, double> allocation;
  final Map<String, dynamic> explanations;
  final bool isLoading;
  final String? error;

  const AdvisorState({
    this.hasProfile = false,
    this.riskLevel = '',
    this.riskScore = 0,
    this.description = '',
    this.allocation = const {},
    this.explanations = const {},
    this.isLoading = false,
    this.error,
  });
}

// Controller
class AdvisorController extends StateNotifier<AdvisorState> {
  final Dio _dio;

  AdvisorController(this._dio) : super(const AdvisorState()) {
    loadAdvice();
  }

  Future<void> loadAdvice() async {
    state = const AdvisorState(isLoading: true);

    try {
      final response = await _dio.get(ApiEndpoints.investmentAdvisor);
      final data = response.data;

      if (data['has_profile'] != true) {
        state = const AdvisorState(hasProfile: false);
        return;
      }

      final rawAllocation = data['recommended_allocation'] as Map<String, dynamic>;
      final allocation = rawAllocation.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );

      state = AdvisorState(
        hasProfile: true,
        riskLevel: data['risk_level'] ?? '',
        riskScore: data['risk_score'] ?? 0,
        description: data['description'] ?? '',
        allocation: allocation,
        explanations: data['asset_explanations'] ?? {},
      );
    } catch (e) {
      state = const AdvisorState(error: 'Failed to load advisor data');
    }
  }
}

final advisorControllerProvider =
    StateNotifierProvider<AdvisorController, AdvisorState>((ref) {
  return AdvisorController(ref.read(dioProvider));
});

// Screen
class AdvisorScreen extends ConsumerWidget {
  const AdvisorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(advisorControllerProvider);
    final controller = ref.read(advisorControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Investment Advisor', style: AppTypography.titleLarge),
      ),
      body: _buildBody(state, controller),
    );
  }

  Widget _buildBody(AdvisorState state, AdvisorController controller) {
    if (state.isLoading) return LoadingShimmer.list(count: 4, itemHeight: 140);
    if (state.error != null) {
      return AppErrorWidget(message: state.error!, onRetry: controller.loadAdvice);
    }
    if (!state.hasProfile) return _buildNoProfile();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Risk profile badge
        AnimatedCard(
          delayIndex: 0,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${state.riskScore}',
                    style: AppTypography.moneyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.riskLevel, style: AppTypography.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Risk Profile Score: ${state.riskScore}/100',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Allocation donut chart
        AnimatedCard(
          delayIndex: 1,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recommended Allocation', style: AppTypography.titleMedium),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 50,
                    sections: state.allocation.entries.map((entry) {
                      return PieChartSectionData(
                        value: entry.value,
                        title: '${entry.value.toStringAsFixed(0)}%',
                        color: AppColors.assetColor(entry.key),
                        radius: 55,
                        titleStyle: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Legend
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: state.allocation.entries.map((entry) {
                  final name = _assetName(entry.key);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.assetColor(entry.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$name (${entry.value.toStringAsFixed(0)}%)',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // "Why" expansion tiles for each asset class
        Text('Why These Assets?', style: AppTypography.titleMedium),
        const SizedBox(height: 8),

        ...state.allocation.entries.toList().asMap().entries.map((mapEntry) {
          final entry = mapEntry.value;
          final idx = mapEntry.key;
          final explanation = state.explanations[entry.key];
          final name = explanation?['name'] ?? _assetName(entry.key);
          final why = explanation?['why'] ?? 'Recommended for your risk profile.';

          return AnimatedCard(
            delayIndex: idx + 2,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.assetColor(entry.key).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _assetIcon(entry.key),
                  color: AppColors.assetColor(entry.key),
                  size: 22,
                ),
              ),
              title: Text(name, style: AppTypography.titleSmall),
              subtitle: Text(
                '${entry.value.toStringAsFixed(0)}% allocation',
                style: AppTypography.bodySmall,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    why,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.inkLight,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildNoProfile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.quiz_outlined, size: 64, color: AppColors.inkMuted),
            const SizedBox(height: 16),
            Text(
              'Complete your risk assessment to get personalized investment advice.',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.inkLight),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _assetName(String type) {
    const names = {
      'fixed_deposit': 'Fixed Deposits',
      'bonds': 'Bonds',
      'mutual_fund': 'Mutual Funds',
      'stocks': 'Stocks',
      'gold': 'Gold',
    };
    return names[type] ?? type;
  }

  IconData _assetIcon(String type) {
    const icons = {
      'fixed_deposit': Icons.shield_outlined,
      'bonds': Icons.account_balance_outlined,
      'mutual_fund': Icons.pie_chart_outline,
      'stocks': Icons.trending_up,
      'gold': Icons.diamond_outlined,
    };
    return icons[type] ?? Icons.monetization_on_outlined;
  }
}
