/// Portfolio Analytics — Net worth chart, performance metrics, and asset breakdown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

// State
class PortfolioState {
  final Map<String, dynamic>? summary;
  final Map<String, dynamic>? netWorthHistory;
  final bool isLoading;
  final String? error;

  const PortfolioState({
    this.summary,
    this.netWorthHistory,
    this.isLoading = false,
    this.error,
  });
}

// Controller
class PortfolioController extends StateNotifier<PortfolioState> {
  final Dio _dio;

  PortfolioController(this._dio) : super(const PortfolioState()) {
    loadData();
  }

  Future<void> loadData() async {
    state = const PortfolioState(isLoading: true);

    try {
      final results = await Future.wait([
        _dio.get(ApiEndpoints.portfolioSummary),
        _dio.get(ApiEndpoints.netWorthHistory),
      ]);

      state = PortfolioState(
        summary: results[0].data,
        netWorthHistory: results[1].data,
      );
    } catch (e) {
      state = const PortfolioState(error: 'Failed to load portfolio data');
    }
  }
}

final portfolioControllerProvider =
    StateNotifierProvider<PortfolioController, PortfolioState>((ref) {
  return PortfolioController(ref.read(dioProvider));
});

// Screen
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(portfolioControllerProvider);
    final controller = ref.read(portfolioControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Portfolio', style: AppTypography.titleLarge),
      ),
      body: _buildBody(state, controller),
    );
  }

  Widget _buildBody(PortfolioState state, PortfolioController controller) {
    if (state.isLoading) return LoadingShimmer.list(count: 5, itemHeight: 120);
    if (state.error != null) {
      return AppErrorWidget(message: state.error!, onRetry: controller.loadData);
    }

    final summary = state.summary;
    final history = state.netWorthHistory;
    if (summary == null) return const Center(child: Text('No portfolio data.'));

    final totalInvested = (summary['total_invested'] as num?)?.toDouble() ?? 0;
    final totalCurrent = (summary['total_current_value'] as num?)?.toDouble() ?? 0;
    final totalReturn = (summary['total_return'] as num?)?.toDouble() ?? 0;
    final returnPct = (summary['total_return_percentage'] as num?)?.toDouble() ?? 0;
    final cagr = summary['portfolio_cagr'];
    final holdings = summary['holdings'] as List? ?? [];
    final allocation = summary['asset_allocation'] as Map<String, dynamic>? ?? {};

    // Net worth chart data
    final dataPoints = (history?['data_points'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: controller.loadData,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Net Worth card
          AnimatedCard(
            delayIndex: 0,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Worth', style: AppTypography.bodySmall),
                const SizedBox(height: 4),
                Text(
                  '₹${NumberFormat('#,##,###').format(totalCurrent)}',
                  style: AppTypography.moneyLarge,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      totalReturn >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 18,
                      color: totalReturn >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${totalReturn >= 0 ? '+' : ''}₹${NumberFormat('#,##,###').format(totalReturn.abs())} (${returnPct.toStringAsFixed(1)}%)',
                      style: AppTypography.metric.copyWith(
                        color: totalReturn >= 0
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Net Worth Line Chart
          if (dataPoints.length > 1)
            AnimatedCard(
              delayIndex: 1,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net Worth Trend', style: AppTypography.titleMedium),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: AppColors.chartGrid,
                            strokeWidth: 0.5,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '₹${(value / 1000).toStringAsFixed(0)}K',
                                  style: AppTypography.labelSmall,
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 2,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx >= 0 && idx < dataPoints.length) {
                                  final dateStr = dataPoints[idx]['date'] ?? '';
                                  final parts = dateStr.split('-');
                                  if (parts.length >= 2) {
                                    final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                                    final monthIdx = int.tryParse(parts[1]) ?? 0;
                                    return Text(
                                      monthIdx > 0 && monthIdx < months.length ? months[monthIdx] : '',
                                      style: AppTypography.labelSmall,
                                    );
                                  }
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: dataPoints.asMap().entries.map((entry) {
                              final value = (entry.value['value'] as num?)?.toDouble() ?? 0;
                              return FlSpot(entry.key.toDouble(), value);
                            }).toList(),
                            isCurved: true,
                            curveSmoothness: 0.3,
                            color: AppColors.chartLine,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.chartFill,
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                return LineTooltipItem(
                                  '₹${NumberFormat('#,##,###').format(spot.y)}',
                                  AppTypography.labelMedium.copyWith(
                                    color: Colors.white,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),

          // Performance Metrics
          AnimatedCard(
            delayIndex: 2,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Performance Metrics', style: AppTypography.titleMedium),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _PerformanceMetric(
                        label: 'Total Invested',
                        value: '₹${NumberFormat('#,##,###').format(totalInvested)}',
                      ),
                    ),
                    Expanded(
                      child: _PerformanceMetric(
                        label: 'Current Value',
                        value: '₹${NumberFormat('#,##,###').format(totalCurrent)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PerformanceMetric(
                        label: 'Total Returns',
                        value: '${totalReturn >= 0 ? '+' : ''}${returnPct.toStringAsFixed(1)}%',
                        valueColor: totalReturn >= 0 ? AppColors.success : AppColors.error,
                      ),
                    ),
                    Expanded(
                      child: _PerformanceMetric(
                        label: 'Portfolio CAGR',
                        value: cagr != null ? '${cagr.toStringAsFixed(1)}%' : '—',
                        valueColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Holdings breakdown
          Text('Holdings', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          ...holdings.asMap().entries.map((entry) {
            final holding = entry.value as Map<String, dynamic>;
            return _HoldingTile(holding: holding, index: entry.key + 3);
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PerformanceMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PerformanceMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.moneyMedium.copyWith(
            color: valueColor ?? AppColors.ink,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _HoldingTile extends StatelessWidget {
  final Map<String, dynamic> holding;
  final int index;

  const _HoldingTile({required this.holding, required this.index});

  @override
  Widget build(BuildContext context) {
    final name = holding['asset_name'] ?? '';
    final type = holding['asset_type'] ?? '';
    final currentValue = (holding['current_value'] as num?)?.toDouble() ?? 0;
    final returnPct = (holding['return_percentage'] as num?)?.toDouble() ?? 0;
    final xirr = holding['calculated_xirr'];
    final cagr = holding['calculated_cagr'];
    final isPositive = returnPct >= 0;

    return AnimatedCard(
      delayIndex: index,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Asset type indicator
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.assetColor(type),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (xirr != null)
                      Text(
                        'XIRR: ${xirr.toStringAsFixed(1)}%',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    if (xirr != null && cagr != null)
                      Text(' • ', style: AppTypography.labelSmall),
                    if (cagr != null)
                      Text(
                        'CAGR: ${cagr.toStringAsFixed(1)}%',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${NumberFormat('#,##,###').format(currentValue)}',
                style: AppTypography.moneyMedium.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                '${isPositive ? '+' : ''}${returnPct.toStringAsFixed(1)}%',
                style: AppTypography.labelMedium.copyWith(
                  color: isPositive ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
