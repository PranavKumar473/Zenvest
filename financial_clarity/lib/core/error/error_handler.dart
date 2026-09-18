/// Global error handling utilities.
import 'package:dio/dio.dart';
import 'failures.dart';

class ErrorHandler {
  ErrorHandler._();

  /// Map a DioException to a typed Failure.
  static Failure handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure('Connection timed out. Please try again.');

      case DioExceptionType.connectionError:
        return const NetworkFailure(
          'Unable to connect. Check your internet connection.',
        );

      case DioExceptionType.badResponse:
        return _handleStatusCode(
          error.response?.statusCode,
          error.response?.data,
        );

      case DioExceptionType.cancel:
        return const ClientFailure('Request was cancelled');

      default:
        return const UnknownFailure('An unexpected error occurred');
    }
  }

  /// Map HTTP status codes to typed failures.
  static Failure _handleStatusCode(int? statusCode, dynamic data) {
    final message = _extractMessage(data);

    switch (statusCode) {
      case 400:
        return ClientFailure(message ?? 'Invalid request', statusCode: 400);
      case 401:
        return AuthFailure(message ?? 'Authentication failed', statusCode: 401);
      case 403:
        return AuthFailure(message ?? 'Access denied', statusCode: 403);
      case 404:
        return ClientFailure(message ?? 'Resource not found', statusCode: 404);
      case 409:
        return ClientFailure(message ?? 'Conflict', statusCode: 409);
      case 422:
        return ClientFailure(message ?? 'Validation error', statusCode: 422);
      case 429:
        return ClientFailure('Too many requests. Please slow down.',
            statusCode: 429);
      default:
        if (statusCode != null && statusCode >= 500) {
          return ServerFailure(message ?? 'Server error', statusCode: statusCode);
        }
        return UnknownFailure(message ?? 'Unknown error');
    }
  }

  /// Extract error message from API response body.
  static String? _extractMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String) return message;
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        try {
          return detail.map((e) {
            if (e is Map) {
              final loc = e['loc'];
              final msg = e['msg'];
              if (loc is List && loc.isNotEmpty) {
                return '${loc.last}: $msg';
              }
              return msg?.toString() ?? '';
            }
            return e.toString();
          }).where((msg) => msg.isNotEmpty).join(', ');
        } catch (_) {
          return detail.toString();
        }
      }
      return message?.toString() ?? detail?.toString();
    }
    if (data is String) return data;
    return null;
  }

  /// Map any exception to a Failure.
  static Failure handleException(Object error) {
    if (error is DioException) return handleDioError(error);
    if (error is Failure) return error;
    return UnknownFailure(error.toString());
  }
}
