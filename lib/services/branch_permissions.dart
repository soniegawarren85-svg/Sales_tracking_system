import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_actor.dart';
import 'super_admin.dart';
import 'transaction_settings.dart';

class BranchPermissions {
  static Future<bool> allowed(
    String key, {
    FirebaseFirestore? database,
    String? branchId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (SuperAdmin.isSession(prefs)) return true;
    final role = prefs.getString('lastRole');
    if (role == null) return true;
    if (key == 'allowReceiptHistory') return true;
    if (role == 'admin') {
      if ([
        'adminAllowAllocations',
        'adminAllowReturnApproval',
        'adminAllowReconciliationApproval',
      ].contains(key)) {
        return false;
      }
      if (key == 'allowChecklist') key = 'adminAllowChecklist';
      if (key == 'allowReturns') key = 'adminAllowReturns';
    }
    final db = database ?? FirebaseFirestore.instance;
    final profileFuture = findAccountProfile(
      db,
      prefs.getString('lastUserId') ?? '',
    );
    final settingsFuture = db
        .collection('admin_settings')
        .doc('transactions')
        .get();
    final results = await Future.wait([profileFuture, settingsFuture]);
    final profile = results[0];
    final ids = branchId != null && branchId.isNotEmpty
        ? [branchId]
        : (profile?.data()?['branchIds'] as List? ?? [])
              .map((v) => '$v')
              .toList();
    final settings =
        (results[1] as DocumentSnapshot<Map<String, dynamic>>).data() ?? {};
    return ids.isEmpty
        ? settings[key] != false
        : ids.every((id) => settingsForBranch(settings, id)[key] != false);
  }

  static Future<void> require(
    String key, {
    FirebaseFirestore? database,
    String? branchId,
  }) async {
    if (!await allowed(key, database: database, branchId: branchId)) {
      throw StateError('This action is disabled for your role at this branch.');
    }
  }
}
