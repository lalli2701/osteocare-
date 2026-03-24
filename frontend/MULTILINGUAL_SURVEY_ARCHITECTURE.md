# 🎯 Multilingual Survey Architecture Guide

## Overview

This document explains the new dynamic, language-agnostic survey system for OsteoCare+. It separates question metadata from language-specific text, enabling seamless multilingual support without code duplication or logic changes.

---

## 📁 File Structure

```
osteocare_plus/
├── assets/
│   ├── survey/
│   │   └── survey_master.json          # Master question definitions
│   └── translations/
│       ├── en.json                      # UI translations
│       ├── hi.json                      # UI translations
│       ├── te.json                      # UI translations
│       └── survey_questions/
│           ├── en.json                  # Question text (English)
│           ├── hi.json                  # Question text (Hindi)
│           └── te.json                  # Question text (Telugu)
├── lib/
│   └── core/services/
│       └── survey_service.dart          # Survey loading & merging logic
└── pubspec.yaml                         # Updated with survey assets
```

---

## 🔷 Core Components

### 1. **survey_master.json** (Schema Definition)
Contains ONLY metadata - never changes with language.

**Structure:**
```json
[
  {
    "id": 1,
    "field_name": "age",
    "type": "number_input",
    "required": true,
    "model_mapping": {
      "data_column": "RIDAGEYR",
      "encoding": "as_is"
    }
  },
  {
    "id": 9,
    "field_name": "arthritis",
    "type": "yes_no",
    "options": ["Yes", "No"],
    "required": false,
    "model_mapping": {
      "data_column": "MCQ160G",
      "encoding": {
        "Yes": 1,
        "No": 0
      }
    }
  }
]
```

**Key Points:**
- ✅ Same structure for all languages
- ✅ Defines field types, options, validation rules
- ✅ Contains model encoding information
- ❌ NO language-specific text

---

### 2. **survey_questions/{en,hi,te}.json** (Translations)
Language-specific text only.

**English Example (en.json):**
```json
{
  "arthritis": {
    "question": "Has a doctor ever told you that you have arthritis (joint disease)?",
    "help_text": "Arthritis is a long-term joint condition...",
    "note_text": "This refers only to a diagnosis given by a doctor.",
    "info_text": "What is arthritis?...",
    "options": {
      "Yes": "Yes",
      "No": "No"
    }
  }
}
```

**Hindi Example (hi.json):**
```json
{
  "arthritis": {
    "question": "क्या किसी डॉक्टर ने आपको गठिया (संयुक्त रोग) होने की जानकारी दी है?",
    "help_text": "गठिया एक दीर्घकालिक संयुक्त स्थिति है...",
    "note_text": "यह केवल डॉक्टर द्वारा दिए गए निदान को संदर्भित करता है।",
    "info_text": "गठिया क्या है?...",
    "options": {
      "Yes": "हाँ",
      "No": "नहीं"
    }
  }
}
```

**Key Points:**
- ✅ Question text in user's language
- ✅ Help/info text in user's language
- ✅ Option labels in user's language
- ✅ Same keys as master file
- ❌ NO structural logic

---

### 3. **SurveyService** (Loader & Merger)

Handles loading and merging master + language files.

**Class Structure:**
```dart
class SurveyService {
  // Load master question definitions
  Future<List<dynamic>> _loadMasterQuestions()
  
  // Load language-specific text
  Future<Map<String, dynamic>> _loadLanguageQuestions(String languageCode)
  
  // Merge master + language and return SurveyQuestion objects
  Future<List<SurveyQuestion>> getQuestions()
  
  // Get single question by field name
  Future<SurveyQuestion?> getQuestionByFieldName(String fieldName)
  
  // Get translated option label
  String getOptionLabel(String fieldName, String value)
  
  // Reload for new language
  Future<void> reloadForLanguage(String languageCode)
}
```

**SurveyQuestion Model:**
```dart
class SurveyQuestion {
  final int id;
  final String fieldName;        // "arthritis"
  final String type;             // "yes_no", "number_input", etc.
  final String question;         // Localized question text
  final String helpText;         // Localized help text
  final List<String> options;    // ["Yes", "No"]
  final bool required;
  final Map<String, dynamic>? subFields;  // For height_weight
  final String? noteText;
  final String? infoText;
}
```

---

## 🟢 Integration Flow

### How the System Works

1. **User selects language** → `LanguageService.changeLanguage()`
2. **Survey screen loads** → `SurveyService.getQuestions()`
3. **Service loads** survey_master.json
4. **Service loads** language-specific questions (e.g., hi.json)
5. **Service merges** them → List<SurveyQuestion>
6. **UI renders** dynamically based on question type
7. **User submits** → Only structured values sent to backend

---

## 🔷 Usage Example in Survey Page

### Basic Implementation

```dart
class SurveyPage extends StatefulWidget {
  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  final SurveyService _surveyService = SurveyService();
  List<SurveyQuestion>? _questions;
  
  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final questions = await _surveyService.getQuestions();
    setState(() {
      _questions = questions;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_questions == null) {
      return Scaffold(
        appBar: AppBar(title: Text('survey_title'.tr())),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('survey_title'.tr())),
      body: PageView.builder(
        itemCount: _questions!.length,
        itemBuilder: (context, index) {
          final question = _questions![index];
          return _buildQuestionWidget(question);
        },
      ),
    );
  }

  Widget _buildQuestionWidget(SurveyQuestion question) {
    switch (question.type) {
      case 'yes_no':
        return _buildYesNoQuestion(question);
      case 'number_input':
        return _buildNumberQuestion(question);
      case 'select':
        return _buildSelectQuestion(question);
      case 'height_weight':
        return _buildHeightWeightQuestion(question);
      default:
        return SizedBox.shrink();
    }
  }

  Widget _buildYesNoQuestion(SurveyQuestion question) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Text(question.question, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton(
                onPressed: () {
                  _answers[question.fieldName] = 'Yes';  // Structured value
                  _nextQuestion();
                },
                child: Text(_surveyService.getOptionLabel(question.fieldName, 'Yes')),
              ),
              SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  _answers[question.fieldName] = 'No';  // Structured value
                  _nextQuestion();
                },
                child: Text(_surveyService.getOptionLabel(question.fieldName, 'No')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

---

## ✔️ Answer Storage

**Correct (Structured Values):**
```dart
{
  "arthritis": "Yes",           // Raw option value
  "age": 45,
  "gender": "Male",
  "smoking": "No",
  "alcohol": "Occasionally"
}
```

**Wrong (Translated Strings):**
```dart
{
  "arthritis": "हाँ",           // ❌ Never send translated text
  "arthritis": "అవును",        // ❌ Different per language
  "age": "चालीस पांच"           // ❌ Text instead of number
}
```

---

## 🔄 Language Switching

When user changes language in Profile:

```dart
// In profile_page.dart
Future<void> _changeLanguage(AppLanguage language) async {
  // 1. Update context locale
  await context.setLocale(language.locale);
  
  // 2. Sync with backend
  await LanguageService.changeLanguage(context, language);
  
  // 3. Reload survey questions for new language
  await SurveyService().reloadForLanguage(language.code);
}
```

---

## 🚨 Common Mistakes to Avoid

❌ **Don't**: Hardcode questions in UI
```dart
// WRONG
String getQuestion() {
  if (selectedLanguage == 'hi') {
    return 'क्या किसी डॉक्टर ने...';
  } else {
    return 'Has a doctor told...';
  }
}
```

✅ **Do**: Load from SurveyService
```dart
// RIGHT
final questions = await SurveyService().getQuestions();
final arthritisQuestion = questions.firstWhere((q) => q.fieldName == 'arthritis');
print(arthritisQuestion.question);  // Already localized
```

---

❌ **Don't**: Send translated answers
```dart
// WRONG
_submitSurvey({
  'arthritis': 'हाँ',  // Translated
  'age': 'पैंतालीस',   // Translated
});
```

✅ **Do**: Send structured values
```dart
// RIGHT
_submitSurvey({
  'arthritis': 'Yes',  // Structured
  'age': 45,           // Structured
});
```

---

❌ **Don't**: Duplicate questions per language
```
// WRONG structure
├── survey_questions_en.json
├── survey_questions_hi.json
├── survey_questions_te.json
├── SurveyPageEn
├── SurveyPageHi
├── SurveyPageTe
```

✅ **Do**: Single survey logic + language files
```
// RIGHT structure
├── survey_master.json (1 file)
├── survey_questions/
│   ├── en.json
│   ├── hi.json
│   ├── te.json
├── SurveyPage (1 component)
├── SurveyService (loader)
```

---

## 📊 Question Type Reference

| Type | Purpose | Backend Encoding |
|------|---------|------------------|
| `yes_no` | Binary choice | 1 (Yes) / 0 (No) |
| `select` | Multiple choice | Value as-is |
| `number_input` | Age, measurements | Number as-is |
| `height_weight` | BMI calculation | Calculated to BMX |
| `choice` | Gender, options | Mapped: Male=1, Female=2 |

---

## 🔐 Medical Safety

✅ **Fixed translations** (Survey questions)
- Manually reviewed by medical team
- Never auto-translated
- Stored in JSON files

✅ **Future: Dynamic translations** (AI explanations)
- Use Google Translate API
- For chat responses only
- Still reviewed before production

---

## 📝 Adding a New Language

1. **No changes needed** to survey_master.json
2. **Just add** `assets/translations/survey_questions/{xx}.json`
3. **Copy English file** and translate each question
4. **Ensure** all keys match English file
5. **Test** with SurveyService.getQuestions()

Example for Spanish (es):
```bash
cp assets/translations/survey_questions/en.json \
   assets/translations/survey_questions/es.json
# Edit es.json with Spanish translations
```

---

## ✨ Benefits

| Benefit | Why It Matters |
|---------|-----------------|
| **No duplication** | Single survey logic for all languages |
| **Type safe** | SurveyQuestion model validates structure |
| **Medical safe** | Translations manually reviewed |
| **Model compatible** | Backend unaffected by language changes |
| **Scalable** | Easy to add 4th, 5th language |
| **Cacheable** | SurveyService caches loaded data |
| **Voice ready** | Question IDs enable TTS integration |
| **Maintainable** | Clear separation of concerns |

---

## Next Steps

1. ✅ Created survey_master.json
2. ✅ Created en/hi/te question translations
3. ✅ Created SurveyService
4. ⏳ Refactor survey_page.dart to use SurveyService
5. ⏳ Add language switching tests
6. ⏳ Voice assistant integration (read question.id)
7. ⏳ Dynamic Google Translate for non-medical content

