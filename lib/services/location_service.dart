import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';

class NearbyHospital {
  final String name;
  final String address;
  final double? distanceKm;
  final String? mapsUrl;

  const NearbyHospital({
    required this.name,
    required this.address,
    this.distanceKm,
    this.mapsUrl,
  });
}

class LocationService {
  Future<NearbyHospital?> getNearestHospital() async {
    if (AppConstants.nearestHospitalUrl.isEmpty) {
      return null;
    }

    try {
      final position = await _getPosition();
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken(true);
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      final resp = await http.post(
        Uri.parse(AppConstants.nearestHospitalUrl),
        headers: headers,
        body: jsonEncode({
          'lat': position.latitude,
          'lng': position.longitude,
          'radius': AppConstants.googlePlacesRadiusMeters,
        }),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! Map) return null;

      final name = (data['name'] ?? 'Hospital').toString();
      final address = (data['address'] ?? 'Nearby hospital').toString();
      final distanceRaw = data['distance_km'];
      final distanceKm = distanceRaw is num ? distanceRaw.toDouble() : null;
      final mapsUrl = data['maps_url']?.toString();

      return NearbyHospital(
        name: name,
        address: address,
        distanceKm: distanceKm,
        mapsUrl: mapsUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Position> _getPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location services are disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}
