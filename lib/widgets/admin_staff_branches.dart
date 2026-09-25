import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'branch_staff_activity_dialog.dart';

String _staffName(Map<String, dynamic> data) {
  final name = ['firstName', 'lastName']
      .map((key) => '${data[key] ?? ''}')
      .where((value) => value.isNotEmpty)
      .join(' ');
  return name.isEmpty ? '${data['staffId'] ?? 'Staff'}' : name;
}

String _staffKey(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
    '${doc.data()['uid'] ?? doc.data()['userId'] ?? doc.id}';

class AdminStaffBranches extends StatelessWidget {
  const AdminStaffBranches({super.key});
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (context, branches) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('staff_requests')
              .snapshots(),
          builder: (context, staff) {
            if (branches.hasError || staff.hasError)
              return const Text('Unable to load branch staff.');
            if (!branches.hasData || !staff.hasData)
              return const Center(child: CircularProgressIndicator());
            final docs = branches.data!.docs
                .where((doc) => doc.data()['isVoided'] != true)
                .toList();
            if (docs.isEmpty)
              return const Text(
                'Create a branch in Allocation to assign staff.',
              );
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 2 : 1;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: docs.map((doc) {
                    final data = doc.data();
                    final ids = (data['staffIds'] as List? ?? [])
                        .map((id) => '$id')
                        .toSet();
                    final members = staff.data!.docs
                        .where(
                          (member) =>
                              ids.contains(_staffKey(member)) &&
                              member.data()['status'] == 'accepted',
                        )
                        .toList();
                    return SizedBox(
                      width:
                          (constraints.maxWidth - (columns - 1) * 14) / columns,
                      child: Card(
                        color: const Color(0xFFFCE4EC),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: InkWell(
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (_) => SizedBox(
                              height: MediaQuery.sizeOf(context).height * .65,
                              child: _BranchStaffSheet(branch: doc.reference),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Staff in ${data['name'] ?? 'Branch'}',
                                  style: const TextStyle(
                                    color: Color(0xFFAD1457),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text('${members.length} assigned staff'),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    ...members
                                        .take(5)
                                        .map(
                                          (member) => Tooltip(
                                            message: _staffName(member.data()),
                                            child: CircleAvatar(
                                              backgroundColor: Colors.white,
                                              foregroundColor: const Color(
                                                0xFFE91E63,
                                              ),
                                              child: Text(
                                                _staffName(
                                                  member.data(),
                                                ).substring(0, 1).toUpperCase(),
                                              ),
                                            ),
                                          ),
                                        ),
                                    if (members.length > 5)
                                      CircleAvatar(
                                        child: Text('+${members.length - 5}'),
                                      ),
                                    if (members.isEmpty)
                                      const CircleAvatar(
                                        backgroundColor: Colors.white,
                                        child: Icon(
                                          Icons.person_outline,
                                          color: Color(0xFFE91E63),
                                        ),
                                      ),
                                  ],
                                ),
                                const Divider(height: 28),
                                TextButton.icon(
                                  onPressed: () => showBranchStaffActivity(
                                    context,
                                    doc.id,
                                    '${data['name'] ?? 'Branch'}',
                                  ),
                                  icon: const Icon(Icons.history_rounded),
                                  label: const Text('View Activity Logs'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFFAD1457),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Row(
                                  children: [
                                    Expanded(
                                      child: Text('View & assign staff'),
                                    ),
                                    Icon(
                                      Icons.arrow_forward,
                                      color: Color(0xFFE91E63),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
  );
}

class _BranchStaffSheet extends StatefulWidget {
  const _BranchStaffSheet({required this.branch});
  final DocumentReference<Map<String, dynamic>> branch;
  @override
  State<_BranchStaffSheet> createState() => _BranchStaffSheetState();
}

class _BranchStaffSheetState extends State<_BranchStaffSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _assign(
    QueryDocumentSnapshot<Map<String, dynamic>> staff,
    bool assign,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final branch = await transaction.get(widget.branch);
        final member = await transaction.get(staff.reference);
        final data = member.data();
        if (branch.data() == null ||
            branch.data()!['isVoided'] == true ||
            data == null)
          throw StateError('Branch or staff is no longer available.');
        final branchIds = (data['branchIds'] as List? ?? [])
            .map((value) => '$value')
            .toList();
        if (assign &&
            (data['status'] != 'accepted' ||
                branchIds.any((id) => id != widget.branch.id)))
          throw StateError('Staff is inactive or assigned to another branch.');
        final ids = (branch.data()!['staffIds'] as List? ?? [])
            .map((value) => '$value')
            .toList();
        final names = (branch.data()!['staffNames'] as List? ?? [])
            .map((value) => '$value')
            .toList();
        while (names.length < ids.length) {
          names.add('Staff');
        }
        final id = _staffKey(staff);
        final index = ids.indexOf(id);
        if (assign && index < 0) {
          ids.add(id);
          names.add(_staffName(data));
        }
        if (!assign && index >= 0) {
          ids.removeAt(index);
          names.removeAt(index);
        }
        transaction.update(widget.branch, {
          'staffIds': ids,
          'staffNames': names,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(staff.reference, {
          'branchIds': assign
              ? FieldValue.arrayUnion([widget.branch.id])
              : FieldValue.arrayRemove([widget.branch.id]),
        });
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Unable to update assignment. The staff may be inactive or assigned elsewhere.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: widget.branch.snapshots(),
    builder: (context, branch) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('staff_requests')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError || branch.hasError)
              return const Center(
                child: Text('Unable to load staff assignments.'),
              );
            if (!snapshot.hasData || !branch.hasData)
              return const Center(child: CircularProgressIndicator());
            final ids = (branch.data!.data()?['staffIds'] as List? ?? [])
                .map((id) => '$id')
                .toSet();
            final staff = snapshot.data!.docs
                .where(
                  (doc) =>
                      '${doc.data()['role']}'.toLowerCase() == 'staff' &&
                      (doc.data()['status'] == 'accepted' ||
                          ids.contains(_staffKey(doc))),
                )
                .toList();
            staff.sort(
              (a, b) => (ids.contains(_staffKey(b)) ? 1 : 0).compareTo(
                ids.contains(_staffKey(a)) ? 1 : 0,
              ),
            );
            return Column(
              children: [
                ListTile(
                  title: Text(
                    'Staff in ${branch.data!.data()?['name'] ?? 'Branch'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  subtitle: const Text('Assigned staff and available accounts'),
                  trailing: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                if (_saving) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      if (staff.isEmpty)
                        const ListTile(
                          title: Text('No available staff accounts.'),
                        ),
                      ...staff.map((doc) {
                        final data = doc.data();
                        final assigned = ids.contains(_staffKey(doc));
                        final elsewhere = (data['branchIds'] as List? ?? [])
                            .any((id) => id != widget.branch.id);
                        return CheckboxListTile(
                          value: assigned,
                          secondary: CircleAvatar(
                            backgroundColor: const Color(0xFFFCE4EC),
                            child: Text(
                              _staffName(data).substring(0, 1).toUpperCase(),
                            ),
                          ),
                          title: Text(_staffName(data)),
                          subtitle: Text(
                            assigned
                                ? (data['status'] == 'accepted'
                                      ? 'Assigned to this branch'
                                      : 'Deactivated')
                                : elsewhere
                                ? 'Assigned to another branch'
                                : 'Available to assign',
                          ),
                          activeColor: const Color(0xFFE91E63),
                          onChanged: _saving || (!assigned && elsewhere)
                              ? null
                              : (value) => _assign(doc, value == true),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
  );
}
