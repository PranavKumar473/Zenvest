/// Investment Advisor — Reactive allocation dashboard based on risk profile.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

// State
class AdvisorState {
  final bool hasProfile;
  final String riskLevel;
  final int riskScore;
  final String description;
  final Map<String, double> allocation;
  final Map<String, dynamic> explanations;
  final Map<String, dynamic> schemeSuggestions;  // ADD
  final double monthlyInvestable;                  // ADD
  final bool isLoading;
  final String? error;
  final Map<String, bool> confirmedSchemes;        // ADD — schemeId → confirmed
  final Map<String, double> actualAmounts;         // ADD — schemeId → amount typed
  final List<dynamic> acceptedAdvisors;            // ADD: List of accepted human advisors

  const AdvisorState({
    this.hasProfile = false,
    this.riskLevel = '',
    this.riskScore = 0,
    this.description = '',
    this.allocation = const {},
    this.explanations = const {},
    this.schemeSuggestions = const {},
    this.monthlyInvestable = 0.0,
    this.isLoading = false,
    this.error,
    this.confirmedSchemes = const {},
    this.actualAmounts = const {},
    this.acceptedAdvisors = const [],
  });

  AdvisorState copyWith({
    bool? hasProfile,
    String? riskLevel,
    int? riskScore,
    String? description,
    Map<String, double>? allocation,
    Map<String, dynamic>? explanations,
    Map<String, dynamic>? schemeSuggestions,
    double? monthlyInvestable,
    bool? isLoading,
    String? error,
    Map<String, bool>? confirmedSchemes,
    Map<String, double>? actualAmounts,
    List<dynamic>? acceptedAdvisors,
  }) {
    return AdvisorState(
      hasProfile: hasProfile ?? this.hasProfile,
      riskLevel: riskLevel ?? this.riskLevel,
      riskScore: riskScore ?? this.riskScore,
      description: description ?? this.description,
      allocation: allocation ?? this.allocation,
      explanations: explanations ?? this.explanations,
      schemeSuggestions: schemeSuggestions ?? this.schemeSuggestions,
      monthlyInvestable: monthlyInvestable ?? this.monthlyInvestable,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      confirmedSchemes: confirmedSchemes ?? this.confirmedSchemes,
      actualAmounts: actualAmounts ?? this.actualAmounts,
      acceptedAdvisors: acceptedAdvisors ?? this.acceptedAdvisors,
    );
  }
}

// Controller
class AdvisorController extends StateNotifier<AdvisorState> {
  final Dio _dio;

  AdvisorController(this._dio) : super(const AdvisorState()) {
    loadAdvice();
  }

  Future<void> loadAdvice() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final results = await Future.wait([
        _dio.get(ApiEndpoints.investmentAdvisor),
        _dio.get('/advisor-requests/outgoing'),
      ]);

      final data = results[0].data;
      final List<dynamic> requests = results[1].data;

      // Filter accepted advisors
      final accepted = requests
          .where((r) => r['status'] == 'accepted')
          .map((r) => {
                'id': r['advisor_id'],
                'name': r['advisor_name'],
              })
          .toList();

      if (data['has_profile'] != true) {
        state = AdvisorState(hasProfile: false, acceptedAdvisors: accepted);
        return;
      }

      final rawAllocation = data['recommended_allocation'] as Map<String, dynamic>;
      final allocation = rawAllocation.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );

      state = AdvisorState(
        hasProfile: true,
        riskLevel: data['risk_level'] ?? '',
        riskScore: data['risk_score'] ?? 0,
        description: data['description'] ?? '',
        allocation: allocation,
        explanations: data['asset_explanations'] ?? {},
        schemeSuggestions: data['scheme_suggestions'] ?? {},
        monthlyInvestable: (data['monthly_investable'] as num?)?.toDouble() ?? 0.0,
        acceptedAdvisors: accepted,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to load advisor data', isLoading: false);
    }
  }

  Future<void> confirmInvestment({
    required String assetType,
    required String schemeName,
    required double suggestedAmount,
    required double actualAmount,
    required bool confirmed,
    String? advisorId,
  }) async {
    try {
      await _dio.post(ApiEndpoints.confirmInvestment, data: {
        'asset_type': assetType,
        'scheme_name': schemeName,
        'suggested_amount': suggestedAmount,
        'actual_amount': actualAmount,
        'confirmed': confirmed,
        'advisor_id': advisorId,
      });
      // Mark locally as confirmed
      final key = '${assetType}_$schemeName';
      state = state.copyWith(
        confirmedSchemes: {...state.confirmedSchemes, key: confirmed},
        actualAmounts: {...state.actualAmounts, key: actualAmount},
      );
    } catch (_) {}
  }
}

final advisorControllerProvider =
    StateNotifierProvider<AdvisorController, AdvisorState>((ref) {
  return AdvisorController(ref.read(dioProvider));
});

// Screen
class AdvisorScreen extends ConsumerWidget {
  const AdvisorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(advisorControllerProvider);
    final controller = ref.read(advisorControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Investment Advisor', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_rounded),
            tooltip: 'Talk to Human Advisors',
            onPressed: () => context.push('/advisors'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => controller.loadAdvice(),
          ),
        ],
      ),
      body: _buildBody(context, state, controller, ref),
    );
  }

  Widget _buildBody(BuildContext context, AdvisorState state, AdvisorController controller, WidgetRef ref) {
    if (state.isLoading) return LoadingShimmer.list(count: 4, itemHeight: 140);
    if (state.error != null) {
      return AppErrorWidget(message: state.error!, onRetry: controller.loadAdvice);
    }
    if (!state.hasProfile) return _buildNoProfile();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Risk profile badge
        AnimatedCard(
          delayIndex: 0,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${state.riskScore}',
                    style: AppTypography.moneyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.riskLevel, style: AppTypography.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Risk Profile Score: ${state.riskScore}/100',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Donut chart with rupee amounts
        AnimatedCard(
          delayIndex: 1,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recommended Allocation', style: AppTypography.titleMedium),
              const SizedBox(height: 20),
              SizedBox(
                height: 180,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 50,
                    sections: state.allocation.entries.map((entry) {
                      return PieChartSectionData(
                        value: entry.value,
                        title: '${entry.value.toStringAsFixed(0)}%',
                        color: AppColors.assetColor(entry.key),
                        radius: 40,
                        titleStyle: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Rupee Amount Legend
              Column(
                children: state.allocation.entries.map((entry) {
                  final pct = entry.value;
                  final amount = state.monthlyInvestable * (pct / 100);
                  final name = _assetName(entry.key);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.assetColor(entry.key),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name, style: AppTypography.bodySmall),
                        ),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: AppTypography.labelSmall.copyWith(color: AppColors.inkMuted),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '₹${_formatIndian(amount)}/mo',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.savings_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Monthly investment pool: ₹${_formatWholeIndian(state.monthlyInvestable)}',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Advisor scheme cards
        Text('Why These Assets?', style: AppTypography.titleMedium),
        const SizedBox(height: 8),

        ...state.allocation.entries.toList().asMap().entries.map((mapEntry) {
          final entry = mapEntry.value;
          final idx = mapEntry.key;
          final pct = entry.value;
          final amount = state.monthlyInvestable * (pct / 100);
          final explanation = state.explanations[entry.key];
          final name = explanation?['name'] ?? _assetName(entry.key);
          final why = explanation?['why'] ?? 'Recommended for your risk profile.';

          // Schemes for this asset class
          final assetSug = state.schemeSuggestions[entry.key] ?? {};
          final schemes = List<Map<String, dynamic>>.from(assetSug['schemes'] ?? []);

          return AnimatedCard(
            delayIndex: idx + 2,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.assetColor(entry.key).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _assetIcon(entry.key),
                  color: AppColors.assetColor(entry.key),
                  size: 22,
                ),
              ),
              title: Text(name, style: AppTypography.titleSmall),
              subtitle: Text(
                '${pct.toStringAsFixed(0)}% · ₹${_formatWholeIndian(amount)}/mo',
                style: AppTypography.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _showLearnSheet(context, entry.key, ref),
                    child: Text('Learn', style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                    )),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    why,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.inkLight,
                      height: 1.6,
                    ),
                  ),
                ),
                
                // Scheme recommendations
                if (schemes.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recommended Schemes:',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.inkMuted),
                      ),
                    ),
                  ),
                  ...schemes.map((scheme) {
                    return _SchemeCard(
                      scheme: scheme,
                      assetType: entry.key,
                      acceptedAdvisors: state.acceptedAdvisors,
                      onConfirm: (actualAmount, confirmed, advisorId) =>
                          controller.confirmInvestment(
                            assetType: entry.key,
                            schemeName: scheme['name'] ?? '',
                            suggestedAmount: (scheme['suggested_amount'] as num).toDouble(),
                            actualAmount: actualAmount,
                            confirmed: confirmed,
                            advisorId: advisorId,
                          ),
                    );
                  }),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No specific schemes found for this category.'),
                  )
                ],
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildNoProfile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.quiz_outlined, size: 64, color: AppColors.inkMuted),
            const SizedBox(height: 16),
            Text(
              'Complete your risk assessment to get personalized investment advice.',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.inkLight),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _assetName(String type) {
    const names = {
      'fixed_deposit': 'Fixed Deposits',
      'bonds': 'Bonds',
      'mutual_fund': 'Mutual Funds',
      'stocks': 'Stocks',
      'gold': 'Gold',
    };
    return names[type] ?? type;
  }

  IconData _assetIcon(String type) {
    const icons = {
      'fixed_deposit': Icons.shield_outlined,
      'bonds': Icons.account_balance_outlined,
      'mutual_fund': Icons.pie_chart_outline,
      'stocks': Icons.trending_up,
      'gold': Icons.diamond_outlined,
    };
    return icons[type] ?? Icons.monetization_on_outlined;
  }

  String _formatIndian(double amount) {
    if (amount >= 100000) return '${(amount/100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount/1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  String _formatWholeIndian(double amount) {
    final whole = amount.round();
    final str = whole.toString();
    if (str.length <= 3) return str;
    // Indian grouping: last 3, then groups of 2
    final last3 = str.substring(str.length - 3);
    final rest = str.substring(0, str.length - 3);
    final buf = StringBuffer();
    for (var i = rest.length - 1; i >= 0; i--) {
      buf.write(rest[rest.length - 1 - i]);
      final pos = rest.length - 1 - i;
      if (pos > 0 && (rest.length - 1 - pos) % 2 == 1 && i > 0) {
        buf.write(',');
      }
    }
    // Simpler approach: just use the K/L shorthand
    if (whole >= 100000) return '${(whole / 100000).toStringAsFixed(1)}L';
    if (whole >= 1000) return '${(whole / 1000).toStringAsFixed(1)}K';
    return str;
  }
}

class _SchemeCard extends StatefulWidget {
  final Map<String, dynamic> scheme;
  final String assetType;
  final List<dynamic> acceptedAdvisors;
  final Function(double amount, bool confirmed, String? advisorId) onConfirm;

  const _SchemeCard({
    required this.scheme,
    required this.assetType,
    required this.acceptedAdvisors,
    required this.onConfirm,
  });

  @override
  State<_SchemeCard> createState() => _SchemeCardState();
}

class _SchemeCardState extends State<_SchemeCard> {
  bool _isDone = false;
  bool _showManualInput = false;
  final _amountController = TextEditingController();
  bool _submitted = false;
  String? _selectedAdvisorId;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final suggestedAmount = (scheme['suggested_amount'] as num?)?.toDouble() ?? 0;
    final isDemo = scheme['demo'] == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isDone ? AppColors.successLight : AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDone ? AppColors.success : AppColors.divider,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scheme name + demo badge
          Row(
            children: [
              Expanded(
                child: Text(scheme['name'] ?? '',
                    style: AppTypography.labelLarge),
              ),
              if (isDemo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('DEMO DATA',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.warningDark, fontSize: 9)),
                ),
              if (_isDone)
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
            ],
          ),
          const SizedBox(height: 6),

          // Key metrics row
          _buildMetrics(scheme),

          // Highlight text
          if (scheme['highlight'] != null) ...[
            const SizedBox(height: 6),
            Text(scheme['highlight'],
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkLight, fontStyle: FontStyle.italic)),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Suggested amount + confirmation row
          if (!_submitted) ...[
            if (widget.acceptedAdvisors.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedAdvisorId,
                hint: const Text('Link advisor ARN (optional)', style: TextStyle(fontSize: 12)),
                isExpanded: true,
                items: widget.acceptedAdvisors.map<DropdownMenuItem<String>>((adv) {
                  return DropdownMenuItem<String>(
                    value: adv['id'],
                    child: Text('${adv['name']}', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedAdvisorId = val;
                  });
                },
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Suggested monthly',
                          style: AppTypography.labelSmall),
                      Text('₹${suggestedAmount.toStringAsFixed(0)}',
                          style: AppTypography.moneyMedium.copyWith(
                            color: AppColors.primary, fontSize: 18)),
                    ],
                  ),
                ),
                // DONE button
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _isDone = true; _submitted = true; });
                    widget.onConfirm(suggestedAmount, true, _selectedAdvisorId);
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                // "Different amount" toggle
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _showManualInput = !_showManualInput),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_showManualInput ? 'Cancel' : 'Other ₹',
                      style: AppTypography.labelMedium),
                ),
              ],
            ),

            // Manual amount input
            if (_showManualInput) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        hintText: 'Amount you invested',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final amt = double.tryParse(_amountController.text) ?? 0;
                      if (amt > 0) {
                        setState(() { _isDone = true; _submitted = true; });
                        widget.onConfirm(amt, true, _selectedAdvisorId);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Skip option
              TextButton(
                onPressed: () {
                  setState(() { _submitted = true; });
                  widget.onConfirm(0, false, null);
                },
                child: Text('Skip this scheme for now',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.inkMuted)),
              ),
            ],
          ] else ...[
            // Submitted state
            Row(
              children: [
                Icon(
                  _isDone ? Icons.check_circle : Icons.skip_next,
                  color: _isDone ? AppColors.success : AppColors.inkMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isDone
                      ? 'Added ₹${_amountController.text.isEmpty ? suggestedAmount.toStringAsFixed(0) : _amountController.text} to portfolio'
                      : 'Skipped — not added to portfolio',
                  style: AppTypography.labelSmall.copyWith(
                    color: _isDone ? AppColors.success : AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics(Map<String, dynamic> scheme) {
    final type = scheme['type'] ?? '';
    final chips = <String>[];

    if (type == 'mf') {
      if (scheme['returns_3yr'] != null) chips.add('3Y: ${scheme["returns_3yr"]}');
      if (scheme['sharpe_ratio'] != null) chips.add('Sharpe: ${scheme["sharpe_ratio"]}');
      if (scheme['expense_ratio'] != null) chips.add('Expense: ${scheme["expense_ratio"]}');
      if (scheme['min_sip'] != null) chips.add('Min SIP: ₹${scheme["min_sip"]}');
    } else if (type == 'fd') {
      if (scheme['interest_rate'] != null) chips.add(scheme['interest_rate']);
      if (scheme['tenure'] != null) chips.add(scheme['tenure']);
      if (scheme['min_amount'] != null) chips.add('Min: ₹${scheme["min_amount"]}');
    } else if (type == 'bond') {
      if (scheme['interest_rate'] != null) chips.add(scheme['interest_rate']);
      if (scheme['tenure'] != null) chips.add(scheme['tenure']);
    } else if (type == 'stock') {
      if (scheme['current_price'] != null) chips.add('LTP: ${scheme["current_price"]}');
      if (scheme['pe_ratio'] != null) chips.add('PE: ${scheme["pe_ratio"]}');
      if (scheme['market_cap'] != null) chips.add('MCap: ${scheme["market_cap"]}');
    } else if (type == 'sgb') {
      if (scheme['interest_rate'] != null) chips.add(scheme['interest_rate']);
      if (scheme['tenure'] != null) chips.add(scheme['tenure']);
    } else if (type == 'etf') {
      if (scheme['returns_3yr'] != null) chips.add('3Y: ${scheme["returns_3yr"]}');
      if (scheme['expense_ratio'] != null) chips.add('Expense: ${scheme["expense_ratio"]}');
      if (scheme['ticker'] != null) chips.add('NSE: ${scheme["ticker"]}');
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips.map((c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(c, style: AppTypography.labelSmall),
      )).toList(),
    );
  }
}

// Bottom sheet education
void _showLearnSheet(BuildContext context, String assetType, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => _LearnSheet(
        assetType: assetType,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

class _LearnSheet extends StatelessWidget {
  final String assetType;
  final ScrollController scrollController;

  const _LearnSheet({
    required this.assetType,
    required this.scrollController,
  });

  static const Map<String, List<Map<String, dynamic>>> EDUCATION_DATA = {
    'mutual_fund': [
      {
        'name': 'What is a Mutual Fund?',
        'body': 'A mutual fund pools money from many investors to buy a diversified basket of stocks, bonds, or both. A professional fund manager makes the investment decisions. You buy "units" of the fund — each unit represents your share of the pool.',
        'key_facts': ['Regulated by SEBI', 'Start with ₹500/month SIP', 'Returns: 10–20% CAGR for equity funds', 'Taxed as capital gains (10% LTCG above ₹1L)'],
        'risk': 'Medium–High',
      },
      {
        'name': 'Sharpe Ratio — What It Tells You',
        'body': 'The Sharpe Ratio measures how much return a fund earns per unit of risk taken. Higher is better. A Sharpe of >1.0 is good. A fund returning 18% with high volatility may have a worse Sharpe than one returning 14% steadily.',
        'key_facts': ['Sharpe > 1.0 = Good', 'Sharpe > 1.5 = Excellent', 'Compare within same category only', 'Cannot compare MF Sharpe with FD yield'],
        'risk': null,
      },
      {
        'name': 'Expense Ratio — The Silent Cost',
        'body': 'The expense ratio is the annual fee the fund house charges to manage your money, deducted automatically from returns. Direct plans have lower expense ratios than regular plans. Even 0.5% difference compounds significantly over 10 years.',
        'key_facts': ['Direct plan: 0.3–0.8% typical', 'Regular plan: 1.0–2.0% typical', 'Always choose Direct plan when investing online', 'Lower is better — everything else equal'],
        'risk': null,
      },
      {
        'name': 'Beta — How Much Does It Move?',
        'body': 'Beta measures how much a fund moves relative to its benchmark index. Beta of 1.0 means it moves exactly with the market. Beta > 1 means it amplifies market moves (higher risk, higher reward). Beta < 1 means it is more stable than the market.',
        'key_facts': ['Beta < 0.8: Low volatility', 'Beta 0.8–1.2: Market-like', 'Beta > 1.2: Amplified moves', 'Check beta in same market cycle'],
        'risk': null,
      },
    ],
    'fixed_deposit': [
      {
        'name': 'Fixed Deposits Explained',
        'body': 'An FD locks your money with a bank for a fixed period at a predetermined interest rate. The interest is guaranteed regardless of market conditions. Best used for money you definitely cannot afford to lose.',
        'key_facts': ['DICGC insured up to ₹5 lakh per bank', 'Premature withdrawal: 0.5–1% penalty', 'TDS deducted if interest > ₹40,000/year', 'Senior citizens get 0.25–0.50% extra'],
        'risk': 'Low',
      },
      {
        'name': 'FD vs Debt Mutual Fund — Which Wins?',
        'body': 'FDs offer certainty but are fully taxable. Debt mutual funds may offer similar returns with better post-tax efficiency (indexation benefit removed from 2023 but still more liquid). FDs are better for short terms; debt MFs for 3+ years.',
        'key_facts': ['FD interest: Taxed as income (slab rate)', 'Debt MF LTCG (3+ yrs): 20% with indexation (pre-2023)', 'FDs: guaranteed, no NAV risk', 'Debt MFs: subject to credit risk'],
        'risk': null,
      },
    ],
    'bonds': [
      {
        'name': 'How Government Bonds Work',
        'body': 'When the government needs money, it issues bonds. You lend it money at a fixed rate for a set period. The government pays you interest (coupon) semi-annually and returns the principal at maturity. G-Secs carry zero default risk.',
        'key_facts': ['Coupon rate: Fixed at issuance', 'Price fluctuates on secondary market', 'Yield and price move inversely', 'RBI Retail Direct: Buy G-Secs directly'],
        'risk': 'Low',
      },
      {
        'name': 'Bharat Bond ETF — Safest Bond Option',
        'body': 'Bharat Bond ETF is a basket of AAA-rated PSU bonds traded on stock exchanges. It offers bond-like safety with stock-like liquidity. Target maturity means you hold until the ETF winds up and get your money back at a predictable yield.',
        'key_facts': ['Only AAA PSU bonds inside', 'Listed on exchange for easy exit', 'Matures in a specific year (e.g. 2030)', 'Tax-efficient compared to bank FDs'],
        'risk': 'Low–Medium',
      },
    ],
    'stocks': [
      {
        'name': 'Direct Stocks — True Equity Ownership',
        'body': 'Buying a stock makes you a part-owner of the company. You participate directly in their profits (via dividends) and growth (via share price appreciation). It offers the highest long-term returns but requires tolerance for market drops.',
        'key_facts': ['Requires Demat account to buy', 'Returns: 12–15% CAGR (long-term average)', 'Volatility can exceed 30% in a year', 'Dividends are taxed at slab rates'],
        'risk': 'High',
      },
      {
        'name': 'P/E Ratio — Valuation Tool',
        'body': 'The Price-to-Earnings (P/E) ratio shows how much investors are willing to pay for each rupee of company earnings. A P/E of 25 means you pay ₹25 for ₹1 of earnings. A high P/E indicates high growth expectations or overvaluation.',
        'key_facts': ['P/E = Stock Price / Earnings Per Share', 'Compare within same sector only', 'High P/E: Growth stock (expensive)', 'Low P/E: Value stock (cheap)'],
        'risk': null,
      },
    ],
    'gold': [
      {
        'name': 'Sovereign Gold Bonds (SGBs) — Gold Sweet Spot',
        'body': 'SGBs are government securities denominated in grams of gold. They are the safest way to buy digital gold because the RBI pays you a 2.5% annual interest on your initial investment, and capital gains are tax-free if held to maturity.',
        'key_facts': ['Tax-free capital gains on maturity', '2.5% interest paid semi-annually', '8-year tenure, early exit after 5', 'Sovereign guarantee by Government of India'],
        'risk': 'Medium (Gold price risk)',
      },
      {
        'name': 'Gold BeES (ETFs) vs Physical Gold',
        'body': 'Gold ETFs are mutual fund units that track domestic gold prices. One unit usually represents 1 gram or 0.01 gram of gold. They are highly liquid, have no storage costs or making charges, and can be bought instantly on NSE.',
        'key_facts': ['No making charges or locker fees', 'Buy/sell instantly like stocks', 'Tracks actual physical gold prices', 'Highly liquid with minimal tracking error'],
        'risk': 'Medium',
      },
    ],
  };

  @override
  Widget build(BuildContext context) {
    final title = _assetClassName(assetType);
    final topics = EDUCATION_DATA[assetType] ?? [];

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Learn: $title', style: AppTypography.titleLarge),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: topics.length,
              itemBuilder: (ctx, idx) {
                final topic = topics[idx];
                final risk = topic['risk'];
                final facts = List<String>.from(topic['key_facts'] ?? []);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                topic['name'] ?? '',
                                style: AppTypography.labelLarge,
                              ),
                            ),
                            if (risk != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.amber.shade200),
                                ),
                                child: Text(
                                  'Risk: $risk',
                                  style: AppTypography.labelSmall.copyWith(color: Colors.amber.shade900),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          topic['body'] ?? '',
                          style: AppTypography.bodyMedium.copyWith(color: AppColors.inkLight, height: 1.5),
                        ),
                        if (facts.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          ...facts.map((fact) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                Expanded(
                                  child: Text(
                                    fact,
                                    style: AppTypography.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _assetClassName(String type) {
    const names = {
      'fixed_deposit': 'Fixed Deposits',
      'bonds': 'Bonds',
      'mutual_fund': 'Mutual Funds',
      'stocks': 'Stocks',
      'gold': 'Gold',
    };
    return names[type] ?? type;
  }
}
