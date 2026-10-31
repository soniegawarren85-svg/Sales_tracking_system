import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> voidBranchAndUnassignStaff(
  FirebaseFirestore firestore,
  String branchId,
) async {
  final branchRef = firestore.collection('branches').doc(branchId);
  await firestore.runTransaction((transaction) async {
    final branchSnapshot = await transaction.get(branchRef);
    final branch = branchSnapshot.data();
    if (branch == null) {
      throw StateError('The branch no longer exists.');
    }

    final staffIds = (branch['staffIds'] as List? ?? [])
        .map((id) => '$id'.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final staffRefs = staffIds
        .map((staffId) => firestore.collection('staff_requests').doc(staffId))
        .toList();
    final staffSnapshots = await Future.wait(staffRefs.map(transaction.get));

    transaction.update(branchRef, {
      'isVoided': true,
      'voidedAt': FieldValue.serverTimestamp(),
      'staffIds': <String>[],
      'staffNames': <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (var index = 0; index < staffSnapshots.length; index++) {
      final staffData = staffSnapshots[index].data();
      if (staffData == null) continue;
      transaction.update(staffRefs[index], {
        'branchIds': <String>[],
        'requiresBranchAssignment': true,
      });
    }
  });
}
