import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

/// Firebase configuration and initialization
/// Call [initializeFirebase] in main() before runApp()
Future<void> initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    print('Firebase initialized successfully');
  } catch (e, st) {
    print('Error initializing Firebase: $e');
    print(st);
    rethrow;
  }
}

/// Firestore and Storage references
final firestore = FirebaseFirestore.instance;
