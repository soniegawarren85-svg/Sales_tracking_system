import 'package:cloud_firestore/cloud_firestore.dart';

class StaffOnboardingService {
  static bool requiresTutorial(Map<String, dynamic> profile) =>
      profile['onboardingCompleted'] == false;

  static Future<bool> shouldShowTutorial({
    required FirebaseFirestore database,
    required String staffDocumentId,
  }) async {
    if (staffDocumentId.trim().isEmpty || staffDocumentId.contains('/')) {
      throw ArgumentError('A valid staff account is required.');
    }
    final profile = await database
        .collection('staff_requests')
        .doc(staffDocumentId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!profile.exists) {
      throw StateError('The signed-in staff account could not be found.');
    }
    return requiresTutorial(profile.data() ?? const <String, dynamic>{});
  }

  static Future<void> markCompleted({
    required FirebaseFirestore database,
    required String staffDocumentId,
  }) async {
    if (staffDocumentId.trim().isEmpty || staffDocumentId.contains('/')) {
      throw ArgumentError('A valid staff account is required.');
    }
    await database
        .collection('staff_requests')
        .doc(staffDocumentId)
        .update({
          'onboardingCompleted': true,
          'onboardingCompletedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 12));
  }

  static Future<void> completeTutorial({
    required FirebaseFirestore database,
    required String staffDocumentId,
    required bool isReplay,
  }) async {
    if (isReplay) return;
    await markCompleted(database: database, staffDocumentId: staffDocumentId);
  }
}
