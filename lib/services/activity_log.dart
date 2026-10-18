import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_actor.dart';
import 'super_admin.dart';

class ActivityLog {
  static Future<void> record(String action, String description, {
    FirebaseFirestore? database, String? branchId, String? eventId,
    Map<String, dynamic> details = const {},
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('lastRole') ?? '';
      if (role.isEmpty) return;
      final db = database ?? FirebaseFirestore.instance;
      final actor = await resolveSessionActor(db, admin: role != 'staff');
      var branches = <String>[];
      if (branchId != null && branchId.isNotEmpty) {
        branches = [branchId];
      } else if (role != SuperAdmin.role) {
        final profile = await findAccountProfile(db, actor.id);
        branches = (profile?.data()?['branchIds'] as List? ?? []).map((id) => '$id').toList();
      }
      await db.collection('activity_logs').doc(eventId).set({
        'action': action, 'description': description,
        'actorId': actor.id, 'actorName': actor.name,
        'actorPublicId': actor.publicId, 'actorRole': role,
        'branchIds': branches, 'details': details,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('Activity log could not be saved: $error');
    }
  }
}
