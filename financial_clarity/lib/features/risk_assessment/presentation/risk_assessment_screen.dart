/// Risk Assessment — 10-question behavioral engine with animated cards.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class RiskAssessmentScreen extends ConsumerStatefulWidget {
  const RiskAssessmentScreen({super.key});

  @override
  ConsumerState<RiskAssessmentScreen> createState() => _RiskAssessmentScreenState();
}

class _RiskAssessmentScreenState extends ConsumerState<RiskAssessmentScreen> {
  final _pageController = PageController();
  int _currentQuestion = 0;
  final List<int> _answers = List.filled(10, -1);
  bool _isSubmitting = false;
  Map<String, dynamic>? _result;

  // Questions (matching backend)
  static const _questions = [
    {'q': 'If your investment dropped 20% in a week, what would you do?', 'opts': ['Sell everything immediately', 'Sell some to reduce risk', 'Hold and wait for recovery', 'Buy more at a lower price']},
    {'q': 'How long can you keep your money invested?', 'opts': ['Less than 1 year', '1 to 3 years', '3 to 7 years', 'More than 7 years']},
    {'q': 'What is your primary financial goal?', 'opts': ['Preserving my capital', 'Steady income with some growth', 'Growing my wealth over time', 'Maximizing returns, high risk ok']},
    {'q': 'How do you react to market volatility news?', 'opts': ['Very anxious', 'Concerned but calm', 'Part of the cycle', 'I see opportunities']},
    {'q': 'What % of monthly income can you invest?', 'opts': ['Less than 10%', '10% to 20%', '20% to 40%', 'More than 40%']},
    {'q': 'Describe your investment experience:', 'opts': ['No experience', 'FDs and savings schemes', 'Mutual funds and bonds', 'Active stock trading']},
    {'q': 'For ₹1L investment, which scenario appeals most?', 'opts': ['Guaranteed ₹1.06L', '50/50: ₹1.12L or ₹1.02L', '50/50: ₹1.25L or ₹95K', '50/50: ₹1.50L or ₹80K']},
    {'q': 'How many months of emergency savings do you have?', 'opts': ['Less than 1 month', '1 to 3 months', '3 to 6 months', 'More than 6 months']},
    {'q': 'A friend recommends a high-risk, high-reward investment:', 'opts': ['Politely decline', 'Research, invest small', 'Moderate amount after research', 'Invest significantly']},
    {'q': 'Your current financial obligations:', 'opts': ['Heavy EMIs, dependents', 'Moderate EMIs, some dependents', 'Minimal obligations', 'No debt, strong savings']},
  ];

  void _selectAnswer(int optionIndex) {
    setState(() {
      _answers[_currentQuestion] = optionIndex;
    });

    // Auto-advance after short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_currentQuestion < 9) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        setState(() => _currentQuestion++);
      }
    });
  }

  Future<void> _submitAssessment() async {
    setState(() => _isSubmitting = true);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        ApiEndpoints.riskAssessment,
        data: {'answers': _answers},
      );

      setState(() {
        _result = response.data;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit assessment.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _buildResultScreen();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Question ${_currentQuestion + 1} of 10'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${((_currentQuestion + 1) / 10 * 100).toInt()}%',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_currentQuestion + 1) / 10,
                minHeight: 4,
              ),
            ),
          ),

          // Questions
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 10,
              itemBuilder: (context, index) {
                final q = _questions[index];
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        q['q'] as String,
                        style: AppTypography.titleLarge,
                      ),
                      const SizedBox(height: 32),
                      ...(q['opts'] as List<String>).asMap().entries.map(
                        (entry) => _buildOptionCard(
                          text: entry.value,
                          selected: _answers[index] == entry.key,
                          onTap: () => _selectAnswer(entry.key),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Submit button (visible on last question)
          if (_currentQuestion == 9 && _answers[9] >= 0)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitAssessment,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('See My Risk Profile'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required String text,
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
          title: Text(text, style: AppTypography.bodyLarge),
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

  Widget _buildResultScreen() {
    final level = _result!['level'] ?? 'Moderate';
    final score = _result!['score'] ?? 50;
    final description = _result!['description'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Animated gauge
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.primarySurface, AppColors.canvas],
                  ),
                  border: Border.all(color: AppColors.primary, width: 4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$score', style: AppTypography.moneyLarge.copyWith(
                      color: AppColors.primary,
                    )),
                    Text('/ 100', style: AppTypography.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(level, style: AppTypography.displayMedium),
              const SizedBox(height: 12),
              Text(
                description,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.inkLight,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('Start Exploring'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
