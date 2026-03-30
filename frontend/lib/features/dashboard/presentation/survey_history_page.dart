import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/user_session.dart';
import 'dashboard_wrapper.dart';

class SurveyHistoryPage extends StatelessWidget {
  const SurveyHistoryPage({super.key});

  static const routePath = '/survey-history';

  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildHistoryStream() {
    final uid = UserSession.instance.userId;
    if (uid == null || uid.isEmpty) {
      return null;
    }

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

  @override
  Widget build(BuildContext context) {
    final stream = _buildHistoryStream();

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
      body: stream == null
          ? const Center(
              child: Text('Sign in to view survey history.'),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
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
                  return const Center(
                    child: Text('No survey history available yet.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final createdAt = data['createdAt'];
                    final createdDate = createdAt is Timestamp
                        ? createdAt.toDate()
                        : DateTime.now();
                    final riskLevel = data['riskLevel']?.toString();
                    final riskScore = (data['riskScore'] as num?)?.toDouble();

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          child: const Icon(Icons.assignment_turned_in_outlined),
                        ),
                        title: Text(_riskLabel(riskLevel)),
                        subtitle: Text(
                          '${DateFormat('yyyy-MM-dd').format(createdDate)}\nScore: ${riskScore?.toStringAsFixed(1) ?? '-'}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
