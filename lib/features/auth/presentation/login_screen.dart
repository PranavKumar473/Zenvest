/// Login screen with email/password and biometric authentication.
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  final _nameController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  // Advisor fields
  String _userType = 'user'; // 'user' or 'advisor'
  final _arnController = TextEditingController();
  final _advisorLegalNameController = TextEditingController();
  XFile? _arnCardFile;
  bool _showSuccessScreen = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
    
    // Check auto-login status on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).checkAuthStatus();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _arnController.dispose();
    _advisorLegalNameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isLogin && _userType == 'advisor') {
      if (_arnController.text.trim().isEmpty ||
          !RegExp(r"^ARN-\d{4,6}$").hasMatch(_arnController.text.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid ARN in format ARN-XXXXX (4-6 digits)')),
        );
        return;
      }
      if (_advisorLegalNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter advisor legal name')),
        );
        return;
      }
      if (_arnCardFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please upload your ARN card photo')),
        );
        return;
      }
    }

    final controller = ref.read(authControllerProvider.notifier);
    bool success;

    if (_isLogin) {
      success = await controller.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } else {
      Uint8List? fileBytes;
      if (_userType == 'advisor' && _arnCardFile != null) {
        fileBytes = await _arnCardFile!.readAsBytes();
      }
      success = await controller.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        userType: _userType,
        arnNumber: _userType == 'advisor' ? _arnController.text.trim() : null,
        advisorName: _userType == 'advisor' ? _advisorLegalNameController.text.trim() : null,
        licenseImageBytes: fileBytes,
        licenseImageName: _userType == 'advisor' ? _arnCardFile?.name : null,
      );
    }

    if (success && mounted) {
      if (!_isLogin) {
        if (_userType == 'advisor') {
          setState(() {
            _showSuccessScreen = true;
          });
        } else {
          setState(() {
            _isLogin = true;
            _passwordController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created successfully! Please sign in to complete onboarding.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final state = ref.read(authControllerProvider);
        context.go(_homeRouteFor(state));
      }
    }
  }

  String _homeRouteFor(AuthState state) {
    if (state.userType == 'advisor') {
      return state.onboardingCompleted ? '/advisor-requests' : '/advisor-onboarding';
    }
    return state.onboardingCompleted ? '/dashboard' : '/onboarding';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && previous?.status != AuthStatus.authenticated) {
        context.go(_homeRouteFor(next));
      }
    });

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _showSuccessScreen
                ? _buildSuccessScreen()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      // Logo & Title
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 48,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Financial Clarity',
                        style: AppTypography.displayLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin
                            ? 'Welcome back. Let\'s review your finances.'
                            : 'Start your journey to financial clarity.',
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.inkLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Form
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (!_isLogin) ...[
                              _buildUserTypeSelection(),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Full Name',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  validator: (v) {
                                    if (!_isLogin && (v == null || v.length < 2)) {
                                      return 'Please enter your name';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined)),
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              validator: (v) {
                                if (v == null || !v.contains('@')) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() => _obscurePassword = !_obscurePassword);
                                  },
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: (v) {
                                if (v == null || v.length < 8) {
                                  return 'Password must be at least 8 characters';
                                }
                                return null;
                              },
                            ),
                            if (!_isLogin && _userType == 'advisor') ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _arnController,
                                decoration: const InputDecoration(
                                  labelText: 'ARN Number',
                                  hintText: 'ARN-12345',
                                  helperText: 'Your AMFI-assigned Agent Registration Number',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                inputFormatters: [
                                  TextInputFormatter.withFunction((oldValue, newValue) {
                                    var text = newValue.text.toUpperCase();
                                    if (!text.startsWith('ARN-') && text.isNotEmpty) {
                                      text = 'ARN-$text'.replaceAll('ARN-ARN-', 'ARN-');
                                    }
                                    return newValue.copyWith(
                                      text: text,
                                      selection: TextSelection.fromPosition(
                                        TextPosition(offset: text.length),
                                      ),
                                    );
                                  }),
                                ],
                                validator: (v) {
                                  if (!_isLogin && _userType == 'advisor') {
                                    if (v == null || v.isEmpty) return 'ARN is required';
                                    if (!RegExp(r"^ARN-\d{4,6}$").hasMatch(v)) return 'Format must be ARN-XXXXX';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _advisorLegalNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Full Name (as on ARN card)',
                                  hintText: 'As printed on your AMFI registration',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (v) {
                                  if (!_isLogin && _userType == 'advisor' && (v == null || v.isEmpty)) {
                                    return 'Legal name is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: () async {
                                  final picker = ImagePicker();
                                  final image = await picker.pickImage(source: ImageSource.gallery);
                                  if (image != null) {
                                    setState(() => _arnCardFile = image);
                                  }
                                },
                                child: Container(
                                  height: 120,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.divider, width: 1.5),
                                    borderRadius: BorderRadius.circular(12),
                                    color: AppColors.canvas,
                                  ),
                                  child: _arnCardFile != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(11),
                                          child: Image.network(_arnCardFile!.path, fit: BoxFit.cover, width: double.infinity),
                                        )
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.upload_file_outlined, size: 32, color: AppColors.inkMuted),
                                            const SizedBox(height: 8),
                                            Text('Upload ARN Card Photo', style: AppTypography.labelMedium),
                                            Text('JPG or PNG, front side', style: AppTypography.labelSmall.copyWith(color: AppColors.inkMuted)),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Error message
                      if (authState.status == AuthStatus.error && authState.failure != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.errorLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              authState.failure!.message,
                              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),

                      const SizedBox(height: 32),

                      // Submit button
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: authState.status == AuthStatus.loading ? null : _submit,
                          child: authState.status == AuthStatus.loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.inkOnPrimary,
                                  ),
                                )
                              : Text(_isLogin ? 'Sign In' : 'Create Account'),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Toggle login/register
                      TextButton(
                        onPressed: () {
                          setState(() => _isLogin = !_isLogin);
                        },
                        child: Text(
                          _isLogin
                              ? 'Don\'t have an account? Sign Up'
                              : 'Already have an account? Sign In',
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserTypeSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Who are you signing up as?',
          style: AppTypography.titleMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _userType = 'user'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _userType == 'user' ? AppColors.primarySurface : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _userType == 'user' ? AppColors.primary : AppColors.divider,
                      width: _userType == 'user' ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text('👤', style: TextStyle(fontSize: 24)),
                      const SizedBox(height: 8),
                      Text('Investor', style: AppTypography.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        'I want to track my money & get advice',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.inkLight),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _userType = 'advisor'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _userType == 'advisor' ? AppColors.primarySurface : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _userType == 'advisor' ? AppColors.primary : AppColors.divider,
                      width: _userType == 'advisor' ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text('🏛️', style: TextStyle(fontSize: 24)),
                      const SizedBox(height: 8),
                      Text('Advisor', style: AppTypography.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        'I am an AMFI-registered advisor',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.inkLight),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccessScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        const Icon(
          Icons.check_circle_rounded,
          size: 80,
          color: AppColors.success,
        ),
        const SizedBox(height: 24),
        Text(
          'Registration Submitted',
          style: AppTypography.displayMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Your ARN card has been uploaded for review. Sign in now to complete your verification profile (PAN, address, GST, and SEBI registration) — the advisor dashboard unlocks once that\'s done.',
          style: AppTypography.bodyLarge.copyWith(color: AppColors.inkLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                'ARN Number: ${_arnController.text}',
                style: AppTypography.labelLarge.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    'Pending Verification 🔄',
                    style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _showSuccessScreen = false;
              _isLogin = true;
              _passwordController.clear();
              _emailController.clear();
              _nameController.clear();
              _arnController.clear();
              _advisorLegalNameController.clear();
              _arnCardFile = null;
            });
          },
          child: const Text('Continue to App'),
        ),
      ],
    );
  }
}
