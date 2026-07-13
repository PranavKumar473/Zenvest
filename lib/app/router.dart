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
import '../features/advisor_dashboard/presentation/advisor_requests_screen.dart';
import '../features/advisor_dashboard/presentation/my_investors_screen.dart';
import '../features/advisor_dashboard/presentation/advisor_earnings_screen.dart';
import '../features/advisor_dashboard/presentation/investor_portfolio_detail_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/advisor_onboarding/presentation/advisor_onboarding_screen.dart';
import '../features/human_advisors/presentation/subscription_checkout_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshNotifier(ref),
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.uri.path;
      final isAuthenticated = authState.status == AuthStatus.authenticated;
      final isAdvisor = authState.userType == 'advisor';
      final isOnLogin = location == '/login';

      // If not authenticated, allow login/register pages only
      if (!isAuthenticated) {
        return isOnLogin ? null : '/login';
      }

      final homeRoute = isAdvisor
          ? (authState.onboardingCompleted ? '/advisor-requests' : '/advisor-onboarding')
          : (authState.onboardingCompleted ? '/dashboard' : '/onboarding');

      // If authenticated and on login page, redirect based on role/onboarding state
      if (isOnLogin) {
        return homeRoute;
      }

      // Advisors must finish PAN/address/GST/INA verification before reaching
      // the dashboard — mirrors the investor onboarding gate.
      if (isAdvisor && !authState.onboardingCompleted && location != '/advisor-onboarding') {
        return '/advisor-onboarding';
      }

      // If advisor is on an investor-only route, redirect to advisor dashboard
      if (isAdvisor && (location == '/dashboard' || location == '/budgets' || location == '/advisor' || location == '/portfolio')) {
        return homeRoute;
      }

      return null; // no redirect
    },
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
        path: '/advisor-onboarding',
        builder: (context, state) => const AdvisorOnboardingScreen(),
      ),
      GoRoute(
        path: '/advisors/:id/subscribe',
        builder: (context, state) => SubscriptionCheckoutScreen(
          advisorId: state.pathParameters['id']!,
        ),
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
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatScreen(
            requestId: state.pathParameters['id']!,
            peerName: extra['name'] as String? ?? 'Client',
          );
        },
      ),
      GoRoute(
        path: '/my-investors/:investorId/portfolio',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return InvestorPortfolioDetailScreen(
            investorId: state.pathParameters['investorId']!,
            investorName: extra['name'] as String? ?? 'Investor',
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
          // Advisor Tab Routes
          GoRoute(
            path: '/advisor-requests',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AdvisorRequestsScreen(),
            ),
          ),
          GoRoute(
            path: '/my-investors',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MyInvestorsScreen(),
            ),
          ),
          GoRoute(
            path: '/earnings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AdvisorEarningsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});

/// A [ChangeNotifier] that listens to auth state changes and notifies
/// GoRouter to re-evaluate its redirect.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) {
      notifyListeners();
    });
  }
}
