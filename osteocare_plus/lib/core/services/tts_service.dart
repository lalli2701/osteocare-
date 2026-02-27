import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService._internal();

  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();

  Future<void> configure() async {
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> speakTip(String text) async {
    await configure();
    await _tts.speak(text);
  }
}

