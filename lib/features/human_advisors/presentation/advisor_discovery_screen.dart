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

class AdvisorDiscoveryScreen extends ConsumerStatefulWidget {
  const AdvisorDiscoveryScreen({super.key});

  @override
  ConsumerState<AdvisorDiscoveryScreen> createState() => _AdvisorDiscoveryScreenState();
}

class _AdvisorDiscoveryScreenState extends ConsumerState<AdvisorDiscoveryScreen> {
  List<dynamic> _advisors = [];
  List<dynamic> _filteredAdvisors = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String? _selectedSpecialization;

  final List<String> _specializations = [
    'All',
    'Mutual Funds',
    'Wealth Growth',
    'Tax Planning',
    'Bonds & Fixed Income',
    'Retirement Planning',
    'Stocks & Equities',
  ];

  @override
  void initState() {
    super.initState();
    _fetchAdvisors();
  }

  Future<void> _fetchAdvisors() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(ApiEndpoints.advisors);
      if (mounted) {
        setState(() {
          _advisors = response.data;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load advisors. Make sure backend is running.';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredAdvisors = _advisors.where((advisor) {
        final nameMatches = advisor['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        final bioMatches = advisor['bio'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        bool specMatches = true;
        if (_selectedSpecialization != null && _selectedSpecialization != 'All') {
          final List<dynamic> specs = advisor['specializations'] ?? [];
          specMatches = specs.any((s) => s.toString().toLowerCase() == _selectedSpecialization!.toLowerCase());
        }

        return (nameMatches || bioMatches) && specMatches;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Expert Advisors', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchAdvisors,
          ),
        ],
      ),
      body: _isLoading
          ? LoadingShimmer.list(count: 3, itemHeight: 160)
          : _error != null
              ? AppErrorWidget(message: _error!, onRetry: _fetchAdvisors)
              : Column(
                  children: [
                    _buildSearchBar(),
                    _buildFilterChips(),
                    Expanded(
                      child: _filteredAdvisors.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredAdvisors.length,
                              itemBuilder: (context, index) {
                                final advisor = _filteredAdvisors[index];
                                return _buildAdvisorCard(advisor);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      key: const ValueKey('advisor_search_bar'),
      child: TextField(
        onChanged: (val) {
          _searchQuery = val;
          _applyFilters();
        },
        decoration: InputDecoration(
          hintText: 'Search advisors, skills, or bios...',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkMuted),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: _specializations.length,
        itemBuilder: (context, index) {
          final spec = _specializations[index];
          final isSelected = (_selectedSpecialization == spec) || 
                             (_selectedSpecialization == null && spec == 'All');
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(spec),
              selected: isSelected,
              selectedColor: AppColors.primary.withOpacity(0.12),
              disabledColor: Colors.transparent,
              checkmarkColor: AppColors.primary,
              labelStyle: AppTypography.labelLarge.copyWith(
                color: isSelected ? AppColors.primary : AppColors.inkMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.divider,
                  width: 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedSpecialization = spec == 'All' ? null : spec;
                  _applyFilters();
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdvisorCard(dynamic advisor) {
    final List<dynamic> specs = advisor['specializations'] ?? [];
    
    return AnimatedCard(
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        color: AppColors.surface,
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/advisors/${advisor['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(
                        (advisor['name'] ?? 'A')[0],
                        style: AppTypography.titleLarge.copyWith(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(advisor['name'] ?? 'Advisor', style: AppTypography.titleMedium),
                              const SizedBox(width: 6),
                              if (advisor['arn_verified'] == true)
                                const Tooltip(
                                  message: 'AMFI Registered & Verified',
                                  child: Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                                ),
                              if (advisor['gst_verified'] == true)
                                const Tooltip(
                                  message: 'GST Registered & Verified',
                                  child: Padding(
                                    padding: EdgeInsets.only(left: 4.0),
                                    child: Icon(Icons.gavel_rounded, color: Colors.blue, size: 18),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            advisor['arn_number'] ?? 'ARN-XXXXXX',
                            style: AppTypography.bodySmall.copyWith(
                              fontFamily: 'JetBrains Mono',
                              color: AppColors.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                advisor['rating']?.toString() ?? '5.0',
                                style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${advisor['experience_years']} yrs exp',
                                style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      advisor['charges'] ?? 'Free',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  advisor['bio'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: specs.map<Widget>((s) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(
                        s.toString(),
                        style: AppTypography.bodySmall.copyWith(fontSize: 11, color: AppColors.ink),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
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
          const Icon(Icons.people_outline_rounded, size: 64, color: AppColors.inkMuted),
          const SizedBox(height: 16),
          Text('No advisors found', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search query or filters',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
