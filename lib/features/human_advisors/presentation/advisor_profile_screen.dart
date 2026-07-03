import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

class AdvisorProfileScreen extends ConsumerStatefulWidget {
  final String advisorId;

  const AdvisorProfileScreen({super.key, required this.advisorId});

  @override
  ConsumerState<AdvisorProfileScreen> createState() => _AdvisorProfileScreenState();
}

class _AdvisorProfileScreenState extends ConsumerState<AdvisorProfileScreen> {
  dynamic _advisor;
  bool _isLoading = true;
  bool _isActionLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAdvisorDetails();
  }

  Future<void> _fetchAdvisorDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(ApiEndpoints.advisorById(widget.advisorId));
      if (mounted) {
        setState(() {
          _advisor = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load advisor details.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initiateDemoCall() async {
    setState(() {
      _isActionLoading = true;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(ApiEndpoints.advisorDemoCall(widget.advisorId));
      if (mounted) {
        final data = response.data;
        context.push(
          '/advisors/${widget.advisorId}/call',
          extra: {
            'name': _advisor['name'],
            'session_id': data['session_id'],
            'masked_number': data['masked_number'],
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to establish a secure call session. Try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Advisor Profile')),
        body: LoadingShimmer.list(count: 4, itemHeight: 120),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Advisor Profile')),
        body: AppErrorWidget(message: _error!, onRetry: _fetchAdvisorDetails),
      );
    }

    final List<dynamic> specs = _advisor['specializations'] ?? [];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          // ── Ambient Background Blur (Glassmorphism support) ──
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            top: 250,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withOpacity(0.05),
              ),
            ),
          ),
          
          CustomScrollView(
            slivers: [
              // Custom glassmorphic app bar
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.canvas.withOpacity(0.8),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    _advisor['name'] ?? 'Advisor Profile',
                    style: AppTypography.titleLarge.copyWith(color: AppColors.ink),
                  ),
                  centerTitle: false,
                ),
              ),
              
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 24),
                      _buildAboutSection(),
                      const SizedBox(height: 24),
                      _buildSpecializationsSection(specs),
                      const SizedBox(height: 24),
                      _buildCredentialsSection(),
                      const SizedBox(height: 100), // Action button offset
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Action Buttons Bar
          _buildActionButtonsBar(),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return AnimatedCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: AppColors.surface.withOpacity(0.7),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    (_advisor['name'] ?? 'A')[0],
                    style: AppTypography.titleLarge.copyWith(color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _advisor['name'] ?? 'Advisor',
                              style: AppTypography.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_advisor['arn_verified'] == true)
                            const Icon(Icons.verified_rounded, color: AppColors.success, size: 22),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _advisor['arn_number'] ?? 'ARN-XXXXXX',
                        style: AppTypography.bodyMedium.copyWith(
                          fontFamily: 'JetBrains Mono',
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildHeaderStat(Icons.star_rounded, _advisor['rating']?.toString() ?? '5.0', 'Rating'),
                          const SizedBox(width: 24),
                          _buildHeaderStat(Icons.work_outline_rounded, '${_advisor['experience_years']} yrs', 'Exp'),
                          const SizedBox(width: 24),
                          _buildHeaderStat(Icons.payments_outlined, _advisor['charges']?.split(' ')[0] ?? 'Fees', 'Rate'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStat(IconData icon, String val, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: icon == Icons.star_rounded ? Colors.amber : AppColors.inkMuted, size: 16),
            const SizedBox(width: 4),
            Text(val, style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.bodySmall.copyWith(fontSize: 10, color: AppColors.inkMuted)),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('About Advisor', style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        Text(
          _advisor['bio'] ?? '',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildSpecializationsSection(List<dynamic> specs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Areas of Expertise', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: specs.map<Widget>((s) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                s.toString(),
                style: AppTypography.labelMedium.copyWith(color: AppColors.ink),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCredentialsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Regulatory Information', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppColors.surface,
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              _buildCredentialRow('Organization', 'AMFI Registered'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('ARN Status', _advisor['arn_verified'] == true ? 'Active / Verified' : 'Pending Verification'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('Registration Number', _advisor['arn_number'] ?? 'ARN-XXXXXX'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted)),
        Text(val, style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildActionButtonsBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.canvas.withOpacity(0.85),
          border: const Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: const BorderSide(color: AppColors.divider),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.ink),
                    label: Text('Chat', style: AppTypography.labelLarge.copyWith(color: AppColors.ink)),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Chat feature coming soon! Try starting a secure Demo Call.'),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _isActionLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.canvas,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.phone_in_talk_rounded),
                          label: Text('Demo Call', style: AppTypography.labelLarge.copyWith(color: AppColors.canvas)),
                          onPressed: _initiateDemoCall,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
