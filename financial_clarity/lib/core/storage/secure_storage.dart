import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _biometricKey = 'biometric_enabled';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Fallback memory storage if both fail
  static final Map<String, String> _memoryStorage = {};

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
        return;
      } catch (e) {
        _memoryStorage[key] = value;
        return;
      }
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _memoryStorage[key] = value;
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key) ?? _memoryStorage[key];
      } catch (e) {
        return _memoryStorage[key];
      }
    }
    try {
      return await _storage.read(key: key) ?? _memoryStorage[key];
    } catch (e) {
      return _memoryStorage[key];
    }
  }

  Future<void> _delete(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
        _memoryStorage.remove(key);
        return;
      } catch (e) {
        _memoryStorage.remove(key);
        return;
      }
    }
    try {
      await _storage.delete(key: key);
      _memoryStorage.remove(key);
    } catch (e) {
      _memoryStorage.remove(key);
    }
  }

  // ── Token Management ─────────────────────────────────────
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _write(_accessTokenKey, accessToken);
    await _write(_refreshTokenKey, refreshToken);
  }

  Future<String?> getAccessToken() async {
    return _read(_accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return _read(_refreshTokenKey);
  }

  // ── User Data ────────────────────────────────────────────
  Future<void> saveUserId(String userId) async {
    await _write(_userIdKey, userId);
  }

  Future<String?> getUserId() async {
    return _read(_userIdKey);
  }

  // ── Biometric ────────────────────────────────────────────
  Future<void> setBiometricEnabled(bool enabled) async {
    await _write(_biometricKey, enabled.toString());
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _read(_biometricKey);
    return value == 'true';
  }

  // ── Clear All ────────────────────────────────────────────
  Future<void> clearAll() async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_accessTokenKey);
        await prefs.remove(_refreshTokenKey);
        await prefs.remove(_userIdKey);
        await prefs.remove(_biometricKey);
      } catch (_) {}
    } else {
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
    _memoryStorage.clear();
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

