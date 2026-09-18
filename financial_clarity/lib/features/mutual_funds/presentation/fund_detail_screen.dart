/// Comprehensive scheme analytics view — interactive NAV performance chart,
/// historical returns matrix (1Y/3Y/5Y/10Y + CAGR since inception), and
/// risk-adjusted metrics (Sharpe/Sortino/Alpha/Beta). AUM, expense ratio,
/// and sector allocation have no free/licensed data source and are shown
/// as an explicit "not available" state rather than fabricated — see
/// backend/app/services/mutual_fund_service.py::get_fund_detail.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/ambient_background.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/animated_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../domain/mutual_fund.dart';
import 'invest_modal.dart';

class FundDetailScreen extends ConsumerStatefulWidget {
  final int schemeCode;

  const FundDetailScreen({super.key, required this.schemeCode});

  @override
  ConsumerState<FundDetailScreen> createState() => _FundDetailScreenState();
}

class _FundDetailScreenState extends ConsumerState<FundDetailScreen> {
  FundDetail? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(ApiEndpoints.fundDetail(widget.schemeCode));
      if (mounted) {
        setState(() {
          _detail = FundDetail.fromJson(response.data as Map<String, dynamic>);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load fund details. NAV data may be temporarily unavailable.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _invest() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await showInvestModal(
      context,
      schemeName: detail.name,
      schemeCode: detail.schemeCode,
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Investment recorded successfully.'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Fund Details')),
        body: LoadingShimmer.list(count: 5, itemHeight: 130),
      );
    }
    if (_error != null || _detail == null) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Fund Details')),
        body: AppErrorWidget(message: _error ?? 'Fund not found.', onRetry: _load),
      );
    }

    final detail = _detail!;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, detail),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    children: [
                      _buildHeaderCard(detail),
                      const SizedBox(height: 16),
                      _buildDataSourceBanner(detail),
                      const SizedBox(height: 20),
                      if (detail.navChart.isNotEmpty) ...[
                        _sectionTitle('Performance'),
                        const SizedBox(height: 12),
                        _buildPerformanceChart(detail),
                        const SizedBox(height: 24),
                      ],
                      _sectionTitle('Historical Returns'),
                      const SizedBox(height: 12),
                      _buildReturnsMatrix(detail),
                      if (detail.yearlyReturns.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildYearlyReturnsChart(detail),
                      ],
                      const SizedBox(height: 24),
                      _sectionTitle('Risk-Adjusted Metrics'),
                      const SizedBox(height: 12),
                      _buildRiskMetrics(detail),
                      const SizedBox(height: 24),
                      _sectionTitle('Asset & Sector Allocation'),
                      const SizedBox(height: 12),
                      _buildAllocationUnavailable(detail),
                      const SizedBox(height: 24),
                      _sectionTitle('Fund Facts'),
                      const SizedBox(height: 12),
                      _buildFundFacts(detail),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _invest,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.trending_up_rounded, color: Colors.white),
        label: const Text('Invest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, FundDetail detail) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              detail.name,
              style: AppTypography.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: AppTypography.titleMedium);

  Widget _buildHeaderCard(FundDetail detail) {
    final ret1y = detail.returns1y;
    final positive = (ret1y ?? 0) >= 0;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.fundHouse != null) Text(detail.fundHouse!, style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted)),
          if (detail.category != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(detail.category!, style: AppTypography.labelSmall.copyWith(color: AppColors.primary)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (detail.nav != null) ...[
                Text('₹${detail.nav!.toStringAsFixed(2)}', style: AppTypography.moneyLarge),
                const SizedBox(width: 10),
              ],
              if (ret1y != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 16, color: positive ? AppColors.success : AppColors.error),
                      Text(
                        '${ret1y.toStringAsFixed(2)}% (1Y)',
                        style: AppTypography.metric.copyWith(color: positive ? AppColors.success : AppColors.error),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (detail.navDate != null) ...[
            const SizedBox(height: 2),
            Text('NAV as of ${detail.navDate}', style: AppTypography.labelSmall),
          ],
        ],
      ),
    );
  }

  Widget _buildDataSourceBanner(FundDetail detail) {
    if (detail.dataSource == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Source: ${detail.dataSource}. AUM, expense ratio, sector allocation, and fund manager are not shown — no free or licensed data source provides them.',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceChart(FundDetail detail) {
    final points = detail.navChart;
    return AnimatedCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(color: AppColors.chartGrid, strokeWidth: 0.5),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 46,
                  getTitlesWidget: (value, meta) => Text('₹${value.toStringAsFixed(0)}', style: AppTypography.labelSmall),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (points.length / 4).clamp(1, points.length).toDouble(),
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= points.length) return const Text('');
                    final d = points[idx].date;
                    return Text('${d.month}/${d.year % 100}', style: AppTypography.labelSmall);
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.nav)).toList(),
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.chartLine,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: AppColors.chartFill),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                  return LineTooltipItem('₹${spot.y.toStringAsFixed(2)}', AppTypography.labelMedium.copyWith(color: Colors.white));
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnsMatrix(FundDetail detail) {
    final entries = <MapEntry<String, double?>>[
      MapEntry('1Y', detail.returns1y),
      MapEntry('3Y', detail.returns3y),
      MapEntry('5Y', detail.returns5y),
      MapEntry('10Y', detail.returns10y),
      MapEntry('Since Inception', detail.returnsSinceInception),
    ];
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 16,
        children: entries.map((e) => _ReturnStat(label: e.key, value: e.value)).toList(),
      ),
    );
  }

  Widget _buildYearlyReturnsChart(FundDetail detail) {
    final years = detail.yearlyReturns;
    final maxAbs = years.map((y) => y.returnPct.abs()).fold(10.0, (a, b) => a > b ? a : b);
    return AnimatedCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxAbs * 1.2,
            minY: -maxAbs * 1.2,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(color: AppColors.chartGrid, strokeWidth: 0.5),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= years.length) return const Text('');
                    return Text('${years[idx].year}', style: AppTypography.labelSmall);
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem('${rod.toY.toStringAsFixed(1)}%', AppTypography.labelMedium.copyWith(color: Colors.white)),
              ),
            ),
            barGroups: years.asMap().entries.map((e) {
              final positive = e.value.returnPct >= 0;
              return BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(
                  toY: e.value.returnPct,
                  color: positive ? AppColors.success : AppColors.error,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildRiskMetrics(FundDetail detail) {
    final rm = detail.riskMetrics;
    if (!rm.hasAnyData) {
      return _unavailablePanel(
        'Risk-adjusted metrics require at least 6 months of aligned NAV and benchmark history — not yet available for this fund.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              if (rm.sharpeRatio != null) _ReturnStat(label: 'Sharpe Ratio', value: rm.sharpeRatio, suffix: ''),
              if (rm.sortinoRatio != null) _ReturnStat(label: 'Sortino Ratio', value: rm.sortinoRatio, suffix: ''),
              if (rm.alpha != null) _ReturnStat(label: 'Alpha', value: rm.alpha),
              if (rm.beta != null) _ReturnStat(label: 'Beta', value: rm.beta, suffix: ''),
              if (rm.volatilityAnnualized != null) _ReturnStat(label: 'Volatility (Ann.)', value: rm.volatilityAnnualized),
            ],
          ),
        ),
        if (rm.benchmarkUsed != null) ...[
          const SizedBox(height: 8),
          Text('Benchmark: ${rm.benchmarkUsed}', style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted)),
        ],
      ],
    );
  }

  Widget _buildAllocationUnavailable(FundDetail detail) {
    return _unavailablePanel(
      'Sector and asset allocation breakdown is not shown — no free or SEBI-licensed data source provides current portfolio holdings for this fund.',
    );
  }

  Widget _unavailablePanel(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pie_chart_outline_rounded, color: AppColors.inkMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildFundFacts(FundDetail detail) {
    final facts = <MapEntry<String, String>>[
      if (detail.schemeType != null) MapEntry('Scheme Type', detail.schemeType!),
      if (detail.isin != null) MapEntry('ISIN', detail.isin!),
      if (detail.inceptionDate != null) MapEntry('Inception Date', detail.inceptionDate!),
      const MapEntry('AUM', 'Not available'),
      const MapEntry('Expense Ratio', 'Not available'),
      const MapEntry('Fund Manager', 'Not available'),
    ];
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: facts
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(f.key, style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted)),
                      Text(
                        f.value,
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: f.value == 'Not available' ? AppColors.inkMuted : AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _ReturnStat extends StatelessWidget {
  final String label;
  final double? value;
  final String suffix;

  const _ReturnStat({required this.label, required this.value, this.suffix = '%'});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final positive = (v ?? 0) >= 0;
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelSmall),
          const SizedBox(height: 2),
          Text(
            v == null ? 'N/A' : '${positive && suffix == '%' ? '+' : ''}${v.toStringAsFixed(2)}$suffix',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: v == null ? AppColors.inkMuted : (suffix == '%' ? (positive ? AppColors.success : AppColors.error) : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
