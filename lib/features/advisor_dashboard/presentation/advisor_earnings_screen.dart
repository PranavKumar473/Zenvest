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

class AdvisorEarningsScreen extends ConsumerStatefulWidget {
  const AdvisorEarningsScreen({super.key});

  @override
  ConsumerState<AdvisorEarningsScreen> createState() => _AdvisorEarningsScreenState();
}

class _AdvisorEarningsScreenState extends ConsumerState<AdvisorEarningsScreen> {
  Map<String, dynamic>? _earningsData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchEarnings();
  }

  Future<void> _fetchEarnings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      // For MVP we mock or call user profile to compute consultation fee earnings
      final profileRes = await dio.get('/users/me');
      final investorsRes = await dio.get('/arn-linkage/my-investors');
      
      final fee = profileRes.data['consultation_fee_monthly'] ?? 2000.0;
      final investorCount = (investorsRes.data as List).length;
      final totalAum = (investorsRes.data as List).fold(0.0, (double sum, dynamic item) => sum + (item['total_invested_value'] ?? 0.0));

      if (mounted) {
        setState(() {
          _earningsData = {
            'monthly_consultation_fee': fee,
            'active_investor_count': investorCount,
            'total_aum': totalAum,
            'monthly_revenue': fee * investorCount,
            'projected_annual_revenue': fee * investorCount * 12,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load earnings metrics.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Earnings Overview', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchEarnings,
          ),
        ],
      ),
      body: _isLoading
          ? LoadingShimmer.list(count: 3, itemHeight: 120)
          : _error != null
              ? AppErrorWidget(message: _error!, onRetry: _fetchEarnings)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Revenue Card
                      _buildRevenueCard(currencyFormatter),
                      const SizedBox(height: 24),
                      Text('Business Metrics', style: AppTypography.titleMedium),
                      const SizedBox(height: 12),
                      _buildMetricsGrid(currencyFormatter),
                      const SizedBox(height: 24),
                      Text('Revenue Projections', style: AppTypography.titleMedium),
                      const SizedBox(height: 12),
                      _buildProjectionsCard(currencyFormatter),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRevenueCard(NumberFormat formatter) {
    final monthlyRev = _earningsData?['monthly_revenue'] ?? 0.0;
    return AnimatedCard(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF1E3C72)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ESTIMATED MONTHLY REVENUE',
              style: AppTypography.labelMedium.copyWith(color: Colors.white70, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              formatter.format(monthlyRev),
              style: AppTypography.titleLarge.copyWith(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildRevenueStat('Consultation Fee', formatter.format(_earningsData?['monthly_consultation_fee'] ?? 0.0)),
                _buildRevenueStat('Active Clients', '${_earningsData?['active_investor_count'] ?? 0} investors'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMetricsGrid(NumberFormat formatter) {
    final totalAum = _earningsData?['total_aum'] ?? 0.0;
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricTile(Icons.store_rounded, 'Linked AUM', formatter.format(totalAum), 'Total Assets managed'),
        _buildMetricTile(Icons.people_alt_rounded, 'Total Clients', '${_earningsData?['active_investor_count'] ?? 0}', 'Active linked clients'),
      ],
    );
  }

  Widget _buildMetricTile(IconData icon, String label, String value, String description) {
    return Card(
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 12),
            Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            Text(value, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(fontSize: 10, color: AppColors.inkMuted.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectionsCard(NumberFormat formatter) {
    final annualRev = _earningsData?['projected_annual_revenue'] ?? 0.0;
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Projected Annual Revenue', style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text('Estimated next 12 months based on active count', style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted)),
              ],
            ),
            Text(
              formatter.format(annualRev),
              style: AppTypography.titleMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
