import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/saved_hospital_service.dart';

enum _NearbyViewMode { list, map }

class NearbyHospitalsPage extends StatefulWidget {
  const NearbyHospitalsPage({super.key});

  static const routePath = '/nearby-hospitals';

  @override
  State<NearbyHospitalsPage> createState() => _NearbyHospitalsPageState();
}

class _NearbyHospitalsPageState extends State<NearbyHospitalsPage> {
  static const String _geoapifyApiKey = '2f3d44dca2ef403c835a08dad0946602';
  static const String _googlePlacesApiKey = '';

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _hospitals = <Map<String, dynamic>>[];
  _NearbyViewMode _viewMode = _NearbyViewMode.list;

  static const List<Map<String, dynamic>> _fallbackHospitals = [
    {
      'name': 'Apollo Hospitals',
      'specialization': 'Orthopedics',
      'rating': '4.5',
      'phone': '+91-1860-500-1066',
      'address': 'Jubilee Hills, Hyderabad',
      'lat': 17.4239,
      'lng': 78.4162,
    },
    {
      'name': 'Yashoda Hospitals',
      'specialization': 'Orthopedics',
      'rating': '4.3',
      'phone': '+91-40-4567-4567',
      'address': 'Somajiguda, Hyderabad',
      'lat': 17.4244,
      'lng': 78.4532,
    },
    {
      'name': 'KIMS Hospitals',
      'specialization': 'Orthopedics',
      'rating': '4.2',
      'phone': '+91-40-4488-5000',
      'address': 'Secunderabad, Hyderabad',
      'lat': 17.4420,
      'lng': 78.4983,
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeHospitals();
  }

  Future<void> _initializeHospitals() async {
    final shouldContinue = await _askLocationConsent();
    if (!shouldContinue) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'nearby_location_permission_required'.tr();
      });
      return;
    }

    final hasLocation = await _ensureLocationAccess();
    if (!hasLocation) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'nearby_location_permission_required'.tr();
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final hospitals = await _fetchNearbyHospitals(position);

      if (!mounted) {
        return;
      }

      setState(() {
        _hospitals = hospitals.isEmpty ? _buildFallbackWithDistance(position) : hospitals;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hospitals = _buildFallbackWithDistance(null);
        _isLoading = false;
      });
    }
  }

  Future<bool> _askLocationConsent() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('nearby_location_access_title'.tr()),
          content: Text('nearby_location_access_body'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('continue'.tr()),
            ),
          ],
        );
      },
    );
    return answer == true;
  }

  Future<bool> _ensureLocationAccess() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<List<Map<String, dynamic>>> _fetchNearbyHospitals(Position position) async {
    final geoapifyHospitals = await _fetchNearbyHospitalsFromGeoapify(position);
    if (geoapifyHospitals.isNotEmpty) {
      return geoapifyHospitals;
    }

    final googleHospitals = await _fetchNearbyHospitalsFromGoogle(position);
    if (googleHospitals.isNotEmpty) {
      return googleHospitals;
    }

    // Fallback to OSM if Places API is unavailable or key is missing.
    return _fetchNearbyHospitalsFromOpenStreetMap(position);
  }

  Future<List<Map<String, dynamic>>> _fetchNearbyHospitalsFromGeoapify(
    Position position,
  ) async {
    if (_geoapifyApiKey.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final uri = Uri.https(
      'api.geoapify.com',
      '/v2/places',
      {
        'categories': 'healthcare.hospital',
        'filter': 'circle:${position.longitude},${position.latitude},20000',
        'bias': 'proximity:${position.longitude},${position.latitude}',
        'limit': '12',
        'lang': context.locale.languageCode,
        'apiKey': _geoapifyApiKey,
      },
    );

    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return <Map<String, dynamic>>[];
    }

    final features = (decoded['features'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();

    final hospitals = <Map<String, dynamic>>[];
    for (final feature in features) {
      final properties = feature['properties'];
      if (properties is! Map<String, dynamic>) {
        continue;
      }

      final name = (properties['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }

      final lat = (properties['lat'] as num?)?.toDouble();
      final lng = (properties['lon'] as num?)?.toDouble();

      final distanceAndEta = _distanceAndEta(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      final phone = (properties['phone'] ?? properties['contact_phone'] ?? '').toString().trim();
      final address = (properties['formatted'] ?? properties['address_line2'] ?? '').toString().trim();

      hospitals.add({
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'specialization': 'Orthopedics',
        'phone': phone,
        'rating': 'N/A',
        'distance': distanceAndEta['distance'],
        'eta': distanceAndEta['eta'],
      });
    }

    return hospitals.take(8).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchNearbyHospitalsFromGoogle(
    Position position,
  ) async {
    if (_googlePlacesApiKey.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final nearbyUri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/nearbysearch/json',
      {
        'location': '${position.latitude},${position.longitude}',
        'radius': '20000',
        'type': 'hospital',
        'keyword': 'orthopedic',
        'rankby': 'prominence',
        'language': context.locale.languageCode,
        'key': _googlePlacesApiKey,
      },
    );

    final nearbyResponse = await http.get(nearbyUri);
    if (nearbyResponse.statusCode < 200 || nearbyResponse.statusCode >= 300) {
      return <Map<String, dynamic>>[];
    }

    final nearbyDecoded = jsonDecode(nearbyResponse.body);
    if (nearbyDecoded is! Map<String, dynamic>) {
      return <Map<String, dynamic>>[];
    }

    final placesStatus = (nearbyDecoded['status'] ?? '').toString();
    if (placesStatus != 'OK' && placesStatus != 'ZERO_RESULTS') {
      return <Map<String, dynamic>>[];
    }

    final places = (nearbyDecoded['results'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .take(8)
        .toList();

    final hospitals = <Map<String, dynamic>>[];
    for (final place in places) {
      final placeId = (place['place_id'] ?? '').toString();
      final name = (place['name'] ?? '').toString().trim();
      if (placeId.isEmpty || name.isEmpty) {
        continue;
      }

      final geometry = place['geometry'];
      final location = geometry is Map<String, dynamic>
          ? (geometry['location'] as Map<String, dynamic>?)
          : null;

      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();

      final distanceAndEta = _distanceAndEta(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      final details = await _fetchPlaceDetails(placeId);

      final ratingValue = (place['rating'] as num?)?.toDouble();
      final rating = ratingValue == null ? 'N/A' : ratingValue.toStringAsFixed(1);

      hospitals.add({
        'name': name,
        'address': (details['formatted_address'] ?? place['vicinity'] ?? '').toString(),
        'lat': lat,
        'lng': lng,
        'specialization': 'Orthopedics',
        'phone': (details['formatted_phone_number'] ?? '').toString(),
        'rating': rating,
        'distance': distanceAndEta['distance'],
        'eta': distanceAndEta['eta'],
      });
    }

    return hospitals;
  }

  Future<Map<String, dynamic>> _fetchPlaceDetails(String placeId) async {
    if (_googlePlacesApiKey.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final detailsUri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'formatted_phone_number,formatted_address',
        'language': context.locale.languageCode,
        'key': _googlePlacesApiKey,
      },
    );

    final detailsResponse = await http.get(detailsUri);
    if (detailsResponse.statusCode < 200 || detailsResponse.statusCode >= 300) {
      return <String, dynamic>{};
    }

    final detailsDecoded = jsonDecode(detailsResponse.body);
    if (detailsDecoded is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }

    final status = (detailsDecoded['status'] ?? '').toString();
    if (status != 'OK') {
      return <String, dynamic>{};
    }

    final result = detailsDecoded['result'];
    if (result is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchNearbyHospitalsFromOpenStreetMap(
    Position position,
  ) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?format=jsonv2&limit=12&q=orthopedic%20hospital%20near%20${position.latitude},${position.longitude}',
    );

    final response = await http.get(
      uri,
      headers: {'User-Agent': 'OsteoCarePlus/1.0 (health app)'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return <Map<String, dynamic>>[];
    }

    final hospitals = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final displayName = (item['display_name'] ?? '').toString();
      if (displayName.isEmpty) {
        continue;
      }

      final lat = double.tryParse((item['lat'] ?? '').toString());
      final lng = double.tryParse((item['lon'] ?? '').toString());
      final name = displayName.split(',').first.trim();

      final distanceAndEta = _distanceAndEta(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      hospitals.add({
        'name': name,
        'address': displayName,
        'lat': lat,
        'lng': lng,
        'specialization': 'Orthopedics',
        'phone': '',
        'rating': 'N/A',
        'distance': distanceAndEta['distance'],
        'eta': distanceAndEta['eta'],
      });
    }

    return hospitals.take(8).toList();
  }

  List<Map<String, dynamic>> _buildFallbackWithDistance(Position? position) {
    return _fallbackHospitals.map((hospital) {
      final lat = hospital['lat'] as double?;
      final lng = hospital['lng'] as double?;
      final distanceAndEta = position == null
          ? {'distance': 'N/A', 'eta': 'N/A'}
          : _distanceAndEta(position.latitude, position.longitude, lat, lng);

      return {
        ...hospital,
        'distance': distanceAndEta['distance'],
        'eta': distanceAndEta['eta'],
      };
    }).toList();
  }

  Map<String, String> _distanceAndEta(
    double fromLat,
    double fromLng,
    double? toLat,
    double? toLng,
  ) {
    if (toLat == null || toLng == null) {
      return {'distance': 'N/A', 'eta': 'N/A'};
    }

    final meters = Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
    final km = meters / 1000;

    // Simple ETA estimate using 28 km/h urban speed.
    final minutes = (km / 28 * 60).round().clamp(1, 180);

    return {
      'distance': '${km.toStringAsFixed(1)} km',
      'eta': '$minutes min',
    };
  }

  Future<void> _callHospital(Map<String, dynamic> hospital) async {
    final phone = (hospital['phone'] ?? '').toString().trim();
    if (phone.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('nearby_call_unavailable'.tr())),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('nearby_call_failed'.tr())),
      );
    }
  }

  Future<void> _navigateHospital(Map<String, dynamic> hospital) async {
    final lat = double.tryParse((hospital['lat'] ?? '').toString());
    final lng = double.tryParse((hospital['lng'] ?? '').toString());
    final name = (hospital['name'] ?? '').toString();
    final address = (hospital['address'] ?? '').toString();

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

  Future<void> _saveHospital(Map<String, dynamic> hospital) async {
    final added = await SavedHospitalService.saveHospital(hospital);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'saved_hospital_added'.tr(args: [(hospital['name'] ?? '').toString()]) : 'saved_hospital_exists'.tr(),
        ),
      ),
    );
  }

  Widget _buildHospitalCard(Map<String, dynamic> hospital) {
    final name = (hospital['name'] ?? '').toString();
    final distance = (hospital['distance'] ?? 'N/A').toString();
    final eta = (hospital['eta'] ?? 'N/A').toString();
    final rating = (hospital['rating'] ?? 'N/A').toString();
    final specialization = (hospital['specialization'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text('${'nearby_distance_eta'.tr()}: $distance • $eta'),
            Text('${'nearby_rating'.tr()}: $rating'),
            Text('${'nearby_specialization'.tr()}: $specialization'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _callHospital(hospital),
                  icon: const Icon(Icons.call_outlined),
                  label: Text('nearby_call'.tr()),
                ),
                FilledButton.icon(
                  onPressed: () => _navigateHospital(hospital),
                  icon: const Icon(Icons.navigation_outlined),
                  label: Text('nearby_navigate'.tr()),
                ),
                TextButton.icon(
                  onPressed: () => _saveHospital(hospital),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text('nearby_save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapMode() {
    if (_hospitals.isEmpty) {
      return Center(child: Text('nearby_no_hospitals_found'.tr()));
    }

    return ListView(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text('nearby_map_hint'.tr()),
            subtitle: Text('nearby_map_hint_subtitle'.tr()),
          ),
        ),
        const SizedBox(height: 8),
        ..._hospitals.map((hospital) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text((hospital['name'] ?? '').toString()),
              subtitle: Text('${(hospital['distance'] ?? '').toString()} • ${(hospital['eta'] ?? '').toString()}'),
              trailing: FilledButton(
                onPressed: () => _navigateHospital(hospital),
                child: Text('nearby_open_map'.tr()),
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('nearby_hospitals_title'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ToggleButtons(
                        isSelected: [
                          _viewMode == _NearbyViewMode.list,
                          _viewMode == _NearbyViewMode.map,
                        ],
                        onPressed: (index) {
                          setState(() {
                            _viewMode = index == 0 ? _NearbyViewMode.list : _NearbyViewMode.map;
                          });
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('nearby_list_view'.tr()),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('nearby_map_view'.tr()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _viewMode == _NearbyViewMode.list
                            ? ListView(
                                children: [
                                  ..._hospitals.map(_buildHospitalCard),
                                ],
                              )
                            : _buildMapMode(),
                      ),
                    ],
                  ),
                ),
    );
  }
}
