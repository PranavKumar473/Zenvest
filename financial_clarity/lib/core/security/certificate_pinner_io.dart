import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Native (Android/iOS) implementation of SSL certificate pinning.
void setupCertificatePinningImpl(Dio dio) {
  const List<String> pinnedFingerprints = [
    "7a:44:83:8b:2d:c2:d9:21:6f:d1:80:bc:f6:7e:92:ef:2a:bd:ad:65:d3:c8:6e:f2:8c:13:14:ef:13:79:e4:65"
  ];

  if (dio.httpClientAdapter is IOHttpClientAdapter) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();

      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        final derBytes = cert.der;
        final sha256Bytes = sha256.convert(derBytes).bytes;

        final fingerprint = sha256Bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toLowerCase();

        return pinnedFingerprints.any((pin) => pin.toLowerCase() == fingerprint);
      };

      return client;
    };
  }
}
