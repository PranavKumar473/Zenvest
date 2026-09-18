import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../storage/secure_storage.dart';

final appLockProvider = StateNotifierProvider<AppLockService, bool>((ref) {
  final storage = ref.read(secureStorageProvider);
  return AppLockService(storage);
});

class AppLockService extends StateNotifier<bool> {
  final SecureStorageService _storage;
  final LocalAuthentication _auth = LocalAuthentication();

  DateTime? _lastActiveTime;
  static const int lockTimeoutMinutes = 5;

  AppLockService(this._storage) : super(false) {
    _init();
  }

  Future<void> _init() async {
    final hasTokens = await _storage.hasTokens();
    final isBioEnabled = await _storage.isBiometricEnabled();
    // Enable lock on launch if the user is logged in and has biometric unlock enabled
    if (hasTokens && isBioEnabled) {
      state = true;
    }
  }

  void handleAppPaused() {
    _lastActiveTime = DateTime.now();
  }

  Future<void> handleAppResumed() async {
    final hasTokens = await _storage.hasTokens();
    final isBioEnabled = await _storage.isBiometricEnabled();

    if (!hasTokens || !isBioEnabled) {
      state = false;
      return;
    }

    if (_lastActiveTime != null) {
      final difference = DateTime.now().difference(_lastActiveTime!);
      if (difference.inMinutes >= lockTimeoutMinutes) {
        state = true;
      }
    }
  }

  /// Trigger biometric/passcode verification to unlock the app.
  Future<bool> authenticate() async {
    final isBioEnabled = await _storage.isBiometricEnabled();
    if (!isBioEnabled) {
      state = false;
      return true;
    }

    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        state = false;
        return true;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to unlock Financial Clarity',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows falling back to Device PIN/Pattern/Password
        ),
      );

      if (authenticated) {
        state = false;
        _lastActiveTime = null;
      }
      return authenticated;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
