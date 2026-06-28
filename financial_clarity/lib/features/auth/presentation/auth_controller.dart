/// Auth state controller using Riverpod.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/error/error_handler.dart';
import '../../../core/error/failures.dart';

/// Auth state
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? userName;
  final bool onboardingCompleted;
  final Failure? failure;

  const AuthState({
    this.status = AuthStatus.initial,
    this.userId,
    this.userName,
    this.onboardingCompleted = false,
    this.failure,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? userName,
    bool? onboardingCompleted,
    Failure? failure,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      failure: failure,
    );
  }
}

/// Auth controller
class AuthController extends StateNotifier<AuthState> {
  final Dio _dio;
  final SecureStorageService _storage;

  AuthController(this._dio, this._storage) : super(const AuthState());

  /// Check if user has existing session
  Future<void> checkAuthStatus() async {
    final hasTokens = await _storage.hasTokens();
    if (hasTokens) {
      try {
        final response = await _dio.get(ApiEndpoints.userProfile);
        final user = response.data;
        state = state.copyWith(
          status: AuthStatus.authenticated,
          userId: user['id'],
          userName: user['name'],
          onboardingCompleted: user['onboarding_completed'] ?? false,
        );
      } catch (_) {
        await _storage.clearAll();
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// Register a new user
  Future<bool> register(String name, String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final response = await _dio.post(
        ApiEndpoints.register,
        data: {'name': name, 'email': email, 'password': password},
      );

      await _storage.saveTokens(
        accessToken: response.data['access_token'],
        refreshToken: response.data['refresh_token'],
      );

      state = state.copyWith(
        status: AuthStatus.authenticated,
        userName: name,
        onboardingCompleted: false,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        failure: ErrorHandler.handleDioError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        failure: UnknownFailure(e.toString()),
      );
      return false;
    }
  }

  /// Login with email and password
  Future<bool> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final response = await _dio.post(
        ApiEndpoints.login,
        data: {'email': email, 'password': password},
      );

      await _storage.saveTokens(
        accessToken: response.data['access_token'],
        refreshToken: response.data['refresh_token'],
      );

      // Fetch profile
      final profileResponse = await _dio.get(ApiEndpoints.userProfile);
      final user = profileResponse.data;

      state = state.copyWith(
        status: AuthStatus.authenticated,
        userId: user['id'],
        userName: user['name'],
        onboardingCompleted: user['onboarding_completed'] ?? false,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        failure: ErrorHandler.handleDioError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        failure: UnknownFailure(e.toString()),
      );
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    await _storage.clearAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

/// Provider
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.read(dioProvider),
    ref.read(secureStorageProvider),
  );
});
