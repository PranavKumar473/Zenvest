/// Top-5 recommended schemes — ranked by a real, computed composite of
/// past returns + risk-adjusted metrics (Alpha, Sharpe, Sortino). Backed by
/// GET /mutual-funds/top5 (see mutual_fund_service.get_top5_recommendations).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/animated_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/glass_card.dart';
import '../domain/mutual_fund.dart';
import 'fund_compare_controller.dart';

class Top5Screen extends ConsumerStatefulWidget {
  const Top5Screen({super.key});

  @override
  ConsumerState<Top5Screen> createState() => _Top5ScreenState();
}

class _Top5ScreenState extends ConsumerState<Top5Screen> {
  List<TopFund> _funds = [];
  bool _isLoading = true;
  String? _error;
  String? _rankingBasis;
  String? _riskLevel;

  static const _riskLevels = ['Conservative', 'Moderate', 'Aggressive', 'Very Aggressive'];

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
      final response = await dio.get(
        ApiEndpoints.fundTop5,
        queryParameters: _riskLevel != null ? {'risk_level': _riskLevel} : null,
      );
      final funds = (response.data['funds'] as List).map((f) => TopFund.fromJson(f as Map<String, dynamic>)).toList();
      if (mounted) {
        setState(() {
          _funds = funds;
          _rankingBasis = funds.isNotEmpty ? funds.first.rankingBasis : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load recommendations. Complete your risk assessment or pick a risk level below.';
          _isLoading = false;
        });
      }
    }
  }

  String _getFundName(int code) {
    for (final fund in _funds) {
      if (fund.schemeCode == code) {
        return fund.name;
      }
    }
    return 'Unknown Fund';
  }

  @override
  Widget build(BuildContext context) {
    final compareList = ref.watch(fundCompareProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Top 5 Recommended')),
      body: Stack(
        children: [
          Column(
            children: [
              _buildRiskLevelSelector(),
              Expanded(
                child: _isLoading
                    ? LoadingShimmer.list(count: 5, itemHeight: 120)
                    : _error != null
                        ? AppErrorWidget(message: _error!, onRetry: _load)
                        : _funds.isEmpty
                            ? Center(child: Text('No recommendations available.', style: AppTypography.bodyMedium))
                            : _buildList(),
              ),
            ],
          ),
          if (compareList.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildFloatingCompareBar(compareList),
            ),
        ],
      ),
    );
  }

  Widget _buildRiskLevelSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _Chip(label: 'My Profile', selected: _riskLevel == null, onTap: () {
              setState(() => _riskLevel = null);
              _load();
            }),
            for (final level in _riskLevels) ...[
              const SizedBox(width: 8),
              _Chip(label: level, selected: _riskLevel == level, onTap: () {
                setState(() => _riskLevel = level);
                _load();
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final hasCompare = ref.watch(fundCompareProvider).isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, hasCompare ? 110 : 24),
        children: [
          if (_rankingBasis != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _rankingBasis!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
              ),
            ),
          for (int i = 0; i < _funds.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedCard(
                delayIndex: i,
                onTap: () => context.push('/funds/${_funds[i].schemeCode}'),
                child: _TopFundCard(rank: i + 1, fund: _funds[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingCompareBar(List<int> compareList) {
    final canCompare = compareList.length >= 2;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${compareList.length} ${compareList.length == 1 ? 'Fund' : 'Funds'} Selected',
                  style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: compareList.map((code) {
                      final name = _getFundName(code);
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.canvas,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 80),
                              child: Text(
                                name,
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => ref.read(fundCompareProvider.notifier).remove(code),
                              child: const Icon(Icons.close_rounded, size: 12, color: AppColors.inkMuted),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => ref.read(fundCompareProvider.notifier).clear(),
            child: const Text('Clear', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: canCompare
                ? () {
                    context.push('/funds/compare?codes=${compareList.join(',')}');
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.divider,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Compare',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primarySurface,
      labelStyle: AppTypography.labelMedium.copyWith(
        color: selected ? AppColors.primary : AppColors.inkLight,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
      backgroundColor: AppColors.surface,
    );
  }
}

class _TopFundCard extends ConsumerWidget {
  final int rank;
  final TopFund fund;

  const _TopFundCard({required this.rank, required this.fund});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compareList = ref.watch(fundCompareProvider);
    final isSelected = compareList.contains(fund.schemeCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                onChanged: (val) {
                  if (val == true && compareList.length >= 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You can compare a maximum of 3 funds side-by-side.'),
                        backgroundColor: AppColors.error,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  ref.read(fundCompareProvider.notifier).toggle(fund.schemeCode);
                },
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$rank', style: AppTypography.labelLarge.copyWith(color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fund.name, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (fund.category != null) Text(fund.category!, style: AppTypography.bodySmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fund.compositeScore.toStringAsFixed(0), style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
                Text('score', style: AppTypography.labelSmall),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (fund.returns3y != null) _MetricChip('3Y Return', '${fund.returns3y!.toStringAsFixed(1)}%'),
            if (fund.returns3y == null && fund.returns1y != null) _MetricChip('1Y Return', '${fund.returns1y!.toStringAsFixed(1)}%'),
            if (fund.sharpeRatio != null) _MetricChip('Sharpe', fund.sharpeRatio!.toStringAsFixed(2)),
            if (fund.sortinoRatio != null) _MetricChip('Sortino', fund.sortinoRatio!.toStringAsFixed(2)),
            if (fund.alpha != null) _MetricChip('Alpha', '${fund.alpha!.toStringAsFixed(1)}%'),
            if (fund.beta != null) _MetricChip('Beta', fund.beta!.toStringAsFixed(2)),
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: AppTypography.labelSmall),
            TextSpan(text: value, style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}
