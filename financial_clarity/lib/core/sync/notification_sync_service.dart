import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../security/crypto_service.dart';

final notificationSyncServiceProvider = Provider<NotificationSyncService>((ref) {
  final dio = ref.read(dioProvider);
  final crypto = ref.read(cryptoServiceProvider);
  return NotificationSyncService(dio, crypto);
});

class NotificationSyncService {
  final Dio _dio;
  final CryptoService _crypto;

  static const _methodChannel = MethodChannel('com.example.financial_clarity/notification_settings');
  static const _eventChannel = EventChannel('com.example.financial_clarity/notification_stream');

  StreamSubscription? _subscription;

  NotificationSyncService(this._dio, this._crypto);

  /// Checks if Android Notification Access permission is granted to the app.
  Future<bool> hasPermission() async {
    try {
      final bool has = await _methodChannel.invokeMethod('checkPermission') ?? false;
      return has;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system Notification Access settings panel.
  Future<void> openSettings() async {
    try {
      await _methodChannel.invokeMethod('openSettings');
    } catch (_) {}
  }

  /// Starts listening to real-time notification streams from PhonePe, Google Pay, and Paytm.
  void startListening(Function(String message) onSyncSuccess) {
    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final packageName = event['packageName'] as String? ?? '';
        final title = event['title'] as String? ?? '';
        final text = event['text'] as String? ?? '';
        final timestamp = event['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        _processNotification(packageName, title, text, timestamp, onSyncSuccess);
      }
    });
  }

  /// Disconnects the listener from the native event stream.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _processNotification(
    String packageName,
    String title,
    String text,
    int timestampMs,
    Function(String message) onSyncSuccess,
  ) async {
    // 1. Extract amount using standard regex (e.g. ₹450 or Rs. 100)
    final amountReg = RegExp(r'(?:₹|Rs\.?)\s*([0-9,]+(?:\.[0-9]+)?)');
    final match = amountReg.firstMatch(text);
    if (match == null) return;

    final amountStr = match.group(1)?.replaceAll(',', '') ?? '0';
    final amount = double.tryParse(amountStr) ?? 0.0;
    if (amount <= 0) return;

    // 2. Extract vendor/recipient name
    String vendor = 'Unknown Merchant';
    final vendorRegs = [
      RegExp(r'(?:paid|sent|transfer to|Paid|Sent|transferred)\s+(?:₹|Rs\.?)\s*[0-9,.]+\s+to\s+([^.]+)', caseSensitive: false),
      RegExp(r'(?:Received|received|added)\s+(?:₹|Rs\.?)\s*[0-9,.]+\s+from\s+([^.]+)', caseSensitive: false),
    ];

    for (var reg in vendorRegs) {
      final vMatch = reg.firstMatch(text);
      if (vMatch != null) {
        vendor = vMatch.group(1)?.trim() ?? 'Unknown Merchant';
        // Capitalize vendor name for cleaner feed rendering
        if (vendor.isNotEmpty) {
          vendor = vendor[0].toUpperCase() + vendor.substring(1);
        }
        break;
      }
    }

    // 3. Classify transaction as debit or credit
    final isDebit = !text.toLowerCase().contains('received') &&
        !text.toLowerCase().contains('added') &&
        !text.toLowerCase().contains('credited');

    // 4. Assign categories based on keywords
    String category = 'other';
    final lowerText = text.toLowerCase();
    if (lowerText.contains('swiggy') || lowerText.contains('zomato') || lowerText.contains('food') || lowerText.contains('restaurant')) {
      category = 'food';
    } else if (lowerText.contains('uber') || lowerText.contains('ola') || lowerText.contains('fuel') || lowerText.contains('petrol') || lowerText.contains('travel')) {
      category = 'transport';
    } else if (lowerText.contains('netflix') || lowerText.contains('spotify') || lowerText.contains('prime') || lowerText.contains('movie')) {
      category = 'entertainment';
    } else if (lowerText.contains('bill') || lowerText.contains('recharge') || lowerText.contains('electricity') || lowerText.contains('wifi')) {
      category = 'bills';
    }

    final isoTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs).toUtc().toIso8601String();

    // 5. Create transaction sync payload and encrypt it
    final plainPayload = {
      'vendor': vendor,
      'amount': amount,
      'is_debit': isDebit,
      'category': category,
      'description': 'Real-time sync from $packageName',
      'timestamp': isoTimestamp,
    };

    final encrypted = _crypto.encryptPayload(plainPayload);

    // 6. Deliver to backend sync endpoint
    try {
      final response = await _dio.post('/transactions/sync', data: {
        'payload': encrypted,
        'source_app': _getSourceAppName(packageName),
        'device_id': 'android_device_active',
      });

      if (response.statusCode == 201 && response.data['success'] == true) {
        onSyncSuccess('Real-time sync: ${isDebit ? "Spent" : "Received"} ₹$amount at $vendor');
      }
    } catch (_) {
      // Suppress network errors in background service
    }
  }

  String _getSourceAppName(String pkg) {
    if (pkg.contains('phonepe')) return 'phonepe';
    if (pkg.contains('nbu.paisa')) return 'gpay';
    if (pkg.contains('paytm')) return 'paytm';
    return 'other';
  }
}
