/// GoRouter configuration for Financial Clarity.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/risk_assessment/presentation/risk_assessment_screen.dart';
import '../features/transactions/presentation/transaction_feed_screen.dart';
import '../features/budgets/presentation/budget_screen.dart';
import '../features/investment_advisor/presentation/advisor_screen.dart';
import '../features/portfolio/presentation/portfolio_screen.dart';
import '../features/auth/presentation/profile_screen.dart';
import '../shared/widgets/app_scaffold.dart';
import '../features/human_advisors/presentation/advisor_discovery_screen.dart';
import '../features/human_advisors/presentation/advisor_profile_screen.dart';
import '../features/human_advisors/presentation/call_connecting_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    routes: [
      // ── Auth (no bottom nav) ──────────────────────────
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/risk-assessment',
        builder: (context, state) => const RiskAssessmentScreen(),
      ),
      GoRoute(
        path: '/advisors',
        builder: (context, state) => const AdvisorDiscoveryScreen(),
      ),
      GoRoute(
        path: '/advisors/:id',
        builder: (context, state) => AdvisorProfileScreen(
          advisorId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/advisors/:id/call',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return CallConnectingScreen(
            advisorId: state.pathParameters['id']!,
            advisorName: extra['name'] as String? ?? 'Advisor',
            sessionId: extra['session_id'] as String? ?? '',
            maskedNumber: extra['masked_number'] as String? ?? '',
          );
        },
      ),

      // ── Main App Shell (with bottom nav) ──────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return AppScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TransactionFeedScreen(),
            ),
          ),
          GoRoute(
            path: '/budgets',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BudgetScreen(),
            ),
          ),
          GoRoute(
            path: '/advisor',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AdvisorScreen(),
            ),
          ),
          GoRoute(
            path: '/portfolio',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PortfolioScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
