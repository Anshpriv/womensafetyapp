import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web is not configured.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS is not configured.');
      case TargetPlatform.macOS:
        throw UnsupportedError('macOS is not configured.');
      case TargetPlatform.windows:
        throw UnsupportedError('Windows is not configured.');
      case TargetPlatform.linux:
        throw UnsupportedError('Linux is not configured.');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ✅ ANDROID CONFIG (FROM YOUR google-services.json)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyBGdT5WKs151aNXvYRvcgyoxwoBbi98f08",
    appId: "1:4890750983:android:4dc7cc669095e92b0b3aa2",
    messagingSenderId: "4890750983",
    projectId: "womensafetyapp-990d4",
    storageBucket: "womensafetyapp-990d4.firebasestorage.app",
  );
}
