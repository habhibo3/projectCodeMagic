// File generated for Staging environment (mlivecast-staging).
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps (Staging).
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAvhKcj2fIjZFInOY52mQQjwBsKTnbryyQ',
    appId: '1:16228190910:web:fb3b64ca73143adaddecef',
    messagingSenderId: '16228190910',
    projectId: 'mlivecast-staging',
    authDomain: 'mlivecast-staging.firebaseapp.com',
    storageBucket: 'mlivecast-staging.firebasestorage.app',
    measurementId: 'G-B8BM2EML0P',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDHZHbMhrdHtWIVreaS72OdCvDn-x9LhlA',
    appId: '1:16228190910:android:4e960f8ee29734dfddecef',
    messagingSenderId: '16228190910',
    projectId: 'mlivecast-staging',
    storageBucket: 'mlivecast-staging.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDWjrugSPhbkCUYqQI9Z-rRfa9G31o4h_c',
    appId: '1:16228190910:ios:0cbae98cc39041f1ddecef',
    messagingSenderId: '16228190910',
    projectId: 'mlivecast-staging',
    storageBucket: 'mlivecast-staging.firebasestorage.app',
    iosBundleId: 'com.contestlive.contestLive',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDWjrugSPhbkCUYqQI9Z-rRfa9G31o4h_c',
    appId: '1:16228190910:ios:0cbae98cc39041f1ddecef',
    messagingSenderId: '16228190910',
    projectId: 'mlivecast-staging',
    storageBucket: 'mlivecast-staging.firebasestorage.app',
    iosBundleId: 'com.contestlive.contestLive',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAvhKcj2fIjZFInOY52mQQjwBsKTnbryyQ',
    appId: '1:16228190910:web:fb3b64ca73143adaddecef',
    messagingSenderId: '16228190910',
    projectId: 'mlivecast-staging',
    authDomain: 'mlivecast-staging.firebaseapp.com',
    storageBucket: 'mlivecast-staging.firebasestorage.app',
  );
}
