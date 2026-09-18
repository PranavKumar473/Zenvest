import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/ambient_background.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../domain/mutual_fund.dart';
import 'invest_modal.dart';

class FundCompareScreen extends ConsumerStatefulWidget {
  final List<int> schemeCodes;

  const FundCompareScreen({super.key, required this.schemeCodes});

  @override
  ConsumerState<FundCompareScreen> createState() => _FundCompareScreenState();
}

class _FundCompareScreenState extends ConsumerState<FundCompareScreen> {
  List<FundDetail> _details = [];
  bool _isLoading = true;
  String? _error;

  final List<Color> _fundColors = [
    AppColors.primary,
    AppColors.success,
    Colors.deepOrangeAccent,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.schemeCodes.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'No funds selected for comparison.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(ApiEndpoints.fundCompare(widget.schemeCodes));
      final fundsList = (response.data['funds'] as List)
          .map((f) => FundDetail.fromJson(f as Map<String, dynamic>))
          .toList();
      
      if (mounted) {
        setState(() {
          _details = fundsList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load comparison data. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _invest(FundDetail fund) async {
    final result = await showInvestModal(
      context,
      schemeName: fund.name,
      schemeCode: fund.schemeCode,
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Investment in ${fund.name} recorded successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Compare Mutual Funds')),
        body: LoadingShimmer.list(count: 6, itemHeight: 120),
      );
    }

    if (_error != null || _details.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Compare Mutual Funds')),
        body: AppErrorWidget(
          message: _error ?? 'Please select at least one fund to compare.',
          onRetry: _load,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Compare Funds'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Data',
            onPressed: _load,
          )
        ],
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeadersSummary(),
                      const SizedBox(height: 24),
                      _buildCommonChartSection(),
                      const SizedBox(height: 24),
                      _sectionTitle('Performance comparison'),
                      const SizedBox(height: 12),
                      _buildCompareTable(
                        title: 'Historical Returns (CAGR %)',
                        rows: [
                          _CompareRowData('1M Return', (f) => f.returns1m, isPercentage: true),
                          _CompareRowData('3M Return', (f) => f.returns3m, isPercentage: true),
                          _CompareRowData('6M Return', (f) => f.returns6m, isPercentage: true),
                          _CompareRowData('1Y Return', (f) => f.returns1y, isPercentage: true),
                          _CompareRowData('3Y Return', (f) => f.returns3y, isPercentage: true),
                          _CompareRowData('5Y Return', (f) => f.returns5y, isPercentage: true),
                          _CompareRowData('10Y Return', (f) => f.returns10y, isPercentage: true),
                          _CompareRowData('Since Inception', (f) => f.returnsSinceInception, isPercentage: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildCompareTable(
                        title: 'Risk & Volatility Ratios',
                        rows: [
                          _CompareRowData('Sharpe Ratio', (f) => f.riskMetrics.sharpeRatio, isPercentage: false),
                          _CompareRowData('Sortino Ratio', (f) => f.riskMetrics.sortinoRatio, isPercentage: false),
                          _CompareRowData('Alpha (vs Index)', (f) => f.riskMetrics.alpha, isPercentage: true),
                          _CompareRowData('Beta', (f) => f.riskMetrics.beta, isPercentage: false),
                          _CompareRowData('Annual Volatility', (f) => f.riskMetrics.volatilityAnnualized, isPercentage: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildCompareTable(
                        title: 'Fund Information',
                        rows: [
                          _CompareRowData('ISIN', (f) => f.isin, isString: true),
                          _CompareRowData('Inception Date', (f) => f.inceptionDate, isString: true),
                          _CompareRowData('Scheme Type', (f) => f.schemeType, isString: true),
                          _CompareRowData('Benchmark Used', (f) => f.riskMetrics.benchmarkUsed, isString: true),
                          _CompareRowData('NAV Date', (f) => f.navDate, isString: true),
                        ],
                      ),
                      const SizedBox(height: 32),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildHeadersSummary() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _details.asMap().entries.map((entry) {
          final idx = entry.key;
          final fund = entry.value;
          final color = _fundColors[idx % _fundColors.length];

          return Container(
            width: 170,
            margin: const EdgeInsets.only(right: 12),
            child: GlassCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                      Expanded(
                        child: Text(
                          fund.fundHouse ?? 'Mutual Fund',
                          style: AppTypography.labelSmall.copyWith(color: AppColors.inkMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fund.name,
                    style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${fund.nav?.toStringAsFixed(2) ?? 'N/A'}',
                    style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'NAV (${fund.navDate ?? 'Date N/A'})',
                    style: AppTypography.labelSmall,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCommonChartSection() {
    // Check if any details have chart data
    final hasChart = _details.any((d) => d.navChart.isNotEmpty);
    if (!hasChart) return const SizedBox.shrink();

    // Prepare line chart data by normalizing all points to start at 100
    final List<LineChartBarData> lineBarsData = [];
    double maxDays = 0;
    double maxNormalizedVal = 100;
    double minNormalizedVal = 100;

    for (int idx = 0; idx < _details.length; idx++) {
      final fund = _details[idx];
      final points = fund.navChart;
      if (points.isEmpty) continue;

      final firstNav = points.first.nav;
      if (firstNav <= 0) continue;

      final startDate = points.first.date;
      final spots = points.map((p) {
        final days = p.date.difference(startDate).inDays.toDouble();
        final normalizedVal = (p.nav / firstNav) * 100;

        if (days > maxDays) maxDays = days;
        if (normalizedVal > maxNormalizedVal) maxNormalizedVal = normalizedVal;
        if (normalizedVal < minNormalizedVal) minNormalizedVal = normalizedVal;

        return FlSpot(days, normalizedVal);
      }).toList();

      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: _fundColors[idx % _fundColors.length],
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Growth Comparison (Normalized to ₹100)'),
        const SizedBox(height: 8),
        Text(
          'Compares the growth of ₹100 invested in each fund from the earliest inception date in the 3-year history window.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
          child: SizedBox(
            height: 220,
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
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(
                        '₹${value.toStringAsFixed(0)}',
                        style: AppTypography.labelSmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: maxDays > 0 ? maxDays / 4 : 365,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const Text('Start', style: TextStyle(fontSize: 9));
                        final years = (value / 365).toStringAsFixed(1);
                        return Text('$years Yr', style: const TextStyle(fontSize: 9));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: lineBarsData,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '₹${spot.y.toStringAsFixed(1)}',
                        AppTypography.labelMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompareTable({
    required String title,
    required List<_CompareRowData> rows,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
          const Divider(height: 24, thickness: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 16, thickness: 0.5),
            itemBuilder: (context, idx) {
              final row = rows[idx];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label,
                    style: AppTypography.labelSmall.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _details.asMap().entries.map((entry) {
                      final valIdx = entry.key;
                      final fund = entry.value;
                      final dynamic val = row.extractor(fund);

                      String displayVal = 'N/A';
                      Color valColor = AppColors.ink;
                      FontWeight valWeight = FontWeight.normal;

                      if (val != null) {
                        if (row.isString) {
                          displayVal = val.toString();
                        } else if (val is double || val is num) {
                          final double dVal = val.toDouble();
                          final bool isPos = dVal >= 0;
                          final String plus = (isPos && row.isPercentage) ? '+' : '';
                          final String pct = row.isPercentage ? '%' : '';
                          displayVal = '$plus${dVal.toStringAsFixed(2)}$pct';
                          valWeight = FontWeight.bold;

                          if (row.isPercentage) {
                            valColor = isPos ? AppColors.success : AppColors.error;
                          }
                        }
                      }

                      return Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _fundColors[valIdx % _fundColors.length].withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  displayVal,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: valColor,
                                    fontWeight: valWeight,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _details.asMap().entries.map((entry) {
        final idx = entry.key;
        final fund = entry.value;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ElevatedButton.icon(
              onPressed: () => _invest(fund),
              icon: const Icon(Icons.trending_up_rounded, size: 16, color: Colors.white),
              label: Text(
                'Invest ${idx + 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _fundColors[idx % _fundColors.length],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CompareRowData {
  final String label;
  final dynamic Function(FundDetail) extractor;
  final bool isPercentage;
  final bool isString;

  const _CompareRowData(
    this.label,
    this.extractor, {
    this.isPercentage = false,
    this.isString = false,
  });
}
