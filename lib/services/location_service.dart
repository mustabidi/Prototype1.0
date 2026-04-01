import 'package:geolocator/geolocator.dart';

/// Handles GPS permission and location fetching.
/// Used post-login for the hybrid location strategy.
class LocationService {
  /// Check if location services are enabled and permissions granted.
  Future<bool> hasPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Request location permission from the user.
  /// Returns true if granted.
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Get current GPS position.
  /// Returns null if permission denied or service unavailable.
  Future<Position?> getCurrentPosition({bool promptIfDenied = false}) async {
    bool granted = await hasPermission();
    if (!granted) {
      if (!promptIfDenied) return null;
      granted = await requestPermission();
      if (!granted) return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return null;
    }
  }
}
