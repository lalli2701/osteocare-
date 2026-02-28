import 'package:flutter/material.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/services/speech_recognition_service.dart';
import '../../../core/services/permission_service.dart';

/// Reusable widget for voice-enabled survey questions
/// 
/// Provides:
/// - Question display with optional text input
/// - Voice button to read question aloud (TTS)
/// - Microphone button to record voice answers (STT)
/// - Confirmation dialog for voice-recognized answers
/// - Graceful fallback when permissions unavailable
/// - Respects voice_enabled user preference
class VoiceQuestionWidget extends StatefulWidget {
  /// The question widget to display (yes/no buttons, dropdown, text field, etc.)
  final Widget questionWidget;

  /// The question text to read aloud
  final String questionText;

  /// The question field name for data persistence
  final String fieldName;

  /// Question type (yes_no, select, number_input, height_weight)
  final String questionType;

  /// Current question index (for progress display)
  final int currentIndex;

  /// Total number of questions
  final int totalQuestions;

  /// Enable voice features for this question
  final bool enableVoice;

  /// Callback when voice answer is confirmed
  final Function(String fieldName, dynamic answer)? onVoiceAnswerConfirmed;

  /// Optional - answer options for voice selection (for yes_no, select types)
  final List<String>? answerOptions;

  /// Optional - custom voice script builder
  final String Function(String question)? voiceScriptBuilder;

  const VoiceQuestionWidget({
    super.key,
    required this.questionWidget,
    required this.questionText,
    required this.fieldName,
    required this.questionType,
    required this.currentIndex,
    required this.totalQuestions,
    this.enableVoice = true,
    this.onVoiceAnswerConfirmed,
    this.answerOptions,
    this.voiceScriptBuilder,
  });

  @override
  State<VoiceQuestionWidget> createState() => _VoiceQuestionWidgetState();
}

class _VoiceQuestionWidgetState extends State<VoiceQuestionWidget> {
  late VoiceService _voiceService;
  late SpeechRecognitionService _speechService;
  late PermissionService _permissionService;

  bool _isLoadingVoice = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String? _recognizedText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _voiceService = VoiceService();
    _speechService = SpeechRecognitionService();
    _permissionService = PermissionService();
  }

  /// Generate voice script for the question
  String _generateVoiceScript() {
    if (widget.voiceScriptBuilder != null) {
      return widget.voiceScriptBuilder!(widget.questionText);
    }

    // Use default voice service script generation
    return _voiceService.buildQuestionVoiceScript(
      widget.questionText,
      widget.currentIndex + 1,
      widget.totalQuestions,
      options: widget.answerOptions,
    );
  }

  /// Handle voice reading (TTS)
  Future<void> _handleVoiceRead() async {
    if (!widget.enableVoice) return;

    setState(() {
      _isLoadingVoice = true;
      _errorMessage = null;
    });

    try {
      final voiceScript = _generateVoiceScript();
      await _voiceService.speak(voiceScript);
      setState(() => _isSpeaking = true);

      // Listen for speech completion
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() => _isSpeaking = false);
        }
      });
    } catch (e) {
      _showError('Error reading question: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoadingVoice = false);
      }
    }
  }

  /// Handle voice input (STT)
  Future<void> _handleVoiceInput() async {
    if (!widget.enableVoice) return;

    // Check microphone permission
    final hasPermission = await _permissionService.hasMicrophonePermission();
    if (!hasPermission) {
      final granted = await _permissionService.ensureMicrophonePermission();
      if (!granted) {
        _showError(
          'Microphone permission required. Enable in app settings to use voice input.',
          action: _openAppSettings,
          actionLabel: 'Settings',
        );
        return;
      }
    }

    setState(() {
      _isLoadingVoice = true;
      _isListening = true;
      _errorMessage = null;
      _recognizedText = null;
    });

    try {
      // Read listening prompt
      final prompt = widget.questionType == 'number_input'
          ? _voiceService.getNumberPrompt()
          : 'Please answer the question aloud.';
      await _voiceService.speak(prompt);

      // Start speech recognition with callbacks
      await _speechService.startListening(
        onResult: (transcript) async {
          if (!mounted) return;
          
          try {
            // Parse the recognized text based on question type
            if (widget.questionType == 'yes_no') {
              final parsed = _speechService.parseYesNoAnswer(transcript);
              await _showVoiceConfirmation(transcript, parsed);
            } else if (widget.questionType == 'number_input') {
              final number = _speechService.extractNumber(transcript);
              if (number != null) {
                await _showVoiceConfirmation('$number', number);
              } else {
                _showError('Could not recognize a number. Please try again.');
              }
            } else if (widget.questionType == 'select') {
              // Show options for confirmation
              await _showSelectConfirmation(transcript);
            } else {
              // For other types, show the recognized text
              await _showVoiceConfirmation(transcript, transcript);
            }
          } catch (e) {
            _showError('Error processing voice input: ${e.toString()}');
          }
        },
        onError: () {
          _showError('Could not understand. Please try again.');
        },
      );
    } catch (e) {
      _showError('Voice input error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVoice = false;
          _isListening = false;
        });
      }
    }
  }

  /// Show confirmation dialog for voice-recognized answer
  Future<void> _showVoiceConfirmation(String displayText, dynamic answer) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Your Answer'),
        content: Text(
          'You said: "$displayText"\n\nIs that correct?',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retry'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Correct'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Confirmation - use the answer
      widget.onVoiceAnswerConfirmed?.call(widget.fieldName, answer);

      // Provide audio feedback
      try {
        final confirmMsg = _voiceService.getConfirmationPrompt(displayText);
        await _voiceService.speak(confirmMsg);
      } catch (_) {
        // Silently skip audio feedback if TTS fails
      }

      setState(() => _recognizedText = displayText);
    } else if (confirmed == false) {
      // Retry voice input
      await _handleVoiceInput();
    }
  }

  /// Show confirmation dialog for select question with options
  Future<void> _showSelectConfirmation(String recognizedText) async {
    if (!mounted || widget.answerOptions == null) {
      _showError('Voice selection not supported for this question type.');
      return;
    }

    // Try to match recognized text to options
    final matched = widget.answerOptions!.where(
      (option) => recognizedText.toLowerCase().contains(option.toLowerCase()),
    ).firstOrNull;

    if (matched != null) {
      await _showVoiceConfirmation(matched, matched);
    } else {
      _showError(
        'Could not find a matching option. Please try saying: ${widget.answerOptions!.join(", ")}',
      );
      // Retry
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        await _handleVoiceInput();
      }
    }
  }

  /// Show error message with optional action button
  void _showError(
    String message, {
    VoidCallback? action,
    String actionLabel = 'OK',
  }) {
    setState(() => _errorMessage = message);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: action != null
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: action,
                )
              : null,
        ),
      );
    }
  }

  /// Open app settings to enable microphone permission
  Future<void> _openAppSettings() async {
    await _permissionService.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main question widget
        widget.questionWidget,

        // Voice controls (only show if voice enabled and permission available)
        if (widget.enableVoice) ...[
          const SizedBox(height: 16),
          _buildVoiceControls(),
        ],

        // Error message
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              border: Border.all(color: Colors.red[300] ?? Colors.red),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Recognized text display
        if (_recognizedText != null && _recognizedText!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border.all(color: Colors.green[300] ?? Colors.green),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice answer: $_recognizedText',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Build voice control buttons
  Widget _buildVoiceControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(color: Colors.blue[200] ?? Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Speaker button (read question)
          Expanded(
            child: Tooltip(
              message: _isSpeaking ? 'Playing...' : 'Read question aloud',
              child: FilledButton.icon(
                onPressed: _isLoadingVoice ? null : _handleVoiceRead,
                icon: _isSpeaking
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.volume_up, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                label: const Text('Read'),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Microphone button (record answer)
          Expanded(
            child: Tooltip(
              message: _isListening ? 'Listening...' : 'Record your answer',
              child: FilledButton.icon(
                onPressed: _isLoadingVoice || _isListening
                    ? null
                    : _handleVoiceInput,
                icon: _isListening
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.mic, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                label: const Text('Answer'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Stop any ongoing TTS
    try {
      _voiceService.stop();
    } catch (_) {}

    super.dispose();
  }
}
