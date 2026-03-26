import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/dynamic_translation_service.dart';
import '../../../core/services/prescription_storage_service.dart';

import '../../dashboard/presentation/profile_page.dart';
import '../../dashboard/presentation/tasks_page.dart';
import 'survey_page.dart';
import '../../chatbot/presentation/assistant_fab.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, this.result});

  static const routePath = '/results';

  final dynamic result; // Map<String, dynamic> from API

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late Locale _currentLocale;
  bool _localeInitialized = false;
  String? _translatedMessage;
  List<String> _translatedTasks = const [];
  List<String> _translatedAlerts = const [];
  bool _highRiskDialogShown = false;
  String? _detectedCity;
  List<Map<String, String>> _nearbyOrthopedicHospitals = const [];
  bool _isSavingPdf = false;

  static const List<Map<String, String>> _orthopedicHospitals = [
    {
      'name': 'Apollo Hospitals',
      'speciality': 'Orthopedics',
      'contact': '+91-1860-500-1066',
    },
    {
      'name': 'Yashoda Hospitals',
      'speciality': 'Orthopedics',
      'contact': '+91-40-4567-4567',
    },
    {
      'name': 'KIMS Hospitals',
      'speciality': 'Orthopedics',
      'contact': '+91-40-4488-5000',
    },
    {
      'name': 'AIG Hospitals',
      'speciality': 'Orthopedics',
      'contact': '+91-40-4244-4222',
    },
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocale = context.locale;
    if (!_localeInitialized) {
      _currentLocale = newLocale;
      _localeInitialized = true;
      _translateDynamicContent();
    } else if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      _translateDynamicContent();
    }

    _maybeShowHighRiskHospitalDialog();
  }

  Future<void> _loadNearbyOrthopedicHospitals() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          _detectedCity = placemarks.first.locality ?? placemarks.first.subAdministrativeArea;
        }
      } catch (_) {
        // Non-blocking city detection.
      }

      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&q=orthopedic%20hospital%20near%20${position.latitude},${position.longitude}',
      );
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'OsteoCarePlus/1.0 (health app)',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return;
      }

      final hospitals = <Map<String, String>>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final displayName = (item['display_name'] ?? '').toString();
        if (displayName.isEmpty) {
          continue;
        }
        final lat = double.tryParse((item['lat'] ?? '').toString());
        final lon = double.tryParse((item['lon'] ?? '').toString());
        String distanceLabel = '';
        if (lat != null && lon != null) {
          final meters = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            lat,
            lon,
          );
          distanceLabel = '${(meters / 1000).toStringAsFixed(1)} km';
        }

        final name = displayName.split(',').first.trim();
        hospitals.add({
          'name': name,
          'speciality': 'Orthopedics',
          'contact': distanceLabel,
          'address': displayName,
        });
      }

      if (!mounted || hospitals.isEmpty) {
        return;
      }

      setState(() {
        _nearbyOrthopedicHospitals = hospitals.take(5).toList();
      });
    } catch (_) {
      // Keep static fallback list when location/network is unavailable.
    }
  }

  bool _isHighRiskResult() {
    if (widget.result is! Map<String, dynamic>) {
      return false;
    }
    final level = (widget.result['risk_level'] ?? '').toString().toLowerCase();
    return level == 'high';
  }

  void _maybeShowHighRiskHospitalDialog() {
    if (_highRiskDialogShown || !_isHighRiskResult() || !mounted) {
      return;
    }
    _highRiskDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _loadNearbyOrthopedicHospitals().whenComplete(() {
        final hospitals = _nearbyOrthopedicHospitals.isEmpty
            ? _orthopedicHospitals
            : _nearbyOrthopedicHospitals;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text('high_risk_hospital_popup_title'.tr()),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('high_risk_hospital_popup_body'.tr()),
                    if ((_detectedCity ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'result_detected_city'.tr(args: [_detectedCity!]),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 12),
                    ...hospitals.map((hospital) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hospital['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${hospital['speciality'] ?? ''} • ${hospital['contact'] ?? ''}',
                            ),
                            if ((hospital['address'] ?? '').isNotEmpty)
                              Text(
                                hospital['address'] ?? '',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text(
                      'high_risk_hospital_popup_note'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('ok'.tr()),
              ),
            ],
          );
        },
      );
      });
    });
  }

  Future<void> _saveResultAsPdf({
    required String riskLevel,
    required double probability,
    required String summary,
    required List<String> recommendations,
    required List<String> alerts,
  }) async {
    if (_isSavingPdf) {
      return;
    }
    setState(() {
      _isSavingPdf = true;
    });

    try {
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return <pw.Widget>[
              pw.Text('OsteoCare+ Risk Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Generated: ${DateTime.now()}'),
              pw.SizedBox(height: 8),
              pw.Text('Risk Level: $riskLevel'),
              pw.Text('Probability: ${(probability * 100).toStringAsFixed(1)}%'),
              pw.SizedBox(height: 16),
              pw.Text('Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(summary),
              pw.SizedBox(height: 12),
              if (recommendations.isNotEmpty)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('Recommendations', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ...recommendations.map((e) => pw.Bullet(text: e)),
                  ],
                ),
              if (alerts.isNotEmpty)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.SizedBox(height: 12),
                    pw.Text('Medical Alerts', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ...alerts.map((e) => pw.Bullet(text: e)),
                  ],
                ),
            ];
          },
        ),
      );

      final baseDir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory(p.join(baseDir.path, 'reports'));
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      final fileName = 'result_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputPath = p.join(reportsDir.path, fileName);
      final file = File(outputPath);
      await file.writeAsBytes(await doc.save(), flush: true);

      await PrescriptionStorageService.addReport(
        filePath: outputPath,
        fileName: fileName,
        source: 'result_pdf',
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('result_pdf_saved'.tr(args: [outputPath])),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('result_pdf_save_failed'.tr(args: ['$e']))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPdf = false;
        });
      }
    }
  }

  Future<void> _translateDynamicContent() async {
    if (widget.result is! Map<String, dynamic>) {
      return;
    }
    final payload = widget.result as Map<String, dynamic>;
    final langCode = context.locale.languageCode;

    final message = (payload['message'] ?? '').toString();
    final tasks = List<String>.from(payload['recommended_tasks'] ?? const []);
    final alerts = List<String>.from(payload['medical_alerts'] ?? const []);

    final translatedMessage = message.isEmpty
        ? ''
        : await DynamicTranslationService.instance.translate(
            message,
            langCode: langCode,
          );
    final translatedTasks = tasks.isEmpty
        ? const <String>[]
        : await DynamicTranslationService.instance.translateMany(
            tasks,
            langCode: langCode,
          );
    final translatedAlerts = alerts.isEmpty
        ? const <String>[]
        : await DynamicTranslationService.instance.translateMany(
            alerts,
            langCode: langCode,
          );

    if (!mounted) return;
    setState(() {
      _translatedMessage = translatedMessage.isEmpty ? null : translatedMessage;
      _translatedTasks = translatedTasks;
      _translatedAlerts = translatedAlerts;
    });
  }

  Color _colorForRisk(String level) {
    switch (level.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'high':
        return Colors.red;
      case 'moderate':
      default:
        return Colors.orange;
    }
  }

  String _labelForRisk(String level) {
    switch (level.toLowerCase()) {
      case 'low':
        return 'risk_low'.tr();
      case 'high':
        return 'risk_high'.tr();
      case 'moderate':
      default:
        return 'risk_moderate'.tr();
    }
  }

  int? _extractAgeFromResult(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final directAge = payload['age'];
    final parsedDirect = int.tryParse(directAge?.toString() ?? '');
    if (parsedDirect != null) {
      return parsedDirect;
    }

    final inputs = payload['inputs'];
    if (inputs is Map<String, dynamic>) {
      final age = inputs['age'];
      return int.tryParse(age?.toString() ?? '');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Extract data from result
    String riskLevel = 'Unknown';
    String message = 'result_survey_incomplete'.tr();
    double probability = 0.0;
    List<String> tasks = [];
    List<String> alerts = [];

    if (widget.result is Map<String, dynamic>) {
      riskLevel = widget.result['risk_level'] ?? 'Unknown';
      message = widget.result['message'] ?? message;
      probability = (widget.result['probability'] ?? 0.0).toDouble();
      tasks = List<String>.from(widget.result['recommended_tasks'] ?? []);
      alerts = List<String>.from(widget.result['medical_alerts'] ?? []);
    }

    final shownMessage = _translatedMessage ?? message;
    final shownTasks = _translatedTasks.isEmpty ? tasks : _translatedTasks;
    final shownAlerts = _translatedAlerts.isEmpty ? alerts : _translatedAlerts;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text('result_title'.tr()),
      ),
      floatingActionButton: const AssistantFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Risk Level Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'result_risk_level'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: _colorForRisk(riskLevel).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _colorForRisk(riskLevel),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        _labelForRisk(riskLevel),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _colorForRisk(riskLevel),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'result_probability'.tr(args: [(probability * 100).toStringAsFixed(1)]),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Message Card
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'result_summary'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      shownMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recommended Tasks
            if (shownTasks.isNotEmpty) ...[
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'result_recommendations'.tr(),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ...shownTasks.asMap().entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _colorForRisk(riskLevel).withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${entry.key + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _colorForRisk(riskLevel),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Medical Alerts
            if (shownAlerts.isNotEmpty) ...[
              Card(
                elevation: 1,
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'result_alerts'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...shownAlerts.map((alert) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '• $alert',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.orange[900],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Info Text
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'result_disclaimer'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go(ProfilePage.routePath),
                    icon: const Icon(Icons.person_outline),
                    label: Text('profile'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSavingPdf
                        ? null
                        : () => _saveResultAsPdf(
                              riskLevel: riskLevel,
                              probability: probability,
                              summary: shownMessage,
                              recommendations: shownTasks,
                              alerts: shownAlerts,
                            ),
                    icon: _isSavingPdf
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(_isSavingPdf ? 'result_saving'.tr() : 'result_save_pdf'.tr()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons
            FilledButton(
              onPressed: () {
                final age = _extractAgeFromResult(widget.result);
                context.go(
                  TasksPage.routePath,
                  extra: {
                    'risk_level': riskLevel,
                    'age': age,
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('view_health_tips'.tr()),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(SurveyPage.routePath),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('retake_survey'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
