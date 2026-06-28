import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});

class CryptoService {
  // Configured encryption key matching the backend
  static const String _rawKey = "CHANGE-THIS-32-BYTE-KEY-IN-PROD!";

  /// Encrypts a map payload using AES-256-GCM.
  /// Returns a map with base64 encoded 'iv', 'ciphertext', and 'tag'.
  Map<String, String> encryptPayload(Map<String, dynamic> data) {
    // 1. Derive 32-byte key using SHA-256
    final keyBytes = sha256.convert(utf8.encode(_rawKey)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));

    // 2. Generate random 12-byte IV (nonce) for GCM
    final iv = enc.IV.fromSecureRandom(12);

    // 3. Encrypt using AES-GCM
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm, padding: null));
    final plaintext = json.encode(data);
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // In the encrypt package's AES GCM mode, the resulting bytes include the 16-byte GCM tag appended at the end.
    final combinedBytes = encrypted.bytes;
    final ciphertextBytes = combinedBytes.sublist(0, combinedBytes.length - 16);
    final tagBytes = combinedBytes.sublist(combinedBytes.length - 16);

    return {
      'iv': base64.encode(iv.bytes),
      'ciphertext': base64.encode(ciphertextBytes),
      'tag': base64.encode(tagBytes),
    };
  }

  /// Decrypts a payload that was encrypted with AES-256-GCM.
  Map<String, dynamic>? decryptPayload(Map<String, String> encryptedData) {
    try {
      final ivStr = encryptedData['iv'];
      final ciphertextStr = encryptedData['ciphertext'];
      final tagStr = encryptedData['tag'];

      if (ivStr == null || ciphertextStr == null || tagStr == null) {
        return null;
      }

      final ivBytes = base64.decode(ivStr);
      final ciphertextBytes = base64.decode(ciphertextStr);
      final tagBytes = base64.decode(tagStr);

      // Reconstruct combined bytes (ciphertext + tag) for the decrypter
      final combinedBytes = Uint8List.fromList([...ciphertextBytes, ...tagBytes]);

      final keyBytes = sha256.convert(utf8.encode(_rawKey)).bytes;
      final key = enc.Key(Uint8List.fromList(keyBytes));

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm, padding: null));
      final decryptedStr = encrypter.decrypt(
        enc.Encrypted(combinedBytes),
        iv: enc.IV(Uint8List.fromList(ivBytes)),
      );

      return json.decode(decryptedStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
