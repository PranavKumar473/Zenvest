/// Categorized directory of every mutual fund on the platform — Equity
/// (Large/Mid/Small/Flexi Cap, ELSS), Hybrid, Debt — backed by
/// GET /mutual-funds/directory (real, live-computed NAV + returns).
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

class FundDirectoryScreen extends ConsumerStatefulWidget {
  const FundDirectoryScreen({super.key});

  @override
  ConsumerState<FundDirectoryScreen> createState() => _FundDirectoryScreenState();
}

class _FundDirectoryScreenState extends ConsumerState<FundDirectoryScreen> {
  List<FundCategory> _categories = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCategory;
  String _search = '';

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
      final response = await dio.get(ApiEndpoints.fundDirectory);
      final categories = (response.data['categories'] as List)
          .map((c) => FundCategory.fromJson(c as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load the fund directory.';
          _isLoading = false;
        });
      }
    }
  }

  String _getFundName(int code) {
    for (final cat in _categories) {
      for (final fund in cat.funds) {
        if (fund.schemeCode == code) {
          return fund.name;
        }
      }
    }
    return 'Unknown Fund';
  }

  @override
  Widget build(BuildContext context) {
    final compareList = ref.watch(fundCompareProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Fund Directory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_rounded),
            tooltip: 'Top 5 Recommended',
            onPressed: () => context.push('/funds/top5'),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? LoadingShimmer.list(count: 6, itemHeight: 90)
              : _error != null
                  ? AppErrorWidget(message: _error!, onRetry: _load)
                  : _buildContent(),
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

  Widget _buildContent() {
    final visibleCategories = _selectedCategory == null
        ? _categories
        : _categories.where((c) => c.category == _selectedCategory).toList();

    final hasCompare = ref.watch(fundCompareProvider).isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildSearchAndFilters()),
          if (visibleCategories.every((c) => _filteredFunds(c).isEmpty))
            SliverFillRemaining(
              child: Center(
                child: Text('No funds match your search.', style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted)),
              ),
            )
          else
            ...visibleCategories.map((cat) => _buildCategorySection(cat)),
          SliverToBoxAdapter(
            child: SizedBox(height: hasCompare ? 110 : 24),
          ),
        ],
      ),
    );
  }

  List<FundSummary> _filteredFunds(FundCategory category) {
    if (_search.isEmpty) return category.funds;
    final q = _search.toLowerCase();
    return category.funds.where((f) => f.name.toLowerCase().contains(q) || (f.fundHouse ?? '').toLowerCase().contains(q)).toList();
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search funds or fund houses',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                for (final cat in _categories) ...[
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: cat.category,
                    selected: _selectedCategory == cat.category,
                    onTap: () => setState(() => _selectedCategory = cat.category),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCategorySection(FundCategory category) {
    final funds = _filteredFunds(category);
    if (funds.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(category.category, style: AppTypography.titleMedium),
          ),
        ),
        SliverList.builder(
          itemCount: funds.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: AnimatedCard(
              delayIndex: i,
              onTap: () => context.push('/funds/${funds[i].schemeCode}'),
              child: _FundRow(fund: funds[i]),
            ),
          ),
        ),
      ],
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

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

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

class _FundRow extends ConsumerWidget {
  final FundSummary fund;

  const _FundRow({required this.fund});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compareList = ref.watch(fundCompareProvider);
    final isSelected = compareList.contains(fund.schemeCode);

    final ret3y = fund.returns3y;
    final positive = (ret3y ?? 0) >= 0;

    return Row(
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fund.name,
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (fund.fundHouse != null) ...[
                const SizedBox(height: 2),
                Text(fund.fundHouse!, style: AppTypography.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (fund.nav != null)
              Text('₹${fund.nav!.toStringAsFixed(2)}', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            if (ret3y != null)
              Text(
                '${positive ? '+' : ''}${ret3y.toStringAsFixed(1)}% 3Y',
                style: AppTypography.labelMedium.copyWith(
                  color: positive ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              Text('3Y N/A', style: AppTypography.labelSmall),
          ],
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
      ],
    );
  }
}
