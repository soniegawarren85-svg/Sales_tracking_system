import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/checklist_status.dart';

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
            // Match the inventory checklist's branch ownership, including legacy staff allocations.
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('allocation_checklist')
                  .where('staffId', whereIn: scope.take(30).toList())
                  .snapshots(),
              builder: (context, snapshot) {
                final pending = <String>{};
                for (final doc in snapshot.data?.docs ?? []) {
                  final row = doc.data();
                  if (row['isDeleted'] == true ||
                      !ChecklistStatus.incomingOpen(row))
                    continue;
                  pending.add(
                    '${row['batchId'] ?? row['allocationId'] ?? doc.id}',
                  );
                }
                return Badge.count(
                  count: pending.length,
                  isLabelVisible: pending.isNotEmpty,
                  child: child,
                );
              },
            );
          },
        );
      },
    );
  }
}
