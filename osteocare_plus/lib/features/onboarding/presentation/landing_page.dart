import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  static const routePath = '/landing';

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  FlutterTts? _flutterTts;
  bool _ttsReady = false;
  bool _isSpeaking = false;
  bool _isPaused = false;

  static const String _voiceScript = '''Hello and welcome to OsteoCare Plus.

This application helps you understand your osteoporosis risk level in a simple and clear manner.

Please note carefully, this app does not diagnose osteoporosis and it does not replace consultation with a qualified medical professional. It only provides an AI-based risk assessment for awareness purposes.

We collect basic information such as your age, gender, lifestyle habits, and certain medical history details. These inputs are used only to calculate your personalized risk score.

Your data is kept secure and is not sold to any third party.

Let me briefly explain how the app works.

Step one: Create your account using your phone number.

Step two: Enter your health and lifestyle details.

Step three: Our machine learning model analyses your information.

Step four: You receive your risk category — Low, Moderate, or High.

Step five: You get personalized recommendations and reminder notifications to support your bone health.

Osteoporosis affects over 1.5 crore people worldwide. One in three women and one in five men above the age of fifty are at risk.

It is always better to be aware early and take preventive steps.

To continue, please select Sign Up if you are new, or Login if you already have an account.

Thank you for choosing OsteoCare Plus.''';

  Future<void> _initTts() async {
    if (_ttsReady) return;
    _flutterTts = FlutterTts();
    final tts = _flutterTts!;

    await tts.setLanguage('en-IN');
    await tts.setSpeechRate(0.42);
    await tts.setPitch(1.0);

    tts.setStartHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    });

    tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    });

    tts.setCancelHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    });

    tts.setErrorHandler((_) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    });

    _ttsReady = true;
  }

  Future<void> _playOverview() async {
    await _initTts();
    final tts = _flutterTts;
    if (tts == null) return;
    await tts.stop();
    await tts.speak(_voiceScript);
  }

  Future<void> _pauseOverview() async {
    final tts = _flutterTts;
    if (tts == null) return;
    await tts.pause();
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      _isPaused = true;
    });
  }

  Future<void> _stopOverview() async {
    final tts = _flutterTts;
    if (tts == null) return;
    await tts.stop();
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      _isPaused = false;
    });
  }

  @override
  void dispose() {
    _flutterTts?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0A1929),
              const Color(0xFF132F4C),
              const Color(0xFF1A3A52),
              const Color(0xFF0D2438),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Text(
                      'OsteoCare+',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: const Color(0xFF00D9A3),
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF00D9A3).withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AI-Based Osteoporosis Risk Screening',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 100),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D9A3).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00D9A3).withValues(alpha: 0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D9A3).withValues(alpha: 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Text(
                        'Early risk awareness supports preventive care and helps reduce fracture complications.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    Center(
                      child: SizedBox(
                        width: 235,
                        child: _darkGradientButton(
                          label: 'Create Account',
                          onPressed: () => context.push('/signup'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        width: 165,
                        child: OutlinedButton(
                          onPressed: () => context.push('/login'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFF00D9A3),
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF00D9A3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 38),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00D9A3).withValues(alpha: 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D9A3).withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.record_voice_over, color: Color(0xFF00D9A3)),
                              const SizedBox(width: 10),
                              Text(
                                'Tap to Hear Overview',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Voice guidance available for accessibility.',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _controlButton(
                                label: 'Play',
                                icon: Icons.play_arrow_rounded,
                                enabled: true,
                                filled: true,
                                onTap: _playOverview,
                              ),
                              _controlButton(
                                label: 'Pause',
                                icon: Icons.pause,
                                enabled: _isSpeaking,
                                filled: false,
                                onTap: _pauseOverview,
                              ),
                              _controlButton(
                                label: 'Stop',
                                icon: Icons.stop,
                                enabled: _isSpeaking || _isPaused,
                                filled: false,
                                onTap: _stopOverview,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                    Text(
                      'Why We Ask for Your Details',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _simpleTile(
                      'We collect age, gender, lifestyle habits, and medical history only for risk assessment.',
                    ),
                    _simpleTile(
                      'This app gives AI-based risk assessment for awareness purposes; it is not a diagnosis tool.',
                    ),
                    _simpleTile(
                      'Always consult a qualified doctor for diagnosis and treatment decisions.',
                    ),
                    _simpleTile(
                      'Your data is stored securely and is never sold to third parties.',
                    ),
                    const SizedBox(height: 34),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFFED6C02).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFED6C02).withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFED6C02).withValues(alpha: 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_rounded, color: Color(0xFFED6C02)),
                              const SizedBox(width: 10),
                              Text(
                                'Medical Disclaimer',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'This app does not provide medical diagnosis. Results are algorithm-based risk estimates. Always consult a licensed doctor for medical advice, diagnosis, and treatment decisions.',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      'How App Works',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _flowStep(1, 'Create account with phone number.'),
                    _flowStep(2, 'Enter health and lifestyle details.'),
                    _flowStep(3, 'Model analyses your information.'),
                    _flowStep(4, 'See risk category: Low / Moderate / High.'),
                    _flowStep(5, 'Get recommendations and reminders.'),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 54,
                      runSpacing: 14,
                      alignment: WrapAlignment.center,
                      children: [
                        _stat('1.5L+', 'People Affected Worldwide', const Color(0xFF00D9A3)),
                        _stat('1 in 3', 'Women Over 50', const Color(0xFFC8A028)),
                        _stat('1 in 5', 'Men Over 50', const Color(0xFF1AAFD3)),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Center(
                      child: Wrap(
                        spacing: 10,
                        children: [
                          _footerLink('Terms', () => context.push('/terms')),
                          Text('•', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
                          _footerLink('Privacy', () => context.push('/privacy')),
                          Text('•', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
                          _footerLink('Contact', () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Contact: support@osteocare.app')),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'OsteoCare+ v1.0.0',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _simpleTile(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D9A3).withValues(alpha: 0.2)),
        color: Colors.white.withValues(alpha: 0.03),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.78),
          height: 1.45,
        ),
      ),
    );
  }

  Widget _flowStep(int index, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00D9A3), Color(0xFF00B599)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D9A3).withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.65),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _footerLink(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: const Color(0xFF00D9A3),
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _darkGradientButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9A3).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00D9A3),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool filled,
    required Future<void> Function() onTap,
  }) {
    final background = filled ? const Color(0xFF00D9A3) : Colors.transparent;
    final borderColor = filled
        ? const Color(0xFF00D9A3)
        : const Color(0xFF00D9A3).withValues(alpha: 0.28);
    final foreground = filled
        ? Colors.white
        : Colors.white.withValues(alpha: enabled ? 0.7 : 0.35);

    return InkWell(
      onTap: enabled ? () => onTap() : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1.4),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: const Color(0xFF00D9A3).withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: foreground),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
