import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/onboarding/presentation/about_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/survey/presentation/survey_page.dart';
import '../../features/survey/presentation/result_page.dart';
import '../../features/dashboard/presentation/tasks_page.dart';
import '../../features/chatbot/presentation/chatbot_page.dart';
import '../../features/splash/presentation/splash_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: SplashPage.routePath,
    routes: [
      GoRoute(
        path: SplashPage.routePath,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: LoginPage.routePath,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AboutPage.routePath,
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: DashboardPage.routePath,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: SurveyPage.routePath,
        builder: (context, state) => const SurveyPage(),
      ),
      GoRoute(
        path: ResultPage.routePath,
        builder: (context, state) => ResultPage(
          result: state.extra,
        ),
      ),
      GoRoute(
        path: TasksPage.routePath,
        builder: (context, state) => TasksPage(
          riskLevel: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: ChatbotPage.routePath,
        builder: (context, state) => const ChatbotPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri.toString()}'),
      ),
    ),
  );
});

