import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';

// Only import IO-specific code when not on web
import 'certificate_pinner_io.dart' if (dart.library.html) 'certificate_pinner_stub.dart' as impl;

/// SSL Certificate Pinning configuration helper for Dio.
/// Only active on native platforms (Android/iOS). No-op on web.
void setupCertificatePinning(Dio dio) {
  if (kIsWeb) return; // Certificate pinning not possible on web
  impl.setupCertificatePinningImpl(dio);
}
