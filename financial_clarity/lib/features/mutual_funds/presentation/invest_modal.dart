/// Universal "Invest" modal — the single entry point for executing an
/// investment from anywhere in the app (fund directory, top-5
/// recommendations, fund detail). Captures the investment amount and asks
/// "Who guided your investment?" (Robo-Advisor vs Human Advisor), then
/// posts to POST /invest. The platform's corporate ARN is applied
/// server-side and never appears in this UI — see
/// backend/app/services/investment_service.py.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/mutual_fund.dart';

/// Shows the invest modal. Returns true if the investment was recorded.
Future<bool?> showInvestModal(
  BuildContext context, {
  required String schemeName,
  required int schemeCode,
  String assetType = 'mutual_fund',
  double suggestedAmount = 0,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InvestModal(
      schemeName: schemeName,
      schemeCode: schemeCode,
      assetType: assetType,
      suggestedAmount: suggestedAmount,
    ),
  );
}

class _InvestModal extends ConsumerStatefulWidget {
  final String schemeName;
  final int schemeCode;
  final String assetType;
  final double suggestedAmount;

  const _InvestModal({
    required this.schemeName,
    required this.schemeCode,
    required this.assetType,
    required this.suggestedAmount,
  });

  @override
  ConsumerState<_InvestModal> createState() => _InvestModalState();
}

class _InvestModalState extends ConsumerState<_InvestModal> {
  final _amountController = TextEditingController();
  final _advisorNameController = TextEditingController();
  final _euinController = TextEditingController();
  String _source = 'robo'; // 'robo' | 'human'
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedAmount > 0) {
      _amountController.text = widget.suggestedAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _advisorNameController.dispose();
    _euinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid investment amount.');
      return;
    }
    if (_source == 'human') {
      if (_advisorNameController.text.trim().isEmpty || _euinController.text.trim().isEmpty) {
        setState(() => _error = "Enter the advisor's name and EUIN.");
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final guidance = InvestmentGuidance(
        source: _source,
        advisorName: _source == 'human' ? _advisorNameController.text.trim() : null,
        advisorEuin: _source == 'human' ? _euinController.text.trim() : null,
      );
      await dio.post(ApiEndpoints.invest, data: {
        'asset_type': widget.assetType,
        'scheme_name': widget.schemeName,
        'scheme_code': widget.schemeCode,
        'suggested_amount': widget.suggestedAmount,
        'actual_amount': amount,
        'investment_mode': 'sip',
        'guidance': guidance.toJson(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? (e.response!.data['detail']?.toString()) : null;
      setState(() => _error = detail ?? 'Could not record this investment. Try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text('Invest', style: AppTypography.titleLarge),
              const SizedBox(height: 4),
              Text(
                widget.schemeName,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),

              Text('Amount', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '5000',
                  filled: true,
                  fillColor: AppColors.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text('Who guided your investment?', style: AppTypography.labelLarge),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _GuidanceOption(
                      label: 'Robo-Advisor',
                      icon: Icons.auto_awesome_rounded,
                      selected: _source == 'robo',
                      onTap: () => setState(() => _source = 'robo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GuidanceOption(
                      label: 'Human Advisor',
                      icon: Icons.support_agent_rounded,
                      selected: _source == 'human',
                      onTap: () => setState(() => _source = 'human'),
                    ),
                  ),
                ],
              ),

              if (_source == 'human') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _advisorNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: "Advisor's Full Name",
                    filled: true,
                    fillColor: AppColors.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _euinController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Advisor EUIN',
                    hintText: 'E123456',
                    filled: true,
                    fillColor: AppColors.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirm Investment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidanceOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GuidanceOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.primary : AppColors.inkMuted, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? AppColors.primary : AppColors.inkLight,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
