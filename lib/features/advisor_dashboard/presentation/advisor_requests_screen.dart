import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/animated_card.dart';

class AdvisorRequestsScreen extends ConsumerStatefulWidget {
  const AdvisorRequestsScreen({super.key});

  @override
  ConsumerState<AdvisorRequestsScreen> createState() => _AdvisorRequestsScreenState();
}

class _AdvisorRequestsScreenState extends ConsumerState<AdvisorRequestsScreen> {
  List<dynamic> _requests = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/advisor-requests/incoming');
      if (mounted) {
        setState(() {
          _requests = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load client requests.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _respondToRequest(String requestId, String status, String note) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/advisor-requests/$requestId/respond', data: {
        'status': status,
        'response_note': note,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request ${status == 'accepted' ? 'Accepted' : 'Rejected'} successfully!'),
            backgroundColor: status == 'accepted' ? AppColors.success : AppColors.error,
          ),
        );
        _fetchRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit response. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showRespondDialog(String requestId, String investorName, String status) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('${status == 'accepted' ? 'Accept' : 'Reject'} Request from $investorName'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Add an optional note to the investor...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: status == 'accepted' ? AppColors.success : AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                _respondToRequest(requestId, status, noteController.text.trim());
              },
              child: Text(status == 'accepted' ? 'Accept' : 'Reject'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Client Requests', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchRequests,
          ),
        ],
      ),
      body: _isLoading
          ? LoadingShimmer.list(count: 3, itemHeight: 180)
          : _error != null
              ? AppErrorWidget(message: _error!, onRetry: _fetchRequests)
              : _requests.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final req = _requests[index];
                        return _buildRequestCard(req);
                      },
                    ),
    );
  }

  Widget _buildRequestCard(dynamic req) {
    final status = req['status'] as String;
    final riskProfile = req['investor_risk_profile'] as Map?;
    final riskLevel = riskProfile?['level'] ?? 'Not Assessed';
    final riskScore = riskProfile?['score'] ?? 0;

    Color statusColor = Colors.grey;
    if (status == 'accepted') statusColor = AppColors.success;
    if (status == 'rejected') statusColor = AppColors.error;
    if (status == 'pending') statusColor = AppColors.primary;

    return AnimatedCard(
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        color: AppColors.surface,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    req['investor_name'] ?? 'Investor',
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: AppTypography.bodySmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Risk Profile summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Riskometer: $riskLevel ($riskScore/100)',
                      style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (req['message'] != null && req['message'].toString().trim().isNotEmpty) ...[
                Text(
                  'Message:',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  req['message'],
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              if (status == 'pending') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                      onPressed: () => _showRespondDialog(req['id'], req['investor_name'] ?? 'Investor', 'rejected'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accept'),
                      onPressed: () => _showRespondDialog(req['id'], req['investor_name'] ?? 'Investor', 'accepted'),
                    ),
                  ],
                ),
              ] else if (status == 'accepted') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: const Text('Open Chat'),
                      onPressed: () => context.push('/chat/${req['id']}', extra: {
                        'name': req['investor_name'],
                        'request_id': req['id'],
                      }),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mail_outline_rounded, size: 64, color: AppColors.inkMuted),
          const SizedBox(height: 16),
          Text('No client requests yet', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Incoming requests from investors will appear here.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
