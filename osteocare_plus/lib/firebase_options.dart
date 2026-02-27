import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Placeholder Firebase configuration for OssoPulse.
///
/// Replace the API keys and IDs in this file with real values generated
/// by the Firebase console or the FlutterFire CLI before releasing.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: 'WEB_API_KEY',
        appId: 'WEB_APP_ID',
        messagingSenderId: 'WEB_MESSAGING_SENDER_ID',
        projectId: 'WEB_PROJECT_ID',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const FirebaseOptions(
          apiKey: 'ANDROID_API_KEY',
          appId: 'ANDROID_APP_ID',
          messagingSenderId: 'ANDROID_MESSAGING_SENDER_ID',
          projectId: 'ANDROID_PROJECT_ID',
        );
      case TargetPlatform.iOS:
        return const FirebaseOptions(
          apiKey: 'IOS_API_KEY',
          appId: 'IOS_APP_ID',
          messagingSenderId: 'IOS_MESSAGING_SENDER_ID',
          projectId: 'IOS_PROJECT_ID',
        );
      case TargetPlatform.macOS:
        return const FirebaseOptions(
          apiKey: 'MACOS_API_KEY',
          appId: 'MACOS_APP_ID',
          messagingSenderId: 'MACOS_MESSAGING_SENDER_ID',
          projectId: 'MACOS_PROJECT_ID',
        );
      case TargetPlatform.windows:
        return const FirebaseOptions(
          apiKey: 'WINDOWS_API_KEY',
          appId: 'WINDOWS_APP_ID',
          messagingSenderId: 'WINDOWS_MESSAGING_SENDER_ID',
          projectId: 'WINDOWS_PROJECT_ID',
        );
      case TargetPlatform.linux:
        return const FirebaseOptions(
          apiKey: 'LINUX_API_KEY',
          appId: 'LINUX_APP_ID',
          messagingSenderId: 'LINUX_MESSAGING_SENDER_ID',
          projectId: 'LINUX_PROJECT_ID',
        );
      default:
        // Fallback for unsupported platforms.
        return const FirebaseOptions(
          apiKey: 'GENERIC_API_KEY',
          appId: 'GENERIC_APP_ID',
          messagingSenderId: 'GENERIC_MESSAGING_SENDER_ID',
          projectId: 'GENERIC_PROJECT_ID',
        );
    }
  }
}

