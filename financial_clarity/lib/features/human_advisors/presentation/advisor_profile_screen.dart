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
import '../domain/advisor.dart';

class AdvisorProfileScreen extends ConsumerStatefulWidget {
  final String advisorId;

  const AdvisorProfileScreen({super.key, required this.advisorId});

  @override
  ConsumerState<AdvisorProfileScreen> createState() => _AdvisorProfileScreenState();
}

class _AdvisorProfileScreenState extends ConsumerState<AdvisorProfileScreen> {
  Advisor? _advisor;
  bool _isLoading = true;
  bool _isActionLoading = false;
  String? _error;
  String? _requestStatus; // null | 'pending' | 'accepted' | 'rejected'
  String? _requestId;

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
      final results = await Future.wait([
        dio.get(ApiEndpoints.advisorById(widget.advisorId)),
        dio.get('/advisor-requests/outgoing'),
      ]);

      final advisorData = Advisor.fromJson(results[0].data as Map<String, dynamic>);
      final List<dynamic> requests = results[1].data;

      // Find request for this advisor
      final req = requests.firstWhere(
        (r) => r['advisor_id'] == widget.advisorId,
        orElse: () => null,
      );

      if (mounted) {
        setState(() {
          _advisor = advisorData;
          if (req != null) {
            _requestStatus = req['status'];
            _requestId = req['id'];
          } else {
            _requestStatus = null;
            _requestId = null;
          }
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
            'name': _advisor!.name,
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

    final advisor = _advisor!;
    final specs = advisor.specializations;

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
                    advisor.name,
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
                      _buildVerifiedProfileSection(),
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
    final advisor = _advisor!;
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
                  backgroundImage: advisor.profileImageUrl != null
                      ? NetworkImage(advisor.profileImageUrl!)
                      : null,
                  child: advisor.profileImageUrl == null
                      ? Text(
                          advisor.name.isNotEmpty ? advisor.name[0] : 'A',
                          style: AppTypography.titleLarge.copyWith(color: AppColors.primary),
                        )
                      : null,
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
                              advisor.name,
                              style: AppTypography.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (advisor.arnVerified)
                            const Icon(Icons.verified_rounded, color: AppColors.success, size: 22),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        advisor.arnNumber ?? 'ARN-XXXXXX',
                        style: AppTypography.bodyMedium.copyWith(
                          fontFamily: 'JetBrains Mono',
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildHeaderStat(Icons.star_rounded, advisor.rating.toStringAsFixed(1), 'Rating'),
                          const SizedBox(width: 24),
                          _buildHeaderStat(Icons.work_outline_rounded, '${advisor.experienceYears ?? '—'} yrs', 'Exp'),
                          const SizedBox(width: 24),
                          _buildHeaderStat(Icons.payments_outlined, advisor.charges?.split(' ')[0] ?? 'Fees', 'Rate'),
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
    final advisor = _advisor!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('About Advisor', style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        Text(
          advisor.bio ?? '',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildSpecializationsSection(List<String> specs) {
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
                s,
                style: AppTypography.labelMedium.copyWith(color: AppColors.ink),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Full verified profile — Name, Photo, Email, Phone, PAN, Address — per
  /// SEBI disclosure requirements. Phone/PAN arrive pre-masked from the API.
  Widget _buildVerifiedProfileSection() {
    final advisor = _advisor!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verified Profile', style: AppTypography.titleMedium),
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
              _buildCredentialRow('Email', advisor.email),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('Phone', advisor.phoneNumberMasked ?? 'Not on file'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('PAN', advisor.panMasked ?? 'Not on file'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('Address', advisor.address?.displayLine.isNotEmpty == true
                  ? advisor.address!.displayLine
                  : 'Not on file'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialsSection() {
    final advisor = _advisor!;
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
              _buildCredentialRow('ARN (Mutual Fund Execution)', advisor.arnNumber ?? 'ARN-XXXXXX'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('ARN Status', advisor.arnVerified ? 'Active / Verified' : 'Pending Verification'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('INA (Fee-Only Advice)', advisor.hasIna ? advisor.inaNumber! : 'Not registered'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('GST', advisor.gstNumber ?? 'Not registered'),
              const Divider(color: AppColors.divider, height: 24),
              _buildCredentialRow('GST Status', _gstStatusLabel(advisor.gstVerificationStatus)),
            ],
          ),
        ),
        if (advisor.hasConsultationFee) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: AppColors.primary),
              ),
              icon: const Icon(Icons.subscriptions_outlined, color: AppColors.primary),
              label: Text(
                'Subscribe · ${advisor.charges}',
                style: AppTypography.labelLarge.copyWith(color: AppColors.primary),
              ),
              onPressed: () => context.push('/advisors/${widget.advisorId}/subscribe'),
            ),
          ),
        ],
      ],
    );
  }

  String _gstStatusLabel(GstVerificationStatus status) {
    switch (status) {
      case GstVerificationStatus.verified:
        return 'Verified';
      case GstVerificationStatus.failed:
        return 'Verification Failed';
      case GstVerificationStatus.pending:
        return 'Pending';
      case GstVerificationStatus.unverified:
        return 'Not Verified';
    }
  }

  Widget _buildCredentialRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted)),
        Flexible(
          child: Text(
            val,
            style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _sendAdvisorRequest() async {
    setState(() {
      _isActionLoading = true;
    });

    try {
      final dio = ref.read(dioProvider);
      await dio.post('/advisor-requests', data: {
        'advisor_id': widget.advisorId,
        'message': 'Hello, I would like to consult with you regarding my investment planning.',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request sent successfully! Waiting for advisor response.'),
            backgroundColor: AppColors.success,
          ),
        );
        _fetchAdvisorDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send request. Try again.'),
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
            child: _isActionLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _buildActionContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildActionContent() {
    if (_requestStatus == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          icon: const Icon(Icons.person_add_rounded),
          label: Text('Request Advisor', style: AppTypography.labelLarge.copyWith(color: Colors.white)),
          onPressed: _sendAdvisorRequest,
        ),
      );
    }

    if (_requestStatus == 'pending') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          icon: const Icon(Icons.hourglass_empty_rounded),
          label: Text('Request Pending 🔄', style: AppTypography.labelLarge.copyWith(color: Colors.white)),
          onPressed: null, // Disabled
        ),
      );
    }

    if (_requestStatus == 'rejected') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          icon: const Icon(Icons.block_rounded),
          label: Text('Request Declined ❌', style: AppTypography.labelLarge.copyWith(color: Colors.white)),
          onPressed: null, // Disabled
        ),
      );
    }

    // Default: 'accepted'
    return Row(
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
              context.push('/chat/$_requestId', extra: {
                'name': _advisor!.name,
              });
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.canvas,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            icon: const Icon(Icons.phone_in_talk_rounded),
            label: Text('Secure Call', style: AppTypography.labelLarge.copyWith(color: AppColors.canvas)),
            onPressed: _initiateDemoCall,
          ),
        ),
      ],
    );
  }
}
