import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

class InvestorPortfolioDetailScreen extends ConsumerStatefulWidget {
  final String investorId;
  final String investorName;

  const InvestorPortfolioDetailScreen({
    super.key,
    required this.investorId,
    required this.investorName,
  });

  @override
  ConsumerState<InvestorPortfolioDetailScreen> createState() => _InvestorPortfolioDetailScreenState();
}

class _InvestorPortfolioDetailScreenState extends ConsumerState<InvestorPortfolioDetailScreen> {
  List<dynamic> _holdings = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHoldings();
  }

  Future<void> _fetchHoldings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/arn-linkage/my-investors/${widget.investorId}/portfolio');
      if (mounted) {
        setState(() {
          _holdings = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load portfolio details.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final totalPortfolioValue = _holdings.fold(0.0, (double sum, dynamic p) => sum + (p['current_value'] ?? 0.0));
    final totalInvestedValue = _holdings.fold(0.0, (double sum, dynamic p) => sum + (p['initial_investment'] ?? 0.0));
    final profit = totalPortfolioValue - totalInvestedValue;
    final profitPct = totalInvestedValue > 0 ? (profit / totalInvestedValue) * 100 : 0.0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('${widget.investorName}\'s Portfolio', style: AppTypography.titleLarge),
      ),
      body: _isLoading
          ? LoadingShimmer.list(count: 3, itemHeight: 120)
          : _error != null
              ? AppErrorWidget(message: _error!, onRetry: _fetchHoldings)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Net Worth Summary
                      _buildNetWorthSummary(currencyFormatter, totalPortfolioValue, totalInvestedValue, profit, profitPct),
                      const SizedBox(height: 24),
                      Text('Holdings Breakdown', style: AppTypography.titleMedium),
                      const SizedBox(height: 12),
                      _holdings.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _holdings.length,
                              itemBuilder: (context, index) {
                                final holding = _holdings[index];
                                return _buildHoldingCard(holding, currencyFormatter);
                              },
                            ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildNetWorthSummary(NumberFormat formatter, double current, double invested, double profit, double profitPct) {
    final isProfit = profit >= 0;
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Net Value', style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            Text(
              formatter.format(current),
              style: AppTypography.titleLarge.copyWith(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invested Amount', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                    const SizedBox(height: 2),
                    Text(formatter.format(invested), style: AppTypography.labelLarge),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Total Returns', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                    const SizedBox(height: 2),
                    Text(
                      '${isProfit ? '+' : ''}${formatter.format(profit)} (${profitPct.toStringAsFixed(1)}%)',
                      style: AppTypography.labelLarge.copyWith(
                        color: isProfit ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldingCard(dynamic p, NumberFormat formatter) {
    final invested = p['initial_investment'] ?? 0.0;
    final current = p['current_value'] ?? 0.0;
    final diff = current - invested;
    final isProfit = diff >= 0;
    final mode = (p['investment_mode'] ?? 'lumpsum').toString().toUpperCase();

    return AnimatedCard(
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      p['asset_name'] ?? 'Asset',
                      style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mode,
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 9,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CURRENT VALUE', style: TextStyle(fontSize: 10, color: AppColors.inkMuted)),
                      const SizedBox(height: 2),
                      Text(formatter.format(current), style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('RETURNS', style: TextStyle(fontSize: 10, color: AppColors.inkMuted)),
                      const SizedBox(height: 2),
                      Text(
                        '${isProfit ? '+' : ''}${formatter.format(diff)}',
                        style: AppTypography.labelLarge.copyWith(
                          color: isProfit ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Column(
          children: [
            const Icon(Icons.folder_open_rounded, size: 48, color: AppColors.inkMuted),
            const SizedBox(height: 12),
            Text('No active holdings', style: AppTypography.bodyLarge),
            const SizedBox(height: 4),
            Text(
              'No investment confirmation records mapped with your ARN.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
