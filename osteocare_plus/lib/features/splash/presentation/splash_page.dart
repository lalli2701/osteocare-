import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/login_page.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../../core/auth/auth_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const routePath = '/';

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const String _tagline = 'Bone Health Made Simple';
  String _visibleTagline = '';
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTypingAnimation();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future<void>.delayed(const Duration(seconds: 1));

    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    if (isLoggedIn) {
      // Load profile into our in-memory session for convenience.
      await AuthService.instance.loadCurrentUserIfAny();
    }

    if (!mounted) return;

    if (isLoggedIn) {
      context.go(DashboardPage.routePath);
    } else {
      context.go(LoginPage.routePath);
    }
  }

  void _startTypingAnimation() {
    Future.doWhile(() async {
      if (!mounted || _currentIndex >= _tagline.length) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return false;
      setState(() {
        _currentIndex++;
        _visibleTagline = _tagline.substring(0, _currentIndex);
      });
      return _currentIndex < _tagline.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoWidth = size.width * 0.55; // ~55% of screen width

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFE3F2FF),
              Color(0xFFF5FAFF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/osteocare_logo.jpeg',
                width: logoWidth > 340 ? 340 : logoWidth,
              ),
              const SizedBox(height: 16),
              Text(
                _visibleTagline,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

