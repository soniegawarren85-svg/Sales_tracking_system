import 'package:cloud_firestore/cloud_firestore.dart';

int accountSessionVersion(Map<String, dynamic> data) =>
    (data['sessionLogoutVersion'] as num?)?.toInt() ?? 0;

bool accountSessionRevoked(Map<String, dynamic> data, int acceptedVersion) =>
    accountSessionVersion(data) > acceptedVersion;

Future<void> logOutAccountDevices(FirebaseFirestore db, String accountId) =>
    db.collection('staff_requests').doc(accountId).update({
      'sessionLogoutVersion': FieldValue.increment(1),
      'sessionsLoggedOutAt': FieldValue.serverTimestamp(),
    });
