import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/auth/user_session.dart';
import '../../auth/presentation/login_page.dart';
import '../../survey/presentation/nearby_hospitals_page.dart';
import '../../survey/presentation/result_page.dart';
import 'dashboard_wrapper.dart';

class SurveyHistoryPage extends StatefulWidget {
  const SurveyHistoryPage({super.key});

  static const routePath = '/survey-history';

  @override
  State<SurveyHistoryPage> createState() => _SurveyHistoryPageState();
}

class _SurveyHistoryPageState extends State<SurveyHistoryPage> {
  late final Future<String?> _uidFuture = _resolveUserId();

  Future<String?> _resolveUserId() async {
    final sessionUid = UserSession.instance.userId;
    if (sessionUid != null && sessionUid.isNotEmpty) {
      return sessionUid;
    }

    final userData = await AuthService.instance.getUserData();
    final storageUid = userData?['id']?.toString().trim();
    if (storageUid != null && storageUid.isNotEmpty) {
      UserSession.instance.userId = storageUid;
      return storageUid;
    }

    return null;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildHistoryStream(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('surveys')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  String _riskLabel(String? riskLevel) {
    final risk = (riskLevel ?? '').toLowerCase();
    if (risk == 'low') return 'risk_low'.tr();
    if (risk == 'moderate') return 'risk_moderate'.tr();
    if (risk == 'high') return 'risk_high'.tr();
    return 'Unknown';
  }

  String _riskShortLabel(String? riskLevel) {
    final risk = (riskLevel ?? '').toLowerCase();
    if (risk == 'low') return 'Low';
    if (risk == 'moderate') return 'Moderate';
    if (risk == 'high') return 'High';
    return 'Unknown';
  }

  Color _riskColor(String? riskLevel) {
    final risk = (riskLevel ?? '').toLowerCase();
    if (risk == 'low') return const Color(0xFF1FA45B);
    if (risk == 'moderate') return const Color(0xFFE2A50D);
    if (risk == 'high') return const Color(0xFFD8433E);
    return const Color(0xFF6B7280);
  }

  String _riskEmoji(String? riskLevel) {
    final risk = (riskLevel ?? '').toLowerCase();
    if (risk == 'low') return '🟢';
    if (risk == 'moderate') return '🟡';
    if (risk == 'high') return '🔴';
    return '⚪';
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('MMM d, h:mm a').format(value);
  }

  Future<void> _confirmAndDeleteSurvey({
    required String uid,
    required _HistorySurveyEntry entry,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Survey?'),
          content: Text(
            'This will delete the survey from ${_formatDateTime(entry.createdAt)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('surveys')
          .doc(entry.docId)
          .delete();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Survey deleted successfully.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete survey. $e')),
      );
    }
  }

  String _humanize(String text) {
    return text
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  Widget _buildLoggedOutEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '📊 Track Your Progress',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in to see how your bone health changes over time',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.go(LoginPage.routePath),
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No survey history yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Complete your first survey to start your health story.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/survey'),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Take Survey'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(DashboardWrapper.routePath);
            }
          },
        ),
        title: const Text('Survey History'),
      ),
      body: FutureBuilder<String?>(
        future: _uidFuture,
        builder: (context, uidSnapshot) {
          if (uidSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final uid = uidSnapshot.data;
          if (uid == null || uid.isEmpty) {
            return _buildLoggedOutEmptyState(context);
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _buildHistoryStream(uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Unable to load survey history right now.'),
                );
              }

              final docs = snapshot.data?.docs ?? const [];
              if (docs.isEmpty) {
                return _buildNoDataState(context);
              }

              final timeline = docs.map((doc) {
                final data = doc.data();
                final createdRaw = data['createdAt'] ?? data['updatedAt'];
                final createdAt = createdRaw is Timestamp
                    ? createdRaw.toDate()
                    : DateTime.now();
                final risk = data['riskLevel']?.toString() ?? 'Moderate';
                final riskScore = (data['riskScore'] as num?)?.toDouble() ??
                    (((data['probability'] as num?)?.toDouble() ?? 0.0) * 100);

                final factors = _stringList(data['topFactors']);
                final fallbackFactors = _stringList(data['factors']);
                final mainFactors = factors.isNotEmpty ? factors : fallbackFactors;

                final recTasks = _stringList(data['recommendedTasks']);
                final recFromTasks = _stringList(data['tasks']);
                final recLegacy = _stringList(data['recommendations']);
                final recommendations = recTasks.isNotEmpty
                    ? recTasks
                    : (recFromTasks.isNotEmpty ? recFromTasks : recLegacy);

                Map<String, dynamic> resultPayload = {
                  'risk_level': risk,
                  'probability': (riskScore / 100).clamp(0.0, 1.0),
                  'confidence': (data['confidence'] as num?)?.toDouble() ?? 0.5,
                  'confidence_label': data['confidenceLabel']?.toString() ?? 'Medium',
                  'confidence_band': data['confidenceBand']?.toString() ?? 'Medium',
                  'confidence_reason': data['confidenceReason']?.toString() ??
                      'Loaded from survey history.',
                  'recommended_tasks': recommendations,
                  'top_factors': mainFactors,
                  'primary_action': recommendations.isNotEmpty
                      ? recommendations.first
                      : '',
                  'time_groups': const <String, dynamic>{},
                };

                final rawResult = data['result'];
                if (rawResult is Map<String, dynamic>) {
                  resultPayload = rawResult;
                }

                return _HistorySurveyEntry(
                  docId: doc.id,
                  createdAt: createdAt,
                  riskLevel: risk,
                  riskScore: riskScore,
                  factors: mainFactors,
                  recommendations: recommendations,
                  resultPayload: resultPayload,
                );
              }).toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD9E3FF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Progress View',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...timeline.take(6).map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${DateFormat('MMM d').format(item.createdAt)} - ${_riskShortLabel(item.riskLevel)}',
                                  style: TextStyle(color: Colors.blueGrey.shade700),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  ...timeline.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final riskColor = _riskColor(item.riskLevel);
                    final displayFactors = item.factors.take(2).map(_humanize).toList();
                    final insight = displayFactors.isEmpty
                        ? 'Main: Lifestyle and bone-health factors'
                        : 'Main: ${displayFactors.join(', ')}';

                    final previous = index + 1 < timeline.length
                        ? timeline[index + 1]
                        : null;
                    final trendNote = previous == null
                        ? 'Latest entry in your timeline'
                        : (_riskShortLabel(item.riskLevel).toLowerCase() ==
                                _riskShortLabel(previous.riskLevel).toLowerCase())
                            ? 'Same pattern as last survey'
                            : 'Changed since your previous survey';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: riskColor.withValues(alpha: 0.16),
                          child: Text(_riskEmoji(item.riskLevel)),
                        ),
                        title: Text(
                          '${_riskLabel(item.riskLevel)} - ${_formatDateTime(item.createdAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '$insight\n$trendNote',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          tooltip: 'More',
                          onSelected: (value) {
                            if (value == 'open') {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _SurveyHistoryDetailPage(entry: item),
                                ),
                              );
                              return;
                            }
                            if (value == 'delete') {
                              _confirmAndDeleteSurvey(uid: uid, entry: item);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'open',
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new, size: 18),
                                  SizedBox(width: 8),
                                  Text('Open details'),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Delete survey'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _SurveyHistoryDetailPage(entry: item),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HistorySurveyEntry {
  const _HistorySurveyEntry({
    required this.docId,
    required this.createdAt,
    required this.riskLevel,
    required this.riskScore,
    required this.factors,
    required this.recommendations,
    required this.resultPayload,
  });

  final String docId;
  final DateTime createdAt;
  final String riskLevel;
  final double riskScore;
  final List<String> factors;
  final List<String> recommendations;
  final Map<String, dynamic> resultPayload;
}

class _SurveyHistoryDetailPage extends StatelessWidget {
  const _SurveyHistoryDetailPage({required this.entry});

  final _HistorySurveyEntry entry;

  Color _riskColor(String level) {
    final normalized = level.toLowerCase();
    if (normalized == 'low') return const Color(0xFF1FA45B);
    if (normalized == 'moderate') return const Color(0xFFE2A50D);
    if (normalized == 'high') return const Color(0xFFD8433E);
    return const Color(0xFF6B7280);
  }

  String _riskLabel(String level) {
    final normalized = level.toLowerCase();
    if (normalized == 'low') return 'LOW';
    if (normalized == 'moderate') return 'MODERATE';
    if (normalized == 'high') return 'HIGH';
    return 'UNKNOWN';
  }

  String _humanize(String text) {
    return text
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final confidence =
        ((entry.resultPayload['confidence'] as num?)?.toDouble() ?? 0.0) * 100;
    final factors = entry.factors.take(5).map(_humanize).toList();
    final recommendations = entry.recommendations
        .take(6)
        .map(_humanize)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Survey Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _riskColor(entry.riskLevel).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _riskColor(entry.riskLevel).withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Risk: ${_riskLabel(entry.riskLevel)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: _riskColor(entry.riskLevel),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Confidence: ${confidence.toStringAsFixed(0)}%'),
                  const SizedBox(height: 4),
                  Text('Score: ${entry.riskScore.toStringAsFixed(1)}'),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM d, yyyy h:mm a').format(entry.createdAt)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Main Factors',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (factors.isEmpty)
              const Text('No factors captured for this survey.')
            else
              ...factors.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $f'),
                  )),
            const SizedBox(height: 16),
            const Text(
              'Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (recommendations.isEmpty)
              const Text('No recommendations captured for this survey.')
            else
              ...recommendations.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $r'),
                  )),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push(
                  ResultPage.routePath,
                  extra: entry.resultPayload,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Full Result Screen'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go(NearbyHospitalsPage.routePath),
                icon: const Icon(Icons.local_hospital_outlined),
                label: const Text('Nearby Hospitals'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
