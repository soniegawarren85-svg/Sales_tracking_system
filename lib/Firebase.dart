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
    print('Firebase initialized successfully');
  } catch (e, st) {
    print('Error initializing Firebase: $e');
    print(st);
    rethrow;
  }
}

/// Firestore and Storage references
final firestore = FirebaseFirestore.instance;
