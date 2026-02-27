import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/user_session.dart';
import '../presentation/result_page.dart';

class SurveyPage extends StatefulWidget {
  const SurveyPage({super.key});

  static const routePath = '/survey';

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();

  bool _hadFracture = false;
  String? _fractureDuration;

  bool _hadSurgery = false;
  String? _surgeryDuration;

  bool _familyHistory = false;
  bool _steroidUse = false;
  String? _steroidDuration;

  bool _smoking = false;
  bool _alcohol = false;
  bool _lowActivity = false;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    await Future<void>.delayed(const Duration(milliseconds: 600));

    final riskLevel = _calculateRiskLevel();
    UserSession.instance.setLastRiskLevel(riskLevel);

    // Save this survey in Firestore under the authenticated user so it can
    // appear in the tasks/history page.
    try {
      final uid = UserSession.instance.uid;
      final age = int.tryParse(_ageController.text.trim());
      final weight = double.tryParse(_weightController.text.trim());

      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('surveys')
            .add({
          'name': _nameController.text.trim(),
          'age': age,
          'weight': weight,
          'hadFracture': _hadFracture,
          'fractureDuration': _fractureDuration,
          'hadSurgery': _hadSurgery,
          'surgeryDuration': _surgeryDuration,
          'familyHistory': _familyHistory,
          'steroidUse': _steroidUse,
          'steroidDuration': _steroidDuration,
          'smoking': _smoking,
          'alcohol': _alcohol,
          'lowActivity': _lowActivity,
          'riskLevel': riskLevel,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // If saving fails (for example offline), continue without blocking the user.
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    context.go(ResultPage.routePath, extra: riskLevel);
  }

  String _calculateRiskLevel() {
    int score = 0;

    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final weight = double.tryParse(_weightController.text.trim()) ?? 0;

    // Age weighting: strongest after 65, then 50–64, then 40–49.
    if (age >= 65) {
      score += 3;
    } else if (age >= 50) {
      score += 2;
    } else if (age >= 40) {
      score += 1;
    }

    // Low body weight: stronger risk if < 50 kg.
    if (weight > 0 && weight < 50) {
      score += 3;
    } else if (weight >= 50 && weight < 60) {
      score += 2;
    }

    // Previous fracture: more weight and higher if very recent.
    if (_hadFracture) {
      score += 3;
      if (_fractureDuration == '<6_months') {
        score += 2;
      } else if (_fractureDuration == '6_12_months') {
        score += 1;
      }
    }

    // Major surgery / operation (arthritis / cancer treatment etc.).
    if (_hadSurgery) {
      score += 2;
      if (_surgeryDuration == '<6_months') {
        score += 1;
      }
    }

    // Family history.
    if (_familyHistory) {
      score += 2;
    }

    // Steroid medicines.
    if (_steroidUse) {
      score += 2;
      if (_steroidDuration == '>1_year') {
        score += 1;
      }
    }

    // Lifestyle factors.
    if (_smoking) score += 1;
    if (_alcohol) score += 1;
    if (_lowActivity) score += 1;

    if (score <= 3) {
      return 'low';
    } else if (score <= 7) {
      return 'moderate';
    } else {
      return 'high';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Osteoporosis risk survey'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tell us a bit about you',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Age (years)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Required';
                  final age = int.tryParse(text);
                  if (age == null || age <= 0) return 'Enter a valid age.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Required';
                  final weight = double.tryParse(text);
                  if (weight == null || weight <= 0) {
                    return 'Enter a valid weight.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Fractures and surgeries',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                title: const Text('Have you had any fractures before?'),
                value: _hadFracture,
                onChanged: (val) {
                  setState(() {
                    _hadFracture = val;
                    if (!val) _fractureDuration = null;
                  });
                },
              ),
              if (_hadFracture)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: DropdownButtonFormField<String>(
                    value: _fractureDuration,
                    decoration: const InputDecoration(
                      labelText: 'When did it happen?',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '<6_months',
                        child: Text('Within the last 6 months'),
                      ),
                      DropdownMenuItem(
                        value: '6_12_months',
                        child: Text('6–12 months ago'),
                      ),
                      DropdownMenuItem(
                        value: '>1_year',
                        child: Text('More than 1 year ago'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _fractureDuration = val),
                  ),
                ),
              SwitchListTile(
                title: const Text(
                  'Have you had any major bone/orthopedic surgery or operation?',
                ),
                value: _hadSurgery,
                onChanged: (val) {
                  setState(() {
                    _hadSurgery = val;
                    if (!val) _surgeryDuration = null;
                  });
                },
              ),
              if (_hadSurgery)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: DropdownButtonFormField<String>(
                    value: _surgeryDuration,
                    decoration: const InputDecoration(
                      labelText: 'When was it?',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '<6_months',
                        child: Text('Within the last 6 months'),
                      ),
                      DropdownMenuItem(
                        value: '6_12_months',
                        child: Text('6–12 months ago'),
                      ),
                      DropdownMenuItem(
                        value: '>1_year',
                        child: Text('More than 1 year ago'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _surgeryDuration = val),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Other risk factors',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                title: const Text(
                  'Family history of osteoporosis or hip fracture?',
                ),
                value: _familyHistory,
                onChanged: (val) => setState(() => _familyHistory = val),
              ),
              SwitchListTile(
                title: const Text('Long-term steroid medication use?'),
                value: _steroidUse,
                onChanged: (val) {
                  setState(() {
                    _steroidUse = val;
                    if (!val) _steroidDuration = null;
                  });
                },
              ),
              if (_steroidUse)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: DropdownButtonFormField<String>(
                    value: _steroidDuration,
                    decoration: const InputDecoration(
                      labelText: 'For how long?',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '<3_months',
                        child: Text('Less than 3 months'),
                      ),
                      DropdownMenuItem(
                        value: '3_12_months',
                        child: Text('3–12 months'),
                      ),
                      DropdownMenuItem(
                        value: '>1_year',
                        child: Text('More than 1 year'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _steroidDuration = val),
                  ),
                ),
              SwitchListTile(
                title: const Text('Do you smoke currently?'),
                value: _smoking,
                onChanged: (val) => setState(() => _smoking = val),
              ),
              SwitchListTile(
                title: const Text('Do you drink alcohol very often?'),
                value: _alcohol,
                onChanged: (val) => setState(() => _alcohol = val),
              ),
              SwitchListTile(
                title: const Text('Is your daily physical activity very low?'),
                value: _lowActivity,
                onChanged: (val) => setState(() => _lowActivity = val),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('See my risk level'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

