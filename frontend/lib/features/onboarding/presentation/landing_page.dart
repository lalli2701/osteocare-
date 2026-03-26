import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/services/language_service.dart';

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
  bool _hasAutoPlayed = false;

  Future<void> _initTts() async {
    if (_ttsReady) return;
    _flutterTts = FlutterTts();
    final tts = _flutterTts!;

    final language = AppLanguage.fromCode(context.locale.languageCode);
    await tts.setLanguage(LanguageService.getTTSLanguageCode(language));
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

  @override
  void initState() {
    super.initState();
    // Auto-play voice overview once
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_hasAutoPlayed && mounted) {
        _hasAutoPlayed = true;
        _playOverview();
      }
    });
  }

  Future<void> _playOverview() async {
    await _initTts();
    final tts = _flutterTts;
    if (tts == null) return;
    final language = AppLanguage.fromCode(context.locale.languageCode);
    await tts.setLanguage(LanguageService.getTTSLanguageCode(language));
    await tts.stop();
    await tts.speak('voice_script'.tr());
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
      body: Stack(
        children: [
          Container(
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
                      'landing_tagline'.tr(),
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
                        'landing_early_awareness'.tr(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    // Language Selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D9A3).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00D9A3).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'select_language'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _languageButton(
                                label: 'english'.tr(),
                                locale: const Locale('en'),
                                isSelected: context.locale.languageCode == 'en',
                              ),
                              _languageButton(
                                label: 'hindi'.tr(),
                                locale: const Locale('hi'),
                                isSelected: context.locale.languageCode == 'hi',
                              ),
                              _languageButton(
                                label: 'telugu'.tr(),
                                locale: const Locale('te'),
                                isSelected: context.locale.languageCode == 'te',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: SizedBox(
                        width: 235,
                        child: _darkGradientButton(
                          label: 'create_account'.tr(),
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
                          child: Text(
                            'sign_in'.tr(),
                            style: const TextStyle(
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
                                'landing_tap_overview'.tr(),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'landing_voice_guidance'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Voice controls are now floating at bottom-right
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                    Text(
                      'landing_why_details'.tr(),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _simpleTile(
                      'landing_detail_1'.tr(),
                    ),
                    _simpleTile(
                      'landing_detail_2'.tr(),
                    ),
                    _simpleTile(
                      'landing_detail_3'.tr(),
                    ),
                    _simpleTile(
                      'landing_detail_4'.tr(),
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
                                'landing_medical_disclaimer'.tr(),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'landing_medical_disclaimer_text'.tr(),
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
                      'landing_how_it_works'.tr(),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _flowStep(1, 'landing_step_1'.tr()),
                    _flowStep(2, 'landing_step_2'.tr()),
                    _flowStep(3, 'landing_step_3'.tr()),
                    _flowStep(4, 'landing_step_4'.tr()),
                    _flowStep(5, 'landing_step_5'.tr()),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 54,
                      runSpacing: 14,
                      alignment: WrapAlignment.center,
                      children: [
                        _stat('1.5L+', 'landing_stat_people'.tr(), const Color(0xFF00D9A3)),
                        _stat('1 in 3', 'landing_stat_women'.tr(), const Color(0xFFC8A028)),
                        _stat('1 in 5', 'landing_stat_men'.tr(), const Color(0xFF1AAFD3)),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Center(
                      child: Wrap(
                        spacing: 10,
                        children: [
                          _footerLink('terms'.tr(), () => context.push('/terms')),
                          Text('•', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
                          _footerLink('privacy_policy'.tr(), () => context.push('/privacy')),
                          Text('•', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
                          _footerLink('contact'.tr(), () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('landing_contact_snackbar'.tr())),
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
          // Floating Voice Controller
          Positioned(
            bottom: 80,
            right: 20,
            child: _buildFloatingVoiceController(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingVoiceController() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.black87,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF00D9A3).withValues(alpha: 0.3),
            width: 1.5,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.9),
              const Color(0xFF132F4C).withValues(alpha: 0.9),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _floatingIconButton(
              icon: _isPaused || !_isSpeaking ? Icons.play_arrow_rounded : Icons.pause,
              onTap: () {
                if (_isPaused) {
                  _playOverview();
                } else if (_isSpeaking) {
                  _pauseOverview();
                } else {
                  _playOverview();
                }
              },
              tooltip: _isPaused || !_isSpeaking ? 'landing_play_resume'.tr() : 'landing_pause'.tr(),
            ),
            const SizedBox(width: 8),
            _floatingIconButton(
              icon: Icons.stop,
              onTap: _stopOverview,
              tooltip: 'landing_stop'.tr(),
              enabled: _isSpeaking || _isPaused,
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF00D9A3).withValues(alpha: enabled ? 0.2 : 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF00D9A3).withValues(alpha: enabled ? 0.4 : 0.1),
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: const Color(0xFF00D9A3).withValues(alpha: enabled ? 1.0 : 0.3),
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

  Widget _languageButton({
    required String label,
    required Locale locale,
    required bool isSelected,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF00D9A3) : const Color(0xFF00D9A3).withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? const Color(0xFF00D9A3).withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await LanguageService.changeLanguage(
                context,
                AppLanguage.fromCode(locale.languageCode),
              );
              if (mounted) {
                setState(() {});
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF00D9A3) : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

