import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'profile_avatar.dart';

Future<void> showAssignedBranchStaff(
  BuildContext context,
  String branchId,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    backgroundColor: Colors.white,
    child: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * .65,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .snapshots(),
        builder: (context, branch) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('staff_requests')
                  .snapshots(),
              builder: (context, staff) {
                if (branch.hasError || staff.hasError)
                  return const Center(
                    child: Text('Unable to load branch staff.'),
                  );
                if (!branch.hasData || !staff.hasData)
                  return const Center(child: CircularProgressIndicator());
                final data = branch.data!.data() ?? {};
                final ids = (data['staffIds'] as List? ?? [])
                    .map((id) => '$id')
                    .toSet();
                final members = staff.data!.docs.where((doc) {
                  final row = doc.data();
                  return row['isDeleted'] != true &&
                      (ids.contains(doc.id) ||
                          ids.contains(row['uid']) ||
                          ids.contains(row['userId']) ||
                          ids.contains(row['staffId']) ||
                          (row['branchIds'] as List? ?? []).contains(branchId));
                }).toList();
                return Column(
                  children: [
                    ListTile(
                      title: const Text(
                        'Branch staff',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${data['name'] ?? 'Branch'} • ${members.length} assigned',
                      ),
                      trailing: IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: members.isEmpty
                          ? const Center(
                              child: Text('No staff assigned to this branch.'),
                            )
                          : ListView.builder(
                              itemCount: members.length,
                              itemBuilder: (context, index) {
                                final row = members[index].data();
                                return ListTile(
                                  leading: ProfileAvatar(data: row),
                                  title: Text(
                                    '${row['firstName'] ?? ''} ${row['lastName'] ?? ''}'
                                        .trim(),
                                  ),
                                  subtitle: Text('${row['staffId'] ?? ''}'),
                                  trailing: const Icon(
                                    Icons.check_circle_outline,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      ),
    ),
  ),
);
