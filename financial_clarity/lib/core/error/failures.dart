/// Typed failure classes for structured error handling across the app.
abstract class Failure {
  final String message;
  final int? statusCode;

  const Failure(this.message, {this.statusCode});

  @override
  String toString() => 'Failure($statusCode): $message';
}

/// Network-related failures (no connection, timeout, etc.)
class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.statusCode});
}

/// Server-side errors (5xx)
class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.statusCode});
}

/// Client errors (4xx) — validation, not found, etc.
class ClientFailure extends Failure {
  const ClientFailure(super.message, {super.statusCode});
}

/// Authentication failures (401, 403)
class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.statusCode});
}

/// Cache / local storage failures
class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.statusCode});
}

/// Unexpected / unknown failures
class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.statusCode});
}
