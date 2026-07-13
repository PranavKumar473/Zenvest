/// Advisor Onboarding & Verification — collects the SEBI/GST compliance
/// fields (PAN, address, GST, INA) that registration intentionally leaves
/// out, then submits them for review. Mirrors the investor onboarding split:
/// register with the bare minimum, complete the profile once signed in.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../human_advisors/domain/advisor.dart';

class AdvisorOnboardingScreen extends ConsumerStatefulWidget {
  const AdvisorOnboardingScreen({super.key});

  @override
  ConsumerState<AdvisorOnboardingScreen> createState() => _AdvisorOnboardingScreenState();
}

class _AdvisorOnboardingScreenState extends ConsumerState<AdvisorOnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 4;
  bool _isSubmitting = false;
  String? _submitError;

  // Step 0 — PAN & Address
  final _panController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  // Step 1 — GST
  final _gstController = TextEditingController();
  GstVerificationStatus _gstStatus = GstVerificationStatus.unverified;
  bool _isVerifyingGst = false;
  String? _gstVerifyMessage;

  // Step 2 — SEBI INA
  final _inaController = TextEditingController();

  // Step 3 — Profile
  XFile? _profilePicture;
  final _bioController = TextEditingController();
  final _experienceController = TextEditingController();
  final _consultationFeeController = TextEditingController();
  final Set<String> _specializations = {};

  static const _specializationOptions = [
    'Mutual Funds',
    'Wealth Growth',
    'Tax Planning',
    'Bonds & Fixed Income',
    'Retirement Planning',
    'Stocks & Equities',
    'Estate Planning',
    'Goal-Based Planning',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _panController.dispose();
    _addressLine1Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _gstController.dispose();
    _inaController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _consultationFeeController.dispose();
    super.dispose();
  }

  static final _panPattern = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

  String? get _panError {
    final v = _panController.text.trim().toUpperCase();
    if (v.isEmpty) return null; // don't nag before they've started typing
    if (!_panPattern.hasMatch(v)) return 'Enter a valid 10-character PAN, e.g. ABCPD1234E';
    return null;
  }

  String? get _pincodeError {
    final v = _pincodeController.text.trim();
    if (v.isEmpty) return null;
    if (v.length != 6) return 'Pincode must be exactly 6 digits';
    return null;
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _panPattern.hasMatch(_panController.text.trim().toUpperCase()) &&
            _cityController.text.trim().isNotEmpty &&
            _stateController.text.trim().isNotEmpty &&
            _pincodeController.text.trim().length == 6;
      default:
        return true; // GST, INA, and profile fields are optional
    }
  }

  /// Human-readable reason step 0's Continue button is still disabled —
  /// shown near the button so it's never a silent dead end.
  String? get _step0BlockedReason {
    if (_currentStep != 0 || _canProceed) return null;
    final missing = <String>[];
    if (!_panPattern.hasMatch(_panController.text.trim().toUpperCase())) missing.add('a valid PAN');
    if (_cityController.text.trim().isEmpty) missing.add('city');
    if (_stateController.text.trim().isEmpty) missing.add('state');
    if (_pincodeController.text.trim().length != 6) missing.add('a 6-digit pincode');
    if (missing.isEmpty) return null;
    return 'Still need: ${missing.join(', ')}.';
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _currentStep--);
    }
  }

  Future<void> _verifyGst() async {
    final gstNumber = _gstController.text.trim().toUpperCase();
    if (gstNumber.isEmpty) return;

    setState(() {
      _isVerifyingGst = true;
      _gstStatus = GstVerificationStatus.pending;
      _gstVerifyMessage = null;
    });

    try {
      final dio = ref.read(dioProvider);
      // GST verification reads the number already on file, so save it first.
      await dio.patch('/users/me', data: {'gst_number': gstNumber});
      final response = await dio.post(ApiEndpoints.verifyMyGst);
      final data = response.data;
      if (mounted) {
        setState(() {
          _gstStatus = gstStatusFromString(data['gst_verification_status'] as String?);
          _gstVerifyMessage = _gstStatus == GstVerificationStatus.verified
              ? 'Verified against GST Portal as "${data['gst_legal_name']}"'
              : (data['reason'] as String? ?? 'Verification failed. Check the GSTIN and try again.');
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _gstStatus = GstVerificationStatus.failed;
          _gstVerifyMessage = e.response?.data?['detail']?.toString() ?? 'Could not reach the GST Portal.';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifyingGst = false);
    }
  }

  Future<void> _pickProfilePicture() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (image != null) setState(() => _profilePicture = image);
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final dio = ref.read(dioProvider);

      await dio.patch('/users/me', data: {
        'pan_number': _panController.text.trim().toUpperCase(),
        'address': {
          'line1': _addressLine1Controller.text.trim(),
          'city': _cityController.text.trim(),
          'state': _stateController.text.trim(),
          'pincode': _pincodeController.text.trim(),
        },
        if (_gstController.text.trim().isNotEmpty) 'gst_number': _gstController.text.trim().toUpperCase(),
        if (_inaController.text.trim().isNotEmpty) 'sebi_registration_number': _inaController.text.trim().toUpperCase(),
        if (_bioController.text.trim().isNotEmpty) 'bio': _bioController.text.trim(),
        if (_specializations.isNotEmpty) 'specializations': _specializations.toList(),
        if (_experienceController.text.trim().isNotEmpty)
          'experience_years': int.tryParse(_experienceController.text.trim()),
        if (_consultationFeeController.text.trim().isNotEmpty)
          'consultation_fee_monthly': double.tryParse(_consultationFeeController.text.trim()),
      });

      if (_profilePicture != null) {
        final bytes = await _profilePicture!.readAsBytes();
        await dio.post(
          ApiEndpoints.uploadProfilePicture,
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(bytes, filename: _profilePicture!.name),
          }),
        );
      }

      if (_gstController.text.trim().isNotEmpty && _gstStatus != GstVerificationStatus.verified) {
        // Best-effort final verification pass if the advisor never tapped
        // "Verify" on step 2, or edited the number afterwards.
        await dio.post(ApiEndpoints.verifyMyGst);
      }

      await dio.post(ApiEndpoints.completeAdvisorOnboarding);

      // The router's redirect guard reads the cached auth state's
      // onboardingCompleted flag — refresh it or it'll bounce us straight
      // back here even though the backend is done.
      await ref.read(authControllerProvider.notifier).checkAuthStatus();

      if (mounted) context.go('/advisor-requests');
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _submitError = e.response?.data?['detail']?.toString() ?? 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: _currentStep > 0
            ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _previousStep)
            : null,
        title: Text('Verification · Step ${_currentStep + 1} of $_totalSteps'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_currentStep + 1) / _totalSteps,
                minHeight: 4,
                backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildPanAddressStep(),
                _buildGstStep(),
                _buildInaStep(),
                _buildProfileStep(),
              ],
            ),
          ),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(8)),
                child: Text(_submitError!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
              ),
            ),
          if (_step0BlockedReason != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _step0BlockedReason!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_canProceed && !_isSubmitting) ? _nextStep : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkOnPrimary),
                      )
                    : Text(_currentStep == _totalSteps - 1 ? 'Submit for Verification' : 'Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepScaffold({required String title, required String subtitle, required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.displayMedium),
          const SizedBox(height: 8),
          Text(subtitle, style: AppTypography.bodyLarge.copyWith(color: AppColors.inkLight)),
          const SizedBox(height: 32),
          ...children,
        ],
      ),
    );
  }

  Widget _buildPanAddressStep() {
    return _buildStepScaffold(
      title: 'Identity & Address',
      subtitle: 'Required for your SEBI-compliant advisor profile. PAN is masked everywhere except admin review.',
      children: [
        TextField(
          controller: _panController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 10,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
            TextInputFormatter.withFunction((oldValue, newValue) {
              return newValue.copyWith(text: newValue.text.toUpperCase());
            }),
          ],
          decoration: InputDecoration(
            labelText: 'PAN Number',
            hintText: 'ABCPD1234E',
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: _panError,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressLine1Controller,
          decoration: const InputDecoration(labelText: 'Address Line 1 (optional)', prefixIcon: Icon(Icons.home_outlined)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cityController,
          decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _stateController,
          decoration: const InputDecoration(labelText: 'State', prefixIcon: Icon(Icons.map_outlined)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pincodeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Pincode',
            prefixIcon: const Icon(Icons.pin_drop_outlined),
            errorText: _pincodeError,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildGstStep() {
    Color statusColor;
    String statusLabel;
    switch (_gstStatus) {
      case GstVerificationStatus.verified:
        statusColor = AppColors.success;
        statusLabel = 'Verified';
        break;
      case GstVerificationStatus.failed:
        statusColor = AppColors.error;
        statusLabel = 'Failed';
        break;
      case GstVerificationStatus.pending:
        statusColor = AppColors.warning;
        statusLabel = 'Checking…';
        break;
      case GstVerificationStatus.unverified:
        statusColor = AppColors.inkMuted;
        statusLabel = 'Not verified';
    }

    return _buildStepScaffold(
      title: 'GST Registration',
      subtitle: 'Optional — only required if your advisory turnover exceeds ₹20L/year. '
          'We cross-check your GSTIN against the GST Portal.',
      children: [
        TextField(
          controller: _gstController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 15,
          decoration: const InputDecoration(
            labelText: 'GSTIN (optional)',
            hintText: '27AABCU9603R1ZM',
            prefixIcon: Icon(Icons.receipt_long_outlined),
          ),
          onChanged: (_) => setState(() {
            _gstStatus = GstVerificationStatus.unverified;
            _gstVerifyMessage = null;
          }),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor),
              ),
              child: Text(statusLabel, style: AppTypography.labelMedium.copyWith(color: statusColor, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            OutlinedButton.icon(
              icon: _isVerifyingGst
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Verify with GST Portal'),
              onPressed: (_gstController.text.trim().isEmpty || _isVerifyingGst) ? null : _verifyGst,
            ),
          ],
        ),
        if (_gstVerifyMessage != null) ...[
          const SizedBox(height: 8),
          Text(_gstVerifyMessage!, style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted)),
        ],
      ],
    );
  }

  Widget _buildInaStep() {
    return _buildStepScaffold(
      title: 'SEBI RIA Registration',
      subtitle: 'If you provide fee-only investment advice (not just mutual fund execution), '
          'enter your SEBI Investment Adviser registration number. Per SEBI guidelines, '
          'fee-only advice is identified by your INA number — separate from the ARN you '
          'registered with, which covers mutual fund execution only.',
      children: [
        TextField(
          controller: _inaController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'SEBI Registration Number / INA (optional)',
            hintText: 'INA000012345',
            prefixIcon: Icon(Icons.verified_user_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ARN = mutual fund execution/distribution.\nINA = fee-only advice, no execution.\n'
                  'You can hold both — investors will see whichever they attach to their investment.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.inkLight, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStep() {
    return _buildStepScaffold(
      title: 'Public Profile',
      subtitle: 'What investors see before they send you a Connect Request.',
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickProfilePicture,
            child: CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primarySurface,
              backgroundImage: _profilePicture != null ? NetworkImage(_profilePicture!.path) : null,
              child: _profilePicture == null
                  ? const Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 28)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('Tap to add profile photo', style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted))),
        const SizedBox(height: 24),
        TextField(
          controller: _bioController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Bio (optional)', alignLabelWithHint: true),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _experienceController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Years of experience (optional)'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _consultationFeeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Monthly consultation fee, ₹ (optional)',
            helperText: 'Investors can subscribe to this as a recurring charge',
          ),
        ),
        const SizedBox(height: 16),
        Text('Specializations', style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _specializationOptions.map((s) {
            final selected = _specializations.contains(s);
            return FilterChip(
              label: Text(s),
              selected: selected,
              onSelected: (v) => setState(() => v ? _specializations.add(s) : _specializations.remove(s)),
            );
          }).toList(),
        ),
      ],
    );
  }
}
