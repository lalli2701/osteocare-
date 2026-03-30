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
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    } else {
      final query = Uri.encodeComponent('$name $address');
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('nearby_map_open_failed'.tr())),
      );
    }
  }

  Future<void> _removeHospital(Map<String, dynamic> hospital) async {
    await SavedHospitalService.removeHospital(hospital);
    await _loadHospitals();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('saved_hospital_removed'.tr())),
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
              context.go('/dashboard');
            }
          },
        ),
        title: Text('saved_hospitals_title'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hospitals.isEmpty
              ? Center(
                  child: Text('saved_hospitals_empty'.tr()),
                )
              : ListView.separated(
                  itemCount: _hospitals.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final hospital = _hospitals[index];
                    final distance = (hospital['distance'] ?? '').toString();
                    final eta = (hospital['eta'] ?? '').toString();
                    final rating = (hospital['rating'] ?? '').toString();
                    final specialization = (hospital['specialization'] ?? '').toString();

                    return ListTile(
                      title: Text((hospital['name'] ?? '').toString()),
                      subtitle: Text(
                        [
                          if (specialization.isNotEmpty) specialization,
                          if (distance.isNotEmpty) distance,
                          if (eta.isNotEmpty) eta,
                          if (rating.isNotEmpty) '⭐ $rating',
                        ].join(' • '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _navigateToHospital(hospital),
                            icon: const Icon(Icons.directions),
                            tooltip: 'nearby_navigate'.tr(),
                          ),
                          IconButton(
                            onPressed: () => _removeHospital(hospital),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'delete'.tr(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
