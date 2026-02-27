// File generated using FlutterFire CLI.
// Run: dart pub global run flutterfire_cli:flutterfire configure
// Then replace this file or use the generated one.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'run the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAWshaSBfgD-o52fUpSNoTY-TkXZ4uqBjc',
    appId: '1:476385587125:android:fe80538a63bd5dffbc73fc',
    messagingSenderId: '476385587125',
    projectId: 'editai-3d616',
    storageBucket: 'editai-3d616.firebasestorage.app',
  );

  /// Placeholder - run `flutterfire configure` to replace with your project values.

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDkXN4mN9gofrznT6WvCfoFvjnDHWDQcrw',
    appId: '1:476385587125:ios:7ed12f4757000f9bbc73fc',
    messagingSenderId: '476385587125',
    projectId: 'editai-3d616',
    storageBucket: 'editai-3d616.firebasestorage.app',
    iosBundleId: 'com.example.editaiapp',
  );

  /// Placeholder - run `flutterfire configure` to replace with your project values.
}