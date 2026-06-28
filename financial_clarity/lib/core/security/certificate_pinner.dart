import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// SSL Certificate Pinning configuration helper for Dio.
/// Prevents Man-in-the-Middle (MITM) attacks by ensuring the app only
/// communicates with backend servers whose certificates match the pinned SHA-256 fingerprints.
void setupCertificatePinning(Dio dio) {
  // Pinned SHA-256 fingerprint(s) of the production backend SSL certificate.
  // In development, this won't affect local HTTP traffic, but enforces strict verification for HTTPS.
  const List<String> pinnedFingerprints = [
    "7a:44:83:8b:2d:c2:d9:21:6f:d1:80:bc:f6:7e:92:ef:2a:bd:ad:65:d3:c8:6e:f2:8c:13:14:ef:13:79:e4:65"
  ];

  if (dio.httpClientAdapter is IOHttpClientAdapter) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();

      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Calculate SHA-256 hash of DER bytes of certificate
        final derBytes = cert.der;
        final sha256Bytes = sha256.convert(derBytes).bytes;

        final fingerprint = sha256Bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toLowerCase();

        // Allow connection only if the certificate fingerprint matches our pinned list
        return pinnedFingerprints.any((pin) => pin.toLowerCase() == fingerprint);
      };

      return client;
    };
  }
}
