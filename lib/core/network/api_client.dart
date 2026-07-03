/// Dio HTTP client with interceptors for JWT auth, retry, and error mapping.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_endpoints.dart';
import 'api_interceptor.dart';
import '../storage/secure_storage.dart';
import '../security/certificate_pinner.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  // Apply SSL certificate pinning
  setupCertificatePinning(dio);

  final secureStorage = ref.read(secureStorageProvider);
  dio.interceptors.add(AuthInterceptor(dio, secureStorage));
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
    logPrint: (obj) {}, // Suppress logs in production
  ));

  return dio;
});
