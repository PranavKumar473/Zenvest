import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../features/auth/presentation/auth_controller.dart';

class AppScaffold extends ConsumerWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  // --- Investor Tabs ---
  static const _investorDestinations = [
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Transactions',
    ),
    NavigationDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: 'Budgets',
    ),
    NavigationDestination(
      icon: Icon(Icons.lightbulb_outline),
      selectedIcon: Icon(Icons.lightbulb),
      label: 'Robo-Advisor',
    ),
    NavigationDestination(
      icon: Icon(Icons.analytics_outlined),
      selectedIcon: Icon(Icons.analytics),
      label: 'Portfolio',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  static const _investorRoutes = [
    '/dashboard',
    '/budgets',
    '/advisor',
    '/portfolio',
    '/profile',
  ];

  // --- Advisor Tabs ---
  static const _advisorDestinations = [
    NavigationDestination(
      icon: Icon(Icons.question_answer_outlined),
      selectedIcon: Icon(Icons.question_answer),
      label: 'Requests',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_alt_outlined),
      selectedIcon: Icon(Icons.people_alt),
      label: 'My Investors',
    ),
    NavigationDestination(
      icon: Icon(Icons.monetization_on_outlined),
      selectedIcon: Icon(Icons.monetization_on),
      label: 'Earnings',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  static const _advisorRoutes = [
    '/advisor-requests',
    '/my-investors',
    '/earnings',
    '/profile',
  ];

  int _currentIndex(BuildContext context, List<String> routes) {
    final location = GoRouterState.of(context).uri.path;
    final index = routes.indexWhere((r) => location.startsWith(r));
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isAdvisor = authState.userType == 'advisor';

    final destinations = isAdvisor ? _advisorDestinations : _investorDestinations;
    final routes = isAdvisor ? _advisorRoutes : _investorRoutes;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex(context, routes),
          onDestinationSelected: (index) {
            context.go(routes[index]);
          },
          destinations: destinations,
          height: 72,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
    );
  }
}
