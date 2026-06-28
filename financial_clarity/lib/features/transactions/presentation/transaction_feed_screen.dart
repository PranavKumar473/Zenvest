/// Transaction Feed — Lazy-loaded, categorized transaction list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';

// Transaction state
class TransactionState {
  final List<Map<String, dynamic>> transactions;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;
  final String? categoryFilter;

  const TransactionState({
    this.transactions = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
    this.categoryFilter,
  });

  TransactionState copyWith({
    List<Map<String, dynamic>>? transactions,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
    String? categoryFilter,
  }) {
    return TransactionState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
      categoryFilter: categoryFilter ?? this.categoryFilter,
    );
  }
}

// Controller
class TransactionController extends StateNotifier<TransactionState> {
  final Dio _dio;

  TransactionController(this._dio) : super(const TransactionState()) {
    loadTransactions();
  }

  Future<void> loadTransactions({bool refresh = false}) async {
    if (state.isLoading) return;

    final page = refresh ? 1 : state.currentPage;
    state = state.copyWith(isLoading: true, error: null);

    try {
      String url = '${ApiEndpoints.transactions}?page=$page&page_size=20';
      if (state.categoryFilter != null) {
        url += '&category=${state.categoryFilter}';
      }

      final response = await _dio.get(url);
      final data = response.data;
      final newTxns = List<Map<String, dynamic>>.from(data['transactions']);

      state = state.copyWith(
        transactions: refresh ? newTxns : [...state.transactions, ...newTxns],
        isLoading: false,
        hasMore: data['has_next'] ?? false,
        currentPage: page + 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load transactions',
      );
    }
  }

  void setFilter(String? category) {
    state = TransactionState(categoryFilter: category);
    loadTransactions(refresh: true);
  }

  Future<void> refresh() => loadTransactions(refresh: true);
}

final transactionControllerProvider =
    StateNotifierProvider<TransactionController, TransactionState>((ref) {
  return TransactionController(ref.read(dioProvider));
});

// Screen
class TransactionFeedScreen extends ConsumerWidget {
  const TransactionFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transactionControllerProvider);
    final controller = ref.read(transactionControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Transactions', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilterSheet(context, controller, state.categoryFilter),
          ),
        ],
      ),
      body: Column(
        children: [
          // Category chips
          if (state.categoryFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Chip(
                label: Text(
                  AppConstants.categoryNames[state.categoryFilter] ?? state.categoryFilter!,
                ),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => controller.setFilter(null),
                backgroundColor: AppColors.primarySurface,
              ),
            ),

          // Transaction list
          Expanded(
            child: _buildBody(state, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(TransactionState state, TransactionController controller) {
    if (state.error != null && state.transactions.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: controller.refresh,
      );
    }

    if (state.isLoading && state.transactions.isEmpty) {
      return LoadingShimmer.list(count: 8);
    }

    if (state.transactions.isEmpty) {
      return const Center(
        child: Text('No transactions yet.'),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      color: AppColors.primary,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scroll) {
          if (scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 200 &&
              state.hasMore && !state.isLoading) {
            controller.loadTransactions();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: state.transactions.length + (state.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= state.transactions.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final txn = state.transactions[index];
            return _TransactionTile(transaction: txn, index: index);
          },
        ),
      ),
    );
  }

  void _showFilterSheet(
    BuildContext context,
    TransactionController controller,
    String? current,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter by Category', style: AppTypography.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: current == null,
                  onSelected: (_) {
                    controller.setFilter(null);
                    Navigator.pop(ctx);
                  },
                ),
                ...AppConstants.categoryNames.entries.map((e) => ChoiceChip(
                      label: Text('${AppConstants.categoryIcons[e.key] ?? ''} ${e.value}'),
                      selected: current == e.key,
                      onSelected: (_) {
                        controller.setFilter(e.key);
                        Navigator.pop(ctx);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final int index;

  const _TransactionTile({required this.transaction, required this.index});

  @override
  Widget build(BuildContext context) {
    final category = transaction['category'] ?? 'other';
    final icon = AppConstants.categoryIcons[category] ?? '💳';
    final vendor = transaction['vendor'] ?? '';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final timestamp = transaction['timestamp'] != null
        ? DateTime.tryParse(transaction['timestamp'])
        : null;
    final isDebit = transaction['is_debit'] ?? true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),

            // Vendor & category
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vendor, style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  )),
                  const SizedBox(height: 2),
                  Text(
                    '${AppConstants.categoryNames[category] ?? category}'
                    '${timestamp != null ? '  •  ${DateFormat.MMMd().format(timestamp)}' : ''}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),

            // Amount
            Text(
              '${isDebit ? '-' : '+'}₹${amount.toStringAsFixed(0)}',
              style: AppTypography.moneyMedium.copyWith(
                color: isDebit ? AppColors.error : AppColors.success,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
