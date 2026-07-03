import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/error/error_handler.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import 'auth_controller.dart';

class ProfileState {
  final Map<String, dynamic>? profile;
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final String? successMessage;

  const ProfileState({
    this.profile,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.successMessage,
  });

  ProfileState copyWith({
    Map<String, dynamic>? profile,
    bool? isLoading,
    bool? isSaving,
    String? error,
    String? successMessage,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      successMessage: successMessage,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final Dio _dio;
  final Ref _ref;

  ProfileNotifier(this._dio, this._ref) : super(const ProfileState()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get(ApiEndpoints.userProfile);
      state = state.copyWith(profile: response.data, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ErrorHandler.handleDioError(e).message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load profile',
      );
    }
  }

  Future<bool> updateProfile(String name, String phoneNumber) async {
    state = state.copyWith(isSaving: true, successMessage: null);
    try {
      final response = await _dio.patch(
        ApiEndpoints.userProfile,
        data: {
          'name': name,
          'phone_number': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
        },
      );
      state = state.copyWith(
        profile: response.data,
        isSaving: false,
        successMessage: 'Profile updated successfully!',
      );
      // Update session name if changed
      _ref.read(authControllerProvider.notifier).checkAuthStatus();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: ErrorHandler.handleDioError(e).message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to update profile',
      );
      return false;
    }
  }
}

final profileControllerProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier(ref.read(dioProvider), ref);
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _initializeControllers(Map<String, dynamic> profile) {
    if (_nameController.text.isEmpty && _phoneController.text.isEmpty) {
      _nameController.text = profile['name'] ?? '';
      _phoneController.text = profile['phone_number'] ?? '';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref.read(profileControllerProvider.notifier).updateProfile(
          _nameController.text.trim(),
          _phoneController.text.trim(),
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes saved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    final controller = ref.read(profileControllerProvider.notifier);

    // Initial load
    if (state.profile != null) {
      _initializeControllers(state.profile!);
    }

    ref.listen<ProfileState>(profileControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Profile', style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _nameController.clear();
              _phoneController.clear();
              controller.loadProfile();
            },
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(ProfileState state) {
    if (state.isLoading && state.profile == null) {
      return LoadingShimmer.list(count: 4, itemHeight: 90);
    }

    if (state.error != null && state.profile == null) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: ref.read(profileControllerProvider.notifier).loadProfile,
      );
    }

    final profile = state.profile ?? {};
    final email = profile['email'] ?? '';
    final name = profile['name'] ?? '';
    final ageGroup = profile['age_group'] ?? 'Not selected';
    final incomeBracket = profile['income_bracket'] ?? 'Not selected';
    final riskLevel = (profile['risk_profile'] as Map?)?['level'] ?? 'Not assessed';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar and Email Card
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.divider, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primarySurface,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppTypography.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: AppTypography.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Onboarding & Parameters Summary Card (Read-only parameters)
            Text('Financial Parameters', style: AppTypography.titleMedium),
            const SizedBox(height: 10),
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.divider, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSummaryRow('Age Group', ageGroup),
                    const Divider(height: 20),
                    _buildSummaryRow('Salary Range', '₹$incomeBracket'),
                    const Divider(height: 20),
                    _buildSummaryRow('Riskometer Level', riskLevel, valueColor: AppColors.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Editable Personal Details
            Text('Personal Details', style: AppTypography.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Name is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Phone Number (for SMS Sync)',
                prefixIcon: const Icon(Icons.phone_outlined),
                hintText: 'e.g. +919876543210',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null; // Phone is optional
                final clean = v.trim();
                if (clean.length < 10) return 'Please enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 30),

            // Submit changes button
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: state.isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: state.isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),

            // Logout Button
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authControllerProvider.notifier).logout();
                  if (mounted) {
                    context.go('/login');
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.ink,
          ),
        ),
      ],
    );
  }
}
