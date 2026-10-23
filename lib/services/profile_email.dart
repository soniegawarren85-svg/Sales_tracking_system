import 'package:cloud_firestore/cloud_firestore.dart';

String normalizedProfileEmail(Object? value) =>
    '${value ?? ''}'.trim().toLowerCase();

String confirmedProfileEmail(Map<String, dynamic> data) {
  final authEmail = '${data['authEmail'] ?? ''}'.trim();
  return authEmail.isNotEmpty ? authEmail : '${data['email'] ?? ''}'.trim();
}

bool usesLinkedAuthentication(Map<String, dynamic> data) =>
    data['passwordAuthMode'] == 'firebase' ||
    [
      'authEmail',
      'pendingAuthEmail',
      'authUid',
    ].any((key) => '${data[key] ?? ''}'.trim().isNotEmpty);

bool profileReservesEmail(Map<String, dynamic> data, String email) {
  if (data['isDeleted'] == true ||
      data['isVoided'] == true ||
      data['deletedAt'] != null ||
      [
        'deleted',
        'removed',
        'rejected',
      ].contains('${data['status']}'.toLowerCase())) {
    return false;
  }
  return ['email', 'authEmail', 'pendingAuthEmail'].any(
    (key) => normalizedProfileEmail(data[key]) == normalizedProfileEmail(email),
  );
}

Future<bool> profileEmailTaken(
  FirebaseFirestore db,
  String email,
  String ownId, {
  String ownCollection = 'staff_requests',
}) async {
  final results = await Future.wait([
    db
        .collection('staff_requests')
        .get(const GetOptions(source: Source.server)),
    db
        .collection('super_admin_profiles')
        .get(const GetOptions(source: Source.server)),
  ]);
  return results.any(
    (result) => result.docs.any(
      (doc) =>
          !(doc.id == ownId && doc.reference.parent.id == ownCollection) &&
          profileReservesEmail(doc.data(), email),
    ),
  );
}
