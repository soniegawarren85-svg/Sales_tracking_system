import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/checklist_status.dart';
import '../services/low_stock_reports.dart';

int staffInventoryChecklistBadgeCount(
  Iterable<Map<String, dynamic>> rows, {
  required bool branchAdminExists,
}) {
  if (branchAdminExists) return 0;
  final pending = <String>{};
  for (final row in rows) {
    if (row['isDeleted'] == true || !ChecklistStatus.incomingOpen(row)) {
      continue;
    }
    pending.add('${row['batchId'] ?? row['allocationId'] ?? row['_id'] ?? ''}');
  }
  return pending.length;
}

class StaffInventoryBadge extends StatelessWidget {
  const StaffInventoryBadge({
    super.key,
    required this.userId,
    required this.child,
    this.database,
  });
  final String? userId;
  final Widget child;
  final FirebaseFirestore? database;

  @override
  Widget build(BuildContext context) {
    final uid = userId;
    if (uid == null || uid.isEmpty) return child;
    final db = database ?? FirebaseFirestore.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('staff_requests').doc(uid).snapshots(),
      builder: (context, profile) {
        final data = profile.data?.data() ?? {};
        final publicId = '${data['staffId'] ?? ''}'.trim();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('branches')
              .where(
                'staffIds',
                arrayContainsAny: [uid, if (publicId.isNotEmpty) publicId],
              )
              .snapshots(),
          builder: (context, branches) {
            final scope = {
              uid,
              if (publicId.isNotEmpty) publicId,
              ...(data['branchIds'] as List? ?? []).map((id) => '$id'),
              ...?branches.data?.docs
                  .where((d) => d.data()['isDeleted'] != true)
                  .map((d) => d.id),
            };
            final branchIds = {
              ...(data['branchIds'] as List? ?? []).map((id) => '$id'),
              ...?branches.data?.docs
                  .where((doc) => doc.data()['isDeleted'] != true)
                  .map((doc) => doc.id),
            };
            if (branchIds.isEmpty) return child;
            return FutureBuilder<bool>(
              future: branchHasActiveAdmin(
                firestore: db,
                branchIds: branchIds.toList(),
              ),
              builder: (context, admin) {
                if (admin.hasError) {
                  debugPrint(
                    'Unable to verify branch admin for inventory badge: ${admin.error}',
                  );
                  return Tooltip(
                    message: 'Unable to verify branch checklist ownership.',
                    child: child,
                  );
                }
                if (!admin.hasData || admin.data == true) return child;
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db
                      .collection('allocation_checklist')
                      .where('staffId', whereIn: scope.take(30).toList())
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = staffInventoryChecklistBadgeCount([
                      for (final doc in snapshot.data?.docs ?? [])
                        {...doc.data(), '_id': doc.id},
                    ], branchAdminExists: false);
                    return Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      child: child,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
