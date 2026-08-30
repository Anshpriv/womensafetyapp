// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAljv6_UwP4Pz4g78bQMGKxZlHY_yVvJqQ',
    appId: '1:590673217701:android:cc65b01402187a637de54c',
    messagingSenderId: '590673217701',
    projectId: 'shrimatisetu-dc6a7',
    storageBucket: 'shrimatisetu-dc6a7.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAljv6_UwP4Pz4g78bQMGKxZlHY_yVvJqQ',
    appId: '1:590673217701:android:cc65b01402187a637de54c',
    messagingSenderId: '590673217701',
    projectId: 'shrimatisetu-dc6a7',
    storageBucket: 'shrimatisetu-dc6a7.firebasestorage.app',
    iosBundleId: 'com.womensaftey.app',
  );
}
