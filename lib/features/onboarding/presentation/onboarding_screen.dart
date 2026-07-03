/// Conversational Onboarding — Multi-step stepper.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  // Form data
  String? _selectedAgeGroup;
  String? _selectedIncomeBracket;

  final _ageGroups = ['18-25', '26-35', '36-45', '46-60', '60+'];
  final _incomeBrackets = ['0-5L', '5-10L', '10-25L', '25-50L', '50L+'];

  void _nextStep() {
    if (_currentStep < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      _submitOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    }
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _selectedAgeGroup != null;
      case 1:
        return _selectedIncomeBracket != null;
      default:
        return false;
    }
  }

  Future<void> _submitOnboarding() async {
    setState(() => _isSubmitting = true);

    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.onboarding, data: {
        'age_group': _selectedAgeGroup,
        'income_bracket': _selectedIncomeBracket,
        'goals': [],
      });

      if (mounted) context.go('/risk-assessment');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _previousStep,
              )
            : null,
        title: Text('Step ${_currentStep + 1} of 2'),
      ),
      body: Column(
        children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_currentStep + 1) / 2,
                minHeight: 4,
                backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAgeStep(),
                _buildIncomeStep(),
              ],
            ),
          ),

          // Next button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_canProceed && !_isSubmitting) ? _nextStep : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.inkOnPrimary,
                        ),
                      )
                    : Text(_currentStep == 1 ? 'Complete' : 'Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How old are you?', style: AppTypography.displayMedium),
          const SizedBox(height: 8),
          Text(
            'This helps us tailor investment advice to your life stage.',
            style: AppTypography.bodyLarge.copyWith(color: AppColors.inkLight),
          ),
          const SizedBox(height: 32),
          ...(_ageGroups.map((age) => _buildOptionTile(
                title: age,
                subtitle: _ageDescription(age),
                selected: _selectedAgeGroup == age,
                onTap: () => setState(() => _selectedAgeGroup = age),
              ))),
        ],
      ),
    );
  }

  Widget _buildIncomeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Annual income range?', style: AppTypography.displayMedium),
          const SizedBox(height: 8),
          Text(
            'We keep this private. It helps calibrate savings and investment targets.',
            style: AppTypography.bodyLarge.copyWith(color: AppColors.inkLight),
          ),
          const SizedBox(height: 32),
          ...(_incomeBrackets.map((bracket) => _buildOptionTile(
                title: '₹$bracket',
                subtitle: _incomeDescription(bracket),
                selected: _selectedIncomeBracket == bracket,
                onTap: () => setState(() => _selectedIncomeBracket = bracket),
              ))),
        ],
      ),
    );
  }



  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: ListTile(
          title: Text(title, style: AppTypography.titleMedium),
          subtitle: Text(subtitle, style: AppTypography.bodySmall),
          trailing: selected
              ? const Icon(Icons.check_circle, color: AppColors.primary)
              : const Icon(Icons.circle_outlined, color: AppColors.inkMuted),
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  String _ageDescription(String age) {
    switch (age) {
      case '18-25': return 'Early career, high growth potential';
      case '26-35': return 'Building career and assets';
      case '36-45': return 'Peak earnings, family planning';
      case '46-60': return 'Pre-retirement wealth consolidation';
      case '60+': return 'Retirement and income focus';
      default: return '';
    }
  }

  String _incomeDescription(String bracket) {
    switch (bracket) {
      case '0-5L': return 'Starting out — every rupee counts';
      case '5-10L': return 'Building a strong savings habit';
      case '10-25L': return 'Growing wealth and investments';
      case '25-50L': return 'Diversifying across asset classes';
      case '50L+': return 'Optimizing for tax and legacy';
      default: return '';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
