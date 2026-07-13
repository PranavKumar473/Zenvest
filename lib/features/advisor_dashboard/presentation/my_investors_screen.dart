import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

class MyInvestorsScreen extends ConsumerStatefulWidget {
  const MyInvestorsScreen({super.key});

  @override
  ConsumerState<MyInvestorsScreen> createState() => _MyInvestorsScreenState();
}

class _MyInvestorsScreenState extends ConsumerState<MyInvestorsScreen> {
  List<dynamic> _investors = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchInvestors();
  }

  Future<void> _fetchInvestors() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/arn-linkage/my-investors');
      if (mounted) {
        setState(() {
          _investors = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load linked investors.';
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
        title: Text('My Investors', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchInvestors,
          ),
        ],
      ),
      body: _isLoading
          ? LoadingShimmer.list(count: 3, itemHeight: 140)
          : _error != null
              ? AppErrorWidget(message: _error!, onRetry: _fetchInvestors)
              : _investors.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _investors.length,
                      itemBuilder: (context, index) {
                        final inv = _investors[index];
                        final totalValue = inv['total_invested_value'] ?? 0.0;
                        final count = inv['active_investments_count'] ?? 0;

                        return AnimatedCard(
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: AppColors.divider),
                            ),
                            color: AppColors.surface,
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => context.push('/my-investors/${inv['investor_id']}/portfolio', extra: {
                                'name': inv['investor_name'],
                              }),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: AppColors.primary.withOpacity(0.1),
                                      child: Text(
                                        (inv['investor_name'] ?? 'I')[0].toUpperCase(),
                                        style: AppTypography.titleMedium.copyWith(color: AppColors.primary),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            inv['investor_name'] ?? 'Investor',
                                            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            inv['investor_email'] ?? '',
                                            style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '$count active investments',
                                            style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          currencyFormatter.format(totalValue),
                                          style: AppTypography.titleMedium.copyWith(
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Linked AUM',
                                          style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline_rounded, size: 64, color: AppColors.inkMuted),
          const SizedBox(height: 16),
          Text('No linked investors yet', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          Text(
            'When investors use your ARN to make investments, they will show up here.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
