/// Mutual Fund Detail — real NAV history, computed returns, and yearly
/// performance for a single fund. All figures come from AMFI-linked NAV
/// data (see backend/app/services/mutual_fund_service.py); expense ratio,
/// AUM, fund manager, and portfolio holdings are intentionally omitted
/// rather than fabricated — they require a licensed data feed this app
/// doesn't have.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';
import '../domain/mutual_fund.dart';

class FundDetailScreen extends ConsumerStatefulWidget {
  final int schemeCode;

  const FundDetailScreen({super.key, required this.schemeCode});

  @override
  ConsumerState<FundDetailScreen> createState() => _FundDetailScreenState();
}

class _FundDetailScreenState extends ConsumerState<FundDetailScreen> {
  MutualFundDetail? _fund;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response =
          await dio.get(ApiEndpoints.mutualFundDetail(widget.schemeCode));
      if (mounted) {
        setState(() {
          _fund =
              MutualFundDetail.fromJson(response.data as Map<String, dynamic>);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Failed to load fund data. It may be temporarily unavailable.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Fund Details')),
      body: _isLoading
          ? LoadingShimmer.list(count: 4, itemHeight: 120)
          : _error != null
              ? AppErrorWidget(message: _error!, onRetry: _fetch)
              : _fund == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(_fund!),
                            const SizedBox(height: 20),
                            _buildReturnsGrid(_fund!),
                            const SizedBox(height: 20),
                            if (_fund!.navChart.isNotEmpty) ...[
                              _buildNavChart(_fund!),
                              const SizedBox(height: 20),
                            ],
                            if (_fund!.yearlyReturns.isNotEmpty) ...[
                              _buildYearlyReturnsChart(_fund!),
                              const SizedBox(height: 20),
                            ],
                            _buildMetaCard(_fund!),
                            const SizedBox(height: 16),
                            _buildDataSourceNote(_fund!),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildHeader(MutualFundDetail fund) {
    return AnimatedCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fund.name, style: AppTypography.titleLarge),
            const SizedBox(height: 4),
            if (fund.fundHouse != null)
              Text(fund.fundHouse!,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.inkMuted)),
            if (fund.category != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(fund.category!,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.primary)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${fund.nav?.toStringAsFixed(2) ?? '—'}',
                    style: AppTypography.moneyLarge),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    fund.navDate != null
                        ? 'NAV as of ${DateFormat.yMMMd().format(fund.navDate!)}'
                        : 'Current NAV',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnsGrid(MutualFundDetail fund) {
    final entries = <MapEntry<String, double?>>[
      MapEntry('1M', fund.returns1m),
      MapEntry('3M', fund.returns3m),
      MapEntry('6M', fund.returns6m),
      MapEntry('1Y', fund.returns1y),
      MapEntry('3Y CAGR', fund.returns3y),
      MapEntry('5Y CAGR', fund.returns5y),
    ].where((e) => e.value != null).toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Returns', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.6,
          children:
              entries.map((e) => _buildReturnTile(e.key, e.value!)).toList(),
        ),
      ],
    );
  }

  Widget _buildReturnTile(String label, double value) {
    final positive = value >= 0;
    final color = positive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style:
                  AppTypography.labelSmall.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: 4),
          Text(
            '${positive ? '+' : ''}${value.toStringAsFixed(1)}%',
            style: AppTypography.titleSmall
                .copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildNavChart(MutualFundDetail fund) {
    final points = fund.navChart;
    final minNav = points.map((p) => p.nav).reduce((a, b) => a < b ? a : b);
    final maxNav = points.map((p) => p.nav).reduce((a, b) => a > b ? a : b);
    final padding = (maxNav - minNav) * 0.1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NAV History (${points.length > 1 ? '~3Y' : ''})',
            style: AppTypography.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Actual daily NAV from the AMFI-linked registry — this is the real price history, not a projection.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 12),
        Container(
          height: 220,
          padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: LineChart(
            LineChartData(
              minY: minNav - padding,
              maxY: maxNav + padding,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    final point = points[s.x.toInt()];
                    return LineTooltipItem(
                      '₹${point.nav.toStringAsFixed(2)}\n${DateFormat.yMMMd().format(point.date)}',
                      AppTypography.labelSmall.copyWith(color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (int i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].nav),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: AppColors.primary,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.primary.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildYearlyReturnsChart(MutualFundDetail fund) {
    final years = fund.yearlyReturns;
    final maxAbs =
        years.map((y) => y.returnPct.abs()).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Calendar Year Returns', style: AppTypography.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Year-by-year performance — a better trust signal than a single headline CAGR.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 12),
        Container(
          height: 200,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: BarChart(
            BarChartData(
              maxY: maxAbs * 1.2,
              minY: -maxAbs * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= years.length)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${years[idx].year}',
                            style: AppTypography.labelSmall),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final y = years[group.x.toInt()];
                    return BarTooltipItem(
                      '${y.year}: ${y.returnPct >= 0 ? '+' : ''}${y.returnPct.toStringAsFixed(1)}%',
                      AppTypography.labelSmall.copyWith(color: Colors.white),
                    );
                  },
                ),
              ),
              barGroups: [
                for (int i = 0; i < years.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: years[i].returnPct,
                        color: years[i].returnPct >= 0
                            ? AppColors.success
                            : AppColors.error,
                        width: 22,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaCard(MutualFundDetail fund) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fund Information', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              _buildMetaRow('Fund House', fund.fundHouse ?? '—'),
              const Divider(color: AppColors.divider, height: 24),
              _buildMetaRow('Scheme Type', fund.schemeType ?? '—'),
              const Divider(color: AppColors.divider, height: 24),
              _buildMetaRow('ISIN', fund.isin ?? '—'),
              const Divider(color: AppColors.divider, height: 24),
              _buildMetaRow(
                'Inception',
                fund.inceptionDate != null
                    ? DateFormat.yMMMd().format(fund.inceptionDate!)
                    : '—',
              ),
              if (fund.returnsSinceInception != null) ...[
                const Divider(color: AppColors.divider, height: 24),
                _buildMetaRow(
                  'Since Inception',
                  '${fund.returnsSinceInception! >= 0 ? '+' : ''}${fund.returnsSinceInception!.toStringAsFixed(1)}%',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style:
                AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDataSourceNote(MutualFundDetail fund) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.warningDark, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All figures above are real, computed from ${fund.dataSource ?? 'the AMFI-linked NAV registry'}. '
              'Expense ratio, AUM, fund manager, and portfolio holdings aren\'t shown — they require a licensed '
              'data feed this app doesn\'t have, and we\'d rather omit them than show inaccurate numbers. '
              'Past returns don\'t guarantee future performance.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.warningDark, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
