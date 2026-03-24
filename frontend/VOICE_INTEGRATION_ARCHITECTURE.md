# 🎤 Multilingual Voice-Enabled Survey Architecture Guide

## 🎯 System Overview

The voice system is built on a frontend-focused architecture where:

- **Frontend**: Handles TTS (Text-to-Speech), STT (Speech-to-Text), keyword mapping, answer confirmation
- **Backend**: Stores only language preference (`voice_enabled`, `preferred_language`) — never processes speech

Backend remains completely language and speech-neutral.

---

## 📁 File Structure

```
lib/
├── core/services/
│   ├── voice_service.dart                 # TTS engine + voice script generation
│   ├── speech_recognition_service.dart    # STT + keyword mapping per language
│   ├── survey_service.dart                # Survey question loading (already implemented)
│   ├── language_service.dart              # Language preference management
│   └── auth_service.dart                  # Authentication (existing)
│
├── features/survey/presentation/
│   ├── survey_page.dart                   # Main survey UI (to integrate voice)
│   ├── voice_question_widget.dart         # Reusable voice-enabled question widget
│   └── voice_confirmation_dialog.dart     # Confirmation dialog for voice answers
│
└── features/onboarding/presentation/
    └── landing_page.dart                  # Already has floating voice controller
```

---

## 🔑 Key Components

### 1. **VoiceService** (voice_service.dart)

Manages **Text-to-Speech (TTS)** with dynamic language switching.

**Responsibilities:**
- Initialize and configure TTS engine
- Dynamically set TTS language (en-IN, hi-IN, te-IN)
- Generate voice scripts from question + language
- Handle speech control (play, stop, pause)

**Key Methods:**
```dart
// Change language for voice
await VoiceService().switchLanguage('hi');

// Build question voice script
final script = VoiceService().buildQuestionVoiceScript(
  currentIndex: 5,      // Question 5
  totalQuestions: 15,   // Out of 15
  questionText: translatedQuestion,
  options: ['Yes', 'No'],
);

// Speak the script
await VoiceService().speak(script);

// Stop speaking
await VoiceService().stop();
```

**Voice Script Format:**

English:
```
Question 5 of 15. Has a doctor ever told you that you have arthritis? You may answer by saying Yes or No.
```

Hindi:
```
15 में से 5वाँ प्रश्न। क्या किसी डॉक्टर ने आपको आर्थराइटिस होने की जानकारी दी है? कृपया हाँ या नहीं कहें।
```

Telugu:
```
15 లో 5వ ప్రశ్న. మీకు ఆర్థరైటిస్ ఉందని డాక్టర్ ఎప్పుడైనా చెప్పారు? దయచేసి అవును లేదా కాదు అని చెప్పండి.
```

---

### 2. **SpeechRecognitionService** (speech_recognition_service.dart)

Manages **Speech-to-Text (STT)** with multilingual keyword mapping.

**Responsibilities:**
- Listen to user speech in selected language locale
- Map speech to Yes/No/Alternative/Unknown based on language keywords
- Extract numbers from speech (for age field)
- Never send raw transcript to backend

**Keyword Mapping by Language:**

**English:**
- Yes: yes, yeah, yup, sure, okay, ok, correct, right, affirmative
- No: no, nope, nah, negative, never, not, false

**Hindi:**
- Yes: haan, haa, ham, bilkul, theek, sahi
- No: nahi, nahin, na, bilkul nahi, kabhi nahi

**Telugu:**
- Yes: avunu, aavanu, oka, kosu
- No: kaadu, kadu, ledu, lenu

**Key Methods:**
```dart
// Set recognition language
await SpeechRecognitionService().setLanguage('hi');

// Start listening
await SpeechRecognitionService().startListening(
  onResult: (transcript) {
    // Process result
  },
  onError: () {
    // Handle error
  },
);

// Parse yes/no answer
final result = SpeechRecognitionService().parseYesNoAnswer(transcript);
// Returns: RecognitionResult.yes | .no | .alternative | .unknown

// Extract number (for age)
final age = SpeechRecognitionService().extractNumber(transcript);

// Get display text
final displayText = SpeechRecognitionService().getDisplayText(transcript, result);
```

---

## 🎬 Complete Voice Flow Diagrams

### **App Startup Flow (Cold Launch)**

```
App Launch
  ↓
Check SharedPreferences for 'preferred_language'
  ↓
  ├─ Found → Load stored language (e.g., 'hi')
  │           Set app locale to 'hi'
  │           Set VoiceService language to 'hi-IN'
  │           Set SpeechRecognitionService to 'hi_IN'
  │           Go to Splash
  │
  └─ Not Found → Default to 'en'
                 Set app locale to 'en'
                 Set VoiceService to 'en-IN'
                 Set SpeechRecognitionService to 'en_IN'
                 Save 'en' to SharedPreferences
                 Go to Splash
```

### **After Login Flow**

```
Login Success
  ↓
Backend returns:
{
  "user": {...},
  "preferred_language": "telugu",
  "voice_enabled": true
}
  ↓
Frontend checks:
  If backend language ≠ local language
    → Update context locale
    → Update VoiceService
    → Update SpeechRecognitionService
    → Save to SharedPreferences
  Else
    → Proceed as-is
  ↓
Go to Dashboard
```

### **Profile Language Change Flow**

```
User Opens Profile
  ↓
User Selects New Language (e.g., Hindi)
  ↓
Stop running TTS (if any)
Stop speech recognition (if active)
  ↓
Set VoiceService language to 'hi-IN'
Set SpeechRecognitionService to 'hi_IN'
  ↓
Update context locale to 'hi'
Save to SharedPreferences
  ↓
POST to backend: {"preferred_language": "hindi"}
  ↓
Reload current screen in new language
```

### **Survey Question Voice Reading Flow**

```
Survey Page Loads Question
  ↓
Question 5: "arthritis"
  ↓
Load translated question: "क्या किसी डॉक्टर ने..."
Load options: ["हाँ", "नहीं"]
  ↓
Get current language: 'hi'
Set VoiceService language: 'hi-IN'
Set SpeechRecognitionService language: 'hi_IN'
  ↓
Build voice script:
"15 में से 5वाँ प्रश्न। क्या किसी डॉक्टर ने आपको आर्थराइटिस होने की जानकारी दी है? कृपया हाँ या नहीं कहें।"
  ↓
Automatically read question via TTS
(or user can tap mic to read again)
  ↓
User taps Mic button
  ↓
SpeechRecognitionService starts listening in 'hi_IN' locale
  ↓
User speaks: "हाँ"
  ↓
Transcript received: "हाँ"
Parse with keyword map: RecognitionResult.yes
  ↓
Show confirmation dialog:
"आपने कहा: हाँ। क्या यह सही है?"
Buttons: [Confirm] [Retry]
  ↓
If Confirm:
  Store answer: {"arthritis": "Yes"}
  Move to next question
  
If Retry:
  Speak retry prompt: "मुझे समझ नहीं आया। कृपया पुनः प्रयास करें।"
  Restart listening
```

### **Landing Page Auto-Voice Flow**

```
Landing Page Renders
  ↓
Check voice_enabled preference (from backend after login)
  ↓
If voice_enabled == true:
  Get current language from SharedPreferences
  Set VoiceService language
  Auto-play overview in selected language
  Show Stop button
  
If voice_enabled == false:
  Show only Play button
  No auto-play
```

---

## 🚫 Critical Rules

### **Never Do:**

❌ Auto-submit after speech recognition
→ **Always show confirmation dialog before accepting**

❌ Mix languages in same question
→ **Load and use one language at a time**

❌ Send raw transcript to backend
→ **Send only structured answer: {"arthritis": "Yes"}**

❌ Switch locale without stopping TTS/STT
→ **Stop, switch, reinitialize in order**

❌ Trust voice input for complex data (height)
→ **Use touch input for height, voice for simple yes/no**

### **Always Do:**

✅ Initialize VoiceService before playing audio
✅ Initialize SpeechRecognitionService before listening
✅ Check language before parsing keywords
✅ Show confirmation before accepting answer
✅ Handle speech recognition failure gracefully
✅ Stop TTS when speech recognition starts
✅ Match TTS locale with speech recognition locale

---

## 🔧 Implementation Patterns

### **Pattern 1: Simple Yes/No Question with Voice**

```dart
class VoiceYesNoQuestion extends StatefulWidget {
  final SurveyQuestion question;
  final int currentIndex;
  final int totalQuestions;
  final Function(String answer) onAnswered;

  @override
  State<VoiceYesNoQuestion> createState() => _VoiceYesNoQuestionState();
}

class _VoiceYesNoQuestionState extends State<VoiceYesNoQuestion> {
  final VoiceService _voiceService = VoiceService();
  final SpeechRecognitionService _speechService = SpeechRecognitionService();
  bool _showVoiceUI = false;

  @override
  void initState() {
    super.initState();
    _initializeVoice();
  }

  Future<void> _initializeVoice() async {
    await _voiceService.initialize();
    final initialized = await _speechService.initialize();
    setState(() => _showVoiceUI = initialized);
  }

  Future<void> _readQuestion() async {
    final script = _voiceService.buildQuestionVoiceScript(
      widget.currentIndex,
      widget.totalQuestions,
      widget.question.question,
      widget.question.options,
    );
    await _voiceService.speak(script);
  }

  Future<void> _startListening() async {
    await _voiceService.stop(); // Stop question reading
    
    await _speechService.startListening(
      onResult: (transcript) {
        _handleVoiceResult(transcript);
      },
      onError: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(text: 'Could not recognize speech'),
        );
      },
    );
  }

  void _handleVoiceResult(String transcript) {
    final result = _speechService.parseYesNoAnswer(transcript);
    final displayText = _speechService.getDisplayText(transcript, result);

    if (result == RecognitionResult.unknown) {
      _showRetryDialog();
      return;
    }

    _showConfirmationDialog(displayText, result);
  }

  void _showConfirmationDialog(String userAnswer, RecognitionResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Answer'),
        content: Text(_voiceService.getConfirmationPrompt(userAnswer)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onAnswered(result == RecognitionResult.yes ? 'Yes' : 'No');
            },
            child: Text('Confirm'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startListening(); // Retry
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showRetryDialog() {
    final prompt = _voiceService.getRetryPrompt();
    _voiceService.speak(prompt).then((_) {
      Future.delayed(Duration(milliseconds: 500), _startListening);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(widget.question.question),
        if (_showVoiceUI) ...[
          ElevatedButton(
            onPressed: _readQuestion,
            child: Icon(Icons.volume_up),
          ),
          ElevatedButton(
            onPressed: _startListening,
            child: Icon(Icons.mic),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _voiceService.dispose();
    _speechService.dispose();
    super.dispose();
  }
}
```

---

## 🌐 Language Initialization Checklist

- [ ] VoiceService knows current language from SharedPreferences
- [ ] SpeechRecognitionService locale matches VoiceService language
- [ ] Survey questions loaded in correct language
- [ ] Keyword mapping loaded for current language
- [ ] Number extraction rules loaded for current language
- [ ] Voice scripts generated in current language

---

## 🔐 Backend Language Rules

**Backend must store:**
- `voice_enabled` (boolean)
- `preferred_language` (string: 'english', 'hindi', 'telugu')

**Backend must NOT store:**
- Translated UI text
- Voice transcripts
- Speech recognition data

**Backend must NOT do:**
- Translate survey questions
- Translate risk levels
- Auto-generate translations

---

## ✅ Testing Checklist

- [ ] App launches with saved language preference
- [ ] TTS language matches app language
- [ ] Speech recognition locale matches app language
- [ ] Yes/No keywords recognized correctly in English
- [ ] Yes/No keywords recognized correctly in Hindi
- [ ] Yes/No keywords recognized correctly in Telugu
- [ ] Number extraction works for age (English)
- [ ] Confirmation dialog shown before accepting answer
- [ ] Retry works after failed recognition
- [ ] Language switch stops TTS/STT before changing
- [ ] No raw transcripts sent to backend
- [ ] Only structured answers sent to backend

---

## 🚀 Next Implementation Steps

1. **VoiceQuestionWidget** - Reusable component for voice-enabled questions
2. **Integrate with SurveyPage** - Add voice button to each question
3. **Voice Preference Toggle** - Allow users to enable/disable voice in settings
4. **Error Handling** - Graceful fallback when speech unavailable
5. **Performance** - Cache voice scripts to reduce TTS latency
6. **Testing** - Test multilingual recognition with native speakers

---

## 📊 Architecture Summary

```
┌─────────────────────────────────────────────────┐
│           FRONTEND (No Network Needed)          │
├─────────────────────────────────────────────────┤
│  VoiceService (TTS)                             │
│  └─ English: en-IN                              │
│  └─ Hindi: hi-IN                                │
│  └─ Telugu: te-IN                               │
├─────────────────────────────────────────────────┤
│  SpeechRecognitionService (STT)                 │
│  └─ Keyword mapping per language                │
│  └─ Number extraction per language              │
│  └─ Never sends raw transcript                  │
├─────────────────────────────────────────────────┤
│  SurveyService                                  │
│  └─ Loads questions in user's language          │
│  └─ Provides translated question text           │
├─────────────────────────────────────────────────┤
│  LanguageService                                │
│  └─ Manages language preference                 │
│  └─ Syncs with backend                          │
└─────────────────────────────────────────────────┘
            ↓ (Only structured data)
┌─────────────────────────────────────────────────┐
│         BACKEND (Language Neutral)              │
├─────────────────────────────────────────────────┤
│  Auth: Login, Signup                            │
│  Prefs: voice_enabled, preferred_language       │
│  Survey: Receives {"field": value}              │
│  Model: ML prediction (language independent)    │
└─────────────────────────────────────────────────┘
```

This architecture ensures:
- ✅ Offline voice capability
- ✅ Fallback to text input
- ✅ Language-neutral model
- ✅ Privacy (no speech data stored)
- ✅ Performance (local processing)
