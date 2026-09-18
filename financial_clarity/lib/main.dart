/// Financial Clarity — Application Entry Point.
///
/// Initializes the ProviderScope, notification service, and error handlers
/// before launching the app.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/notifications/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  await NotificationService().initialize();

  // Global error handling
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  runApp(
    const ProviderScope(
      child: FinancialClarityApp(),
    ),
  );
}
