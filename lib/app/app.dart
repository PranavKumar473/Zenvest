/// Financial Clarity — MaterialApp configuration.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'router.dart';
import '../core/security/app_lock_overlay.dart';

class FinancialClarityApp extends ConsumerWidget {
  const FinancialClarityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Financial Clarity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        return AppLockOverlay(child: child ?? const SizedBox());
      },
    );
  }
}
