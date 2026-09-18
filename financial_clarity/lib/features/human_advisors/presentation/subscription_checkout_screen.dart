/// Monthly consultation-fee subscription checkout.
/// Backend creates a Razorpay Plan+Subscription (or a mock one in local
/// dev without Razorpay keys configured) and this screen drives the
/// razorpay_flutter native checkout with the returned subscription_id.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/subscription.dart';

class SubscriptionCheckoutScreen extends ConsumerStatefulWidget {
  final String advisorId;

  const SubscriptionCheckoutScreen({super.key, required this.advisorId});

  @override
  ConsumerState<SubscriptionCheckoutScreen> createState() => _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState extends ConsumerState<SubscriptionCheckoutScreen> {
  late final Razorpay _razorpay;
  SubscriptionCheckout? _checkout;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _startCheckout();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _startCheckout() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(ApiEndpoints.subscriptionCheckout, data: {
        'advisor_id': widget.advisorId,
      });
      final checkout = SubscriptionCheckout.fromJson(response.data);

      if (mounted) {
        setState(() {
          _checkout = checkout;
          _isLoading = false;
        });
      }

      if (checkout.provider == 'razorpay') {
        _openRazorpayCheckout(checkout);
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data?['detail']?.toString() ?? 'Could not start checkout.';
          _isLoading = false;
        });
      }
    }
  }

  void _openRazorpayCheckout(SubscriptionCheckout checkout) {
    _razorpay.open({
      'key': checkout.checkoutKey,
      'subscription_id': checkout.providerSubscriptionId,
      'name': 'Financial Clarity',
      'description': 'Monthly consultation — ${checkout.advisorName}',
      'theme': {'color': '#1A5C3A'},
    });
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (_checkout == null) return;
    setState(() => _isProcessing = true);

    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.verifySubscriptionPayment, data: {
        'subscription_id': _checkout!.subscriptionId,
        'razorpay_payment_id': response.paymentId,
        'razorpay_subscription_id': response.orderId ?? _checkout!.providerSubscriptionId,
        'razorpay_signature': response.signature,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription activated!'), backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data?['detail']?.toString() ?? 'Payment succeeded but verification failed.';
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _error = response.message ?? 'Payment was not completed.');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // No-op: informational callback when the user selects a non-Razorpay wallet.
  }

  /// Local-dev path: no Razorpay keys are configured on the backend, so the
  /// checkout is a mock subscription — simulate a successful charge instead
  /// of opening a native payment sheet.
  Future<void> _confirmMockCheckout() async {
    if (_checkout == null) return;
    setState(() => _isProcessing = true);

    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.verifySubscriptionPayment, data: {
        'subscription_id': _checkout!.subscriptionId,
        'razorpay_payment_id': 'mock_payment_${DateTime.now().millisecondsSinceEpoch}',
        'razorpay_subscription_id': _checkout!.providerSubscriptionId,
        'razorpay_signature': 'mock_signature',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mock subscription activated!'), backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data?['detail']?.toString() ?? 'Could not confirm the mock subscription.';
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Consultation Subscription')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_checkout != null) _buildSummaryCard(_checkout!),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(8)),
                      child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
                    ),
                  ],
                  const Spacer(),
                  if (_checkout?.provider == 'mock')
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _confirmMockCheckout,
                      child: _isProcessing
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Simulate Successful Charge (dev mode)'),
                    )
                  else
                    OutlinedButton(
                      onPressed: _checkout == null ? null : () => _openRazorpayCheckout(_checkout!),
                      child: const Text('Reopen Checkout'),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(SubscriptionCheckout checkout) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly Consultation', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          Text('with ${checkout.advisorName}', style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: 16),
          Text(
            '₹${checkout.amountMonthly.toStringAsFixed(0)} / month',
            style: AppTypography.displayMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(
            'Billed automatically every month via ${checkout.provider == 'razorpay' ? 'Razorpay' : 'mock billing (dev)'} until cancelled.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
