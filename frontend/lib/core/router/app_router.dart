import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/auth/presentation/terms_page.dart';
import '../../features/auth/presentation/privacy_page.dart';
import '../../features/onboarding/presentation/landing_page.dart';
import '../../features/onboarding/presentation/about_page.dart';
import '../../features/dashboard/presentation/dashboard_wrapper.dart';
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
        path: LandingPage.routePath,
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: LoginPage.routePath,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: SignupPage.routePath,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: TermsPage.routePath,
        builder: (context, state) => const TermsPage(),
      ),
      GoRoute(
        path: PrivacyPage.routePath,
        builder: (context, state) => const PrivacyPage(),
      ),
      GoRoute(
        path: AboutPage.routePath,
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: DashboardWrapper.routePath,
        builder: (context, state) => const DashboardWrapper(),
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
        builder: (context, state) {
          String? riskLevel;
          int? age;

          final extra = state.extra;
          if (extra is String) {
            riskLevel = extra;
          } else if (extra is Map<String, dynamic>) {
            riskLevel = extra['risk_level']?.toString();
            age = int.tryParse(extra['age']?.toString() ?? '');
          }

          return TasksPage(
            riskLevel: riskLevel,
            age: age,
          );
        },
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

