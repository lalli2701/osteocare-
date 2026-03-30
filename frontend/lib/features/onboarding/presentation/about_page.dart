import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/presentation/dashboard_wrapper.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const routePath = '/about';

  static const List<Map<String, String>> _team = [
    {'name': 'Bhargav Koushik', 'role': 'Team Lead'},
    {'name': 'Bondada Lalithanjali', 'role': 'Developer'},
    {'name': 'Merugu Susheel Nathan', 'role': 'Developer'},
    {'name': 'Shanmukha Sai Teja', 'role': 'Developer'},
    {'name': 'Chaladi Divya', 'role': 'Developer'},
    {'name': 'Penmetsa Sathwik', 'role': 'Developer'},
  ];

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildMember(String name, String role) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFEFF6FF),
        child: Text(
          initial,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(name),
      subtitle: Text(role),
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
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: const Color(0xFFE8F4FF),
                    child: Icon(
                      Icons.health_and_safety,
                      color: Colors.blue.shade700,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'OsteoCare+',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'AI-Based Bone Health Screening',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            _buildSectionTitle('Purpose'),
            const Text(
              'OsteoCare+ helps users assess bone health risk early using AI.\n\n'
              'It provides personalized recommendations, daily habit tracking, and guidance to prevent osteoporosis before it becomes severe.\n\n'
              'This app is designed for awareness and prevention, not medical diagnosis.',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 22),

            _buildSectionTitle('Built By'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < _team.length; i++) ...[
                      _buildMember(_team[i]['name']!, _team[i]['role']!),
                      if (i != _team.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),

            _buildSectionTitle('App Info'),
            Card(
              child: ListTile(
                title: const Text('Version'),
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

