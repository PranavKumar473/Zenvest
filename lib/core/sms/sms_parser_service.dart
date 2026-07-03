/// SmsParserService — Reads device SMS inbox and extracts UPI/bank transactions.
/// Only runs on Android. Returns nothing on iOS (SMS reading blocked by Apple).
/// Does NOT connect to any external servers. Only reads local device SMS.
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a single parsed transaction ready to send to our backend.
class ParsedTransaction {
  final String vendor;
  final double amount;
  final bool isDebit;
  final String category;
  final String source;      // e.g. "phonepe", "gpay", "paytm", "bank_sms"
  final DateTime timestamp;
  final String rawSmsBody;  // kept for debugging, never sent to server

  const ParsedTransaction({
    required this.vendor,
    required this.amount,
    required this.isDebit,
    required this.category,
    required this.source,
    required this.timestamp,
    required this.rawSmsBody,
  });
}

class SmsParserService {
  // ── Known sender address fragments that contain transaction SMSes ──────────
  // These are the alphanumeric sender IDs banks and UPI apps use.
  // Android shows these in the "From" field of an SMS.
  static const List<String> _knownSenders = [
    'PHONEPE', 'PHPE',
    'GPAY',
    'PAYTM', 'PYTM',
    'HDFCBK', 'HDFC',
    'ICICIB', 'ICICI',
    'SBINB', 'SBIBNK', 'SBI',
    'AXISBK', 'AXIS',
    'KOTAKB', 'KOTAK',
    'INDUSB', 'INDUS',
    'PNBSMS', 'PNB',
    'BOIIND', 'BOI',
    'YESBNK', 'YES',
    'IDFCBK', 'IDFC',
    'AUBANK', 'RBLBNK',
    'JUSPAY', 'RAZORPAY',
    'AMAZON', 'FLIPKRT',
    'UPI',
  ];

  // ── Category keyword map ──────────────────────────────────────────────────
  // Vendor names extracted from SMS are matched against these keywords.
  // Order matters: first match wins.
  static const Map<String, List<String>> _categoryKeywords = {
    'food': [
      'swiggy', 'zomato', 'dominos', 'pizza', 'mcdonald', 'kfc', 'burger',
      'restaurant', 'cafe', 'dhaba', 'blinkit', 'zepto', 'bigbasket',
      'grocer', 'kirana', 'hotel', 'food', 'canteen', 'mess', 'diner',
      'haldiram', 'subway', 'dunkin',
    ],
    'transport': [
      'uber', 'ola', 'rapido', 'namma', 'yulu', 'metro', 'irctc', 'railway',
      'bus', 'petrol', 'fuel', 'diesel', 'toll', 'fastag', 'parking',
      'cab', 'auto', 'rickshaw', 'flight', 'indigo', 'air india', 'spicejet',
    ],
    'shopping': [
      'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'snapdeal',
      'shop', 'mart', 'store', 'mall', 'retail', 'reliance', 'dmart',
      'big bazaar', 'croma', 'jiomart', 'lenskart', 'firstcry',
    ],
    'bills': [
      'electricity', 'bescom', 'msedcl', 'tsspdcl', 'water', 'gas', 'lpg',
      'jio', 'airtel', 'bsnl', 'vodafone', 'vi', 'broadband', 'recharge',
      'lic', 'insurance', 'emi', 'loan', 'rent', 'maintenance',
      'tatasky', 'dthdish', 'netflix', 'subscription', 'premium',
    ],
    'health': [
      'pharmacy', 'medplus', 'netmeds', '1mg', 'apollo', 'hospital',
      'clinic', 'doctor', 'diagnostic', 'lab', 'pathology', 'dental',
      'optician', 'medicine', 'pharma', 'health',
    ],
    'entertainment': [
      'bookmyshow', 'pvr', 'inox', 'cinepolis', 'game', 'steam',
      'playstation', 'xbox', 'event', 'concert', 'theatre', 'comedy',
      'spotify', 'youtube', 'hotstar', 'disney',
    ],
  };

  // ── Detect which UPI source sent the SMS ─────────────────────────────────
  static String _detectSource(String senderAddress, String body) {
    final s = senderAddress.toUpperCase();
    final b = body.toLowerCase();
    if (s.contains('PHONEPE') || s.contains('PHPE') || b.contains('phonepe')) return 'phonepe';
    if (s.contains('GPAY') || b.contains('google pay') || b.contains('gpay')) return 'gpay';
    if (s.contains('PAYTM') || s.contains('PYTM') || b.contains('paytm')) return 'paytm';
    if (s.contains('AMAZON') || b.contains('amazon pay')) return 'amazon_pay';
    return 'bank_sms';
  }

  // ── Extract amount from SMS body ──────────────────────────────────────────
  static double? _extractAmount(String body) {
    // Matches: Rs.500, Rs 1,200, INR500, ₹1200.50, INR 50,000
    final patterns = [
      RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false),
      RegExp(r'([\d,]+(?:\.\d{1,2})?)\s*(?:Rs\.?|INR|₹)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final raw = match.group(1)!.replaceAll(',', '');
        return double.tryParse(raw);
      }
    }
    return null;
  }

  // ── Determine debit or credit ─────────────────────────────────────────────
  static bool _isDebit(String body) {
    final lower = body.toLowerCase();
    // Credit indicators (money coming IN)
    final creditWords = [
      'credited', 'received', 'refund', 'cashback', 'added to',
      'deposited', 'credit of', 'amount added',
    ];
    for (final word in creditWords) {
      if (lower.contains(word)) return false;
    }
    // Default to debit (money going OUT) — most transaction SMSes are debits
    return true;
  }

  // ── Extract vendor/merchant name ──────────────────────────────────────────
  static String _extractVendor(String body, String source) {
    final lower = body.toLowerCase();

    // Pattern: "to [VPA/merchant name]" — used by most UPI apps
    final toPattern = RegExp(
      r'(?:to|paid to|sent to|transferred to)\s+([a-zA-Z0-9@._\- ]{2,40})',
      caseSensitive: false,
    );
    // Pattern: "at [merchant]" — used by card transactions
    final atPattern = RegExp(
      r'(?:at|spent at|used at)\s+([a-zA-Z0-9 ]{2,40})',
      caseSensitive: false,
    );
    // Pattern: "from [sender]" — for credits
    final fromPattern = RegExp(
      r'(?:from|received from)\s+([a-zA-Z0-9@._\- ]{2,40})',
      caseSensitive: false,
    );

    for (final pattern in [toPattern, atPattern, fromPattern]) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        var name = match.group(1)!.trim();
        // Remove trailing common words that are not the merchant name
        name = name
            .replaceAll(RegExp(r'\s*(on|via|using|through|for|ref|txn|utr).*', caseSensitive: false), '')
            .trim();
        if (name.length >= 2) {
          // Title-case the name
          return name.split(' ')
              .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
              .join(' ');
        }
      }
    }

    // Fallback: use the source label as vendor
    const sourceLabels = {
      'phonepe': 'PhonePe Payment',
      'gpay': 'Google Pay',
      'paytm': 'Paytm Payment',
      'amazon_pay': 'Amazon Pay',
      'bank_sms': 'Bank Transaction',
    };
    return sourceLabels[source] ?? 'Unknown Merchant';
  }

  // ── Auto-categorise based on vendor text ─────────────────────────────────
  static String _autoCategory(String vendor, String body) {
    final text = '${vendor.toLowerCase()} ${body.toLowerCase()}';
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (text.contains(keyword)) return entry.key;
      }
    }
    return 'other';
  }

  // ── Check if this SMS looks like a financial transaction ──────────────────
  static bool _isTransactionSms(String body) {
    final lower = body.toLowerCase();
    
    // Reject OTP messages
    if (lower.contains('otp') || lower.contains('one time password') ||
        lower.contains('do not share')) return false;

    // Must contain a money keyword
    final hasAmount = lower.contains('rs.') || lower.contains('rs ') ||
        lower.contains('inr') || lower.contains('₹');
    // Must contain a transaction verb
    final hasVerb = lower.contains('debit') || lower.contains('credit') ||
        lower.contains('paid') || lower.contains('sent') ||
        lower.contains('received') || lower.contains('transferred') ||
        lower.contains('spent') || lower.contains('payment');
    return hasAmount && hasVerb;
  }

  // ── MAIN PUBLIC METHOD ────────────────────────────────────────────────────

  /// Request SMS permission and parse inbox transactions.
  /// Returns empty list on iOS (SMS reading not permitted by Apple).
  /// Returns empty list if user denies permission.
  Future<SmsParseResult> parseSmsTransactions() async {
    // iOS & Web: SMS reading is not permitted.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SmsParseResult(
        transactions: [],
        permissionDenied: false,
        isPlatformUnsupported: true,
        newCount: 0,
        skippedCount: 0,
      );
    }

    // Step 1: Check and request READ_SMS permission
    var status = await Permission.sms.status;
    if (status.isDenied || status.isRestricted) {
      status = await Permission.sms.request();
    }

    if (!status.isGranted) {
      // User declined permission — return early with flag
      return const SmsParseResult(
        transactions: [],
        permissionDenied: true,
        isPlatformUnsupported: false,
        newCount: 0,
        skippedCount: 0,
      );
    }

    // Step 2: Load already-synced SMS IDs from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = Set<String>.from(prefs.getStringList('synced_sms_ids') ?? []);

    // Step 3: Query SMS inbox — last 90 days
    final query = SmsQuery();
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final allMessages = await query.querySms(
      kinds: [SmsQueryKind.inbox],
      count: 500,  // read up to 500 recent messages
    );

    // Step 4: Filter, parse, and deduplicate
    final parsed = <ParsedTransaction>[];
    final newSyncedIds = <String>{};
    int skippedCount = 0;

    for (final sms in allMessages) {
      // Skip if already synced
      final smsId = sms.id?.toString() ?? '';
      if (smsId.isNotEmpty && syncedIds.contains(smsId)) {
        skippedCount++;
        continue;
      }

      // Skip if older than 90 days
      final date = sms.date;
      if (date == null || date.isBefore(cutoff)) continue;

      // Skip if sender is not a known bank/UPI sender
      final sender = (sms.address ?? '').toUpperCase();
      final isKnownSender = _knownSenders.any((s) => sender.contains(s));
      if (!isKnownSender) continue;

      final body = sms.body ?? '';

      // Skip if SMS doesn't look like a transaction
      if (!_isTransactionSms(body)) continue;

      // Extract fields
      final amount = _extractAmount(body);
      if (amount == null || amount <= 0) continue;  // skip if no valid amount

      final isDebit = _isDebit(body);
      final source = _detectSource(sender, body);
      final vendor = _extractVendor(body, source);
      final category = _autoCategory(vendor, body);

      parsed.add(ParsedTransaction(
        vendor: vendor,
        amount: amount,
        isDebit: isDebit,
        category: category,
        source: source,
        timestamp: date,
        rawSmsBody: body,  // for local debug only — not sent to server
      ));

      if (smsId.isNotEmpty) newSyncedIds.add(smsId);
    }

    // Step 5: Persist the new synced IDs so we don't re-import next time
    final allSyncedIds = {...syncedIds, ...newSyncedIds}.toList();
    // Keep only the most recent 2000 IDs to prevent unbounded growth
    if (allSyncedIds.length > 2000) allSyncedIds.removeRange(0, allSyncedIds.length - 2000);
    await prefs.setStringList('synced_sms_ids', allSyncedIds);

    return SmsParseResult(
      transactions: parsed,
      permissionDenied: false,
      isPlatformUnsupported: false,
      newCount: parsed.length,
      skippedCount: skippedCount,
    );
  }
}

/// Result object returned by parseSmsTransactions()
class SmsParseResult {
  final List<ParsedTransaction> transactions;
  final bool permissionDenied;       // true if user said "Deny" to SMS permission
  final bool isPlatformUnsupported;  // true on iOS
  final int newCount;                // how many new transactions were found
  final int skippedCount;            // how many were skipped (already synced)

  const SmsParseResult({
    required this.transactions,
    required this.permissionDenied,
    required this.isPlatformUnsupported,
    required this.newCount,
    required this.skippedCount,
  });
}
