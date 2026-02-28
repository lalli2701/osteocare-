import 'package:permission_handler/permission_handler.dart';

/// Service for managing microphone and other app permissions
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();

  factory PermissionService() {
    return _instance;
  }

  PermissionService._internal();

  /// Request microphone permission
  /// Returns true if permission is granted
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Check if microphone permission is already granted
  Future<bool> hasMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Open app settings to manually enable permissions
  Future<bool> openAppSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      return false;
    }
  }

  /// Check and get microphone permission with fallback to settings
  /// Returns true if permission is available
  Future<bool> ensureMicrophonePermission() async {
    try {
      // First check if already granted
      final hasPermission = await hasMicrophonePermission();
      if (hasPermission) {
        return true;
      }

      // Request permission if not granted
      final granted = await requestMicrophonePermission();
      if (granted) {
        return true;
      }

      // Return false - user needed to grant via settings
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get platform-specific permission status message
  String getPermissionStatusMessage(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return 'Microphone permission granted';
      case PermissionStatus.denied:
        return 'Microphone permission denied. Enable in app settings to use voice input.';
      case PermissionStatus.restricted:
        return 'Microphone permission is restricted on this device';
      case PermissionStatus.limited:
        return 'Microphone permission is limited';
      case PermissionStatus.permanentlyDenied:
        return 'Microphone permission permanently denied. Enable in app settings to use voice input.';
      case PermissionStatus.provisional:
        return 'Microphone permission is provisional';
    }
  }
}
