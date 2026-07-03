/// Local push notification service for budget warnings.
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the notification plugin with platform-specific settings.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _initialized = true;
  }

  /// Show a budget warning notification.
  Future<void> showBudgetWarning({
    required String category,
    required int threshold,
    required double spentPercentage,
    required double remainingAmount,
  }) async {
    final isUrgent = threshold >= 85;

    final title = isUrgent
        ? '🚨 Budget Alert: $category'
        : '⚠️ Budget Warning: $category';

    final body = isUrgent
        ? 'You\'ve spent ${spentPercentage.toStringAsFixed(0)}% of your $category budget! '
            'Only ₹${remainingAmount.toStringAsFixed(0)} remaining.'
        : 'You\'ve used ${spentPercentage.toStringAsFixed(0)}% of your $category budget. '
            '₹${remainingAmount.toStringAsFixed(0)} left this month.';

    await _plugin.show(
      category.hashCode + threshold,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'budget_warnings',
          'Budget Warnings',
          channelDescription: 'Alerts when spending approaches budget limits',
          importance: isUrgent ? Importance.high : Importance.defaultImportance,
          priority: isUrgent ? Priority.high : Priority.defaultPriority,
          color: isUrgent
              ? const Color(0xFFC0392B)
              : const Color(0xFFC9992F),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: isUrgent,
          interruptionLevel: isUrgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
    );
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    // Navigation to budget screen handled by GoRouter deep linking
  }
}

