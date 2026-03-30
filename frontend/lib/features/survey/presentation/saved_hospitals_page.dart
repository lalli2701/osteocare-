import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/saved_hospital_service.dart';

class SavedHospitalsPage extends StatefulWidget {
  const SavedHospitalsPage({super.key});

  static const routePath = '/saved-hospitals';

  @override
  State<SavedHospitalsPage> createState() => _SavedHospitalsPageState();
}

class _SavedHospitalsPageState extends State<SavedHospitalsPage> {
  List<Map<String, dynamic>> _hospitals = <Map<String, dynamic>>[];
  bool _isLoading = true;
  final Set<int> _expandedIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _loadHospitals();
  }

  Future<void> _loadHospitals() async {
    final hospitals = await SavedHospitalService.getSavedHospitals();
    if (!mounted) {
      return;
    }
    setState(() {
      _hospitals = hospitals;
      _isLoading = false;
    });
  }

  Future<void> _navigateToHospital(Map<String, dynamic> hospital) async {
    final name = (hospital['name'] ?? '').toString();
    final address = (hospital['address'] ?? '').toString();
    final lat = double.tryParse((hospital['lat'] ?? '').toString());
    final lng = double.tryParse((hospital['lng'] ?? '').toString());

    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      );
    } else {
      final query = Uri.encodeComponent('$name $address');
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('nearby_map_open_failed'.tr())));
    }
  }

  Future<void> _removeHospital(Map<String, dynamic> hospital) async {
    await SavedHospitalService.removeHospital(hospital);
    await _loadHospitals();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('saved_hospital_removed'.tr())));
  }

  Future<void> _callDoctor(String phoneNumber) async {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return;
    }

    final normalized = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) {
      return;
    }

    final uri = Uri(scheme: 'tel', path: normalized);
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open dialer')));
    }
  }

  String _firstNonEmpty(
    Map<String, dynamic> hospital,
    List<String> keys, {
    String fallback = '-',
  }) {
    for (final key in keys) {
      final value = (hospital[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
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
              context.go('/dashboard');
            }
          },
        ),
        title: Text('saved_hospitals_title'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hospitals.isEmpty
          ? Center(child: Text('saved_hospitals_empty'.tr()))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _hospitals.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final hospital = _hospitals[index];
                final distance = (hospital['distance'] ?? '').toString();
                final eta = (hospital['eta'] ?? '').toString();
                final rating = (hospital['rating'] ?? '').toString();
                final specialization = (hospital['specialization'] ?? '')
                    .toString();
                final doctorName = _firstNonEmpty(hospital, const [
                  'doctor_name',
                  'doctorName',
                  'doctor',
                  'physician_name',
                ]);
                final doctorSpecialization = _firstNonEmpty(hospital, const [
                  'specialization',
                  'doctor_specialization',
                  'department',
                ]);
                final doctorPhone = _firstNonEmpty(hospital, const [
                  'doctor_phone',
                  'phone',
                  'phone_number',
                  'contact',
                ]);
                final address = _firstNonEmpty(hospital, const [
                  'address',
                  'location',
                ]);
                final expanded = _expandedIndexes.contains(index);

                return Card(
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        if (expanded) {
                          _expandedIndexes.remove(index);
                        } else {
                          _expandedIndexes.add(index);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (hospital['name'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (specialization.isNotEmpty) specialization,
                              if (distance.isNotEmpty) distance,
                              if (eta.isNotEmpty) eta,
                              if (rating.isNotEmpty) '⭐ $rating',
                            ].join(' • '),
                            style: TextStyle(color: Colors.blueGrey.shade700),
                          ),
                          if (expanded) ...[
                            const SizedBox(height: 12),
                            _DetailRow(label: 'Doctor', value: doctorName),
                            _DetailRow(
                              label: 'Specialization',
                              value: doctorSpecialization,
                            ),
                            _DetailRow(
                              label: 'Phone',
                              value: doctorPhone,
                              onTap: doctorPhone == '-'
                                  ? null
                                  : () => _callDoctor(doctorPhone),
                              trailingIcon: doctorPhone == '-'
                                  ? null
                                  : Icons.phone,
                            ),
                            _DetailRow(label: 'Address', value: address),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _navigateToHospital(hospital),
                                  icon: const Icon(Icons.directions),
                                  label: Text('nearby_navigate'.tr()),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _removeHospital(hospital),
                                  icon: const Icon(Icons.delete_outline),
                                  label: Text('delete'.tr()),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.onTap,
    this.trailingIcon,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final content = RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(color: Colors.blueGrey.shade800),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: onTap == null
                ? null
                : TextStyle(
                    color: Colors.blue.shade700,
                    decoration: TextDecoration.underline,
                  ),
          ),
        ],
      ),
    );

    final tappableContent = onTap == null
        ? content
        : GestureDetector(onTap: onTap, child: content);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: trailingIcon == null
          ? tappableContent
          : Row(
              children: [
                Expanded(child: tappableContent),
                IconButton(
                  onPressed: onTap,
                  icon: Icon(
                    trailingIcon,
                    size: 18,
                    color: Colors.blue.shade700,
                  ),
                  tooltip: 'Call',
                ),
              ],
            ),
    );
  }
}
