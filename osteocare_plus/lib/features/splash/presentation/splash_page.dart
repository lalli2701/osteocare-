import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/presentation/landing_page.dart';
import '../../dashboard/presentation/dashboard_wrapper.dart';
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
    await Future<void>.delayed(const Duration(seconds: 2));

    final isLoggedIn = await AuthService.instance.isLoggedIn();

    if (!mounted) return;

    if (isLoggedIn) {
      context.go(DashboardWrapper.routePath);
    } else {
      context.go(LandingPage.routePath);
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
    final isWide = size.width >= 900;
    final logoWidth = isWide ? 220.0 : (size.width * 0.52);

    Widget splashPanel = Container(
      margin: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 16,
        vertical: isWide ? 18 : 22,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6EA0F1),
            Color(0xFF5F91E6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(
                  'assets/ossopulse_logo.jpeg',
                  width: logoWidth > 340 ? 300 : (logoWidth - 40),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _visibleTagline,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFEAF2FF),
              Color(0xFFF6FAFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: isWide
              ? Row(
                  children: [
                    Expanded(flex: 46, child: splashPanel),
                    const Expanded(flex: 54, child: SizedBox.shrink()),
                  ],
                )
              : splashPanel,
        ),
      ),
    );
  }
}

