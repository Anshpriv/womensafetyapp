import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError('Linux is not configured.');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBGdT5WKs151aNXvYRvcgyoxwoBbi98f08',
    appId: '1:4890750983:android:4dc7cc669095e92b0b3aa2',
    messagingSenderId: '4890750983',
    projectId: 'womensafetyapp-990d4',
    storageBucket: 'womensafetyapp-990d4.firebasestorage.app',
  );

  // ✅ ANDROID CONFIG (FROM YOUR google-services.json)

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBgEJp0WIva4A1lSLFQWRKZMBVUVMOo4Wc',
    appId: '1:4890750983:web:2f6d287ffa80ec420b3aa2',
    messagingSenderId: '4890750983',
    projectId: 'womensafetyapp-990d4',
    authDomain: 'womensafetyapp-990d4.firebaseapp.com',
    storageBucket: 'womensafetyapp-990d4.firebasestorage.app',
    measurementId: 'G-MTVYWW2VWG',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAKPhkhPKrkyb9dfuxFrWzs7H07lmHsRFU',
    appId: '1:4890750983:ios:417b46e59f8b86e90b3aa2',
    messagingSenderId: '4890750983',
    projectId: 'womensafetyapp-990d4',
    storageBucket: 'womensafetyapp-990d4.firebasestorage.app',
    iosBundleId: 'com.example.womensafetyapp',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAKPhkhPKrkyb9dfuxFrWzs7H07lmHsRFU',
    appId: '1:4890750983:ios:417b46e59f8b86e90b3aa2',
    messagingSenderId: '4890750983',
    projectId: 'womensafetyapp-990d4',
    storageBucket: 'womensafetyapp-990d4.firebasestorage.app',
    iosBundleId: 'com.example.womensafetyapp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBgEJp0WIva4A1lSLFQWRKZMBVUVMOo4Wc',
    appId: '1:4890750983:web:435a279d7f5fbe900b3aa2',
    messagingSenderId: '4890750983',
    projectId: 'womensafetyapp-990d4',
    authDomain: 'womensafetyapp-990d4.firebaseapp.com',
    storageBucket: 'womensafetyapp-990d4.firebasestorage.app',
    measurementId: 'G-M6B49M7DVD',
  );

}