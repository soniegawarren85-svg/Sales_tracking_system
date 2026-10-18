import 'profile_avatar.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'branch_staff_activity_dialog.dart';

String _staffName(Map<String, dynamic> data) {
  final name = ['firstName', 'lastName']
      .map((key) => '${data[key] ?? ''}')
      .where((value) => value.isNotEmpty)
      .join(' ');
  return name.isEmpty
      ? '${data['adminId'] ?? data['staffId'] ?? 'Staff'}'
      : name;
}

String _assignmentRole(Map<String, dynamic> data) {
  final role = '${data['role'] ?? ''}'.trim().toLowerCase();
  if (role.isNotEmpty) return role;
  if ('${data['adminId'] ?? ''}'.trim().isNotEmpty) return 'admin';
  if ('${data['staffId'] ?? ''}'.trim().isNotEmpty) return 'staff';
  return '';
}

bool _isActiveForAssignment(Map<String, dynamic> data, String role) {
  final status = '${data['status'] ?? ''}'.trim().toLowerCase();
  return data['isDeleted'] != true &&
      data['isVoided'] != true &&
      data['isDeactivated'] != true &&
      data['isSuspended'] != true &&
      (status == 'accepted' || (role == 'admin' && status.isEmpty));
}

String _staffKey(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
    '${doc.data()['uid'] ?? doc.data()['userId'] ?? doc.id}';

class AdminStaffBranches extends StatelessWidget {
  const AdminStaffBranches({
    super.key,
    this.firestore,
    this.includeAdmins = false,
    this.branchId,
    this.allowAssignment = true,
  });
  final FirebaseFirestore? firestore;
  final bool includeAdmins;
  final String? branchId;
  final bool allowAssignment;
  @override
  Widget build(BuildContext context) {
    final db = firestore ?? FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('branches').snapshots(),
      builder: (context, branches) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('staff_requests').snapshots(),
            builder: (context, staff) {
              if (branches.hasError || staff.hasError) {
                return const Text('Unable to load branch staff.');
              }
              if (!branches.hasData || !staff.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = branches.data!.docs
                  .where(
                    (doc) =>
                        doc.data()['isVoided'] != true &&
                        (branchId == null || doc.id == branchId),
                  )
                  .toList();
              if (docs.isEmpty) {
                return const Text(
                  'Create a branch in Allocation to assign staff.',
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 2 : 1;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: docs.map((doc) {
                        final data = doc.data();
                        final ids = (data['staffIds'] as List? ?? [])
                            .map((id) => '$id')
                            .toSet();
                        final members =
                            staff.data!.docs
                                .where(
                                  (member) =>
                                      ids.contains(_staffKey(member)) &&
                                      member.data()['status'] == 'accepted' &&
                                      (includeAdmins ||
                                          _assignmentRole(member.data()) ==
                                              'staff'),
                                )
                                .toList()
                              ..sort(
                                (a, b) => (a.data()['role'] == 'admin' ? 0 : 1)
                                    .compareTo(
                                      b.data()['role'] == 'admin' ? 0 : 1,
                                    ),
                              );
                        return SizedBox(
                          width: columns == 2
                              ? constraints.maxWidth / 2
                              : constraints.maxWidth * .9,
                          child: Card(
                            color: AppColors.blush,
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
                                  height:
                                      MediaQuery.sizeOf(context).height * .65,
                                  child: _BranchStaffSheet(
                                    includeAdmins: includeAdmins,
                                    allowAssignment: allowAssignment,
                                    branch: doc.reference,
                                    firestore: db,
                                  ),
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
                                        color: AppColors.primaryDark,
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
                                                message: _staffName(
                                                  member.data(),
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    ProfileAvatar(
                                                      data: member.data(),
                                                    ),
                                                    if (includeAdmins)
                                                      Text(
                                                        member.data()['role'] ==
                                                                'admin'
                                                            ? 'Admin'
                                                            : 'Cashier',
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        if (members.length > 5)
                                          CircleAvatar(
                                            child: Text(
                                              '+${members.length - 5}',
                                            ),
                                          ),
                                        if (members.isEmpty)
                                          const CircleAvatar(
                                            backgroundColor: Colors.white,
                                            child: Icon(
                                              Icons.person_outline,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const Divider(height: 28),
                                    FilledButton.icon(
                                      label: const Text('Activity logs'),
                                      onPressed: () => showBranchStaffActivity(
                                        context,
                                        doc.id,
                                        '${data['name'] ?? 'Branch'}',
                                      ),
                                      icon: const Icon(Icons.history_rounded),

                                      style: FilledButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: AppColors.primaryDark,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (allowAssignment)
                                      const Row(
                                        children: [
                                          Expanded(
                                            child: Text('View & assign staff'),
                                          ),
                                          Icon(
                                            Icons.arrow_forward,
                                            color: AppColors.primary,
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
                    ),
                  );
                },
              );
            },
          ),
    );
  }
}

class _BranchStaffSheet extends StatefulWidget {
  const _BranchStaffSheet({
    required this.branch,
    required this.firestore,
    this.includeAdmins = false,
    this.allowAssignment = true,
  });
  final bool includeAdmins;
  final bool allowAssignment;
  final DocumentReference<Map<String, dynamic>> branch;
  final FirebaseFirestore firestore;
  @override
  State<_BranchStaffSheet> createState() => _BranchStaffSheetState();
}

class _BranchStaffSheetState extends State<_BranchStaffSheet> {
  bool _saving = false;
  String? _error;
  String _selectedRole = 'staff';

  Future<void> _assign(
    QueryDocumentSnapshot<Map<String, dynamic>> staff,
    bool assign,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.firestore.runTransaction((transaction) async {
        final branch = await transaction.get(widget.branch);
        final member = await transaction.get(staff.reference);
        final data = member.data();
        if (branch.data() == null ||
            branch.data()!['isVoided'] == true ||
            data == null) {
          throw StateError('Branch or staff is no longer available.');
        }
        final branchIds = (data['branchIds'] as List? ?? [])
            .map((value) => '$value')
            .toList();
        if (assign &&
            (!_isActiveForAssignment(data, _assignmentRole(data)) ||
                branchIds.any((id) => id != widget.branch.id))) {
          throw StateError('Staff is inactive or assigned to another branch.');
        }
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
      if (mounted) {
        setState(
          () => _error =
              'Unable to update assignment. The staff may be inactive or assigned elsewhere.',
        );
      }
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
          stream: widget.firestore.collection('staff_requests').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError || branch.hasError) {
              return const Center(
                child: Text('Unable to load staff assignments.'),
              );
            }
            if (!snapshot.hasData || !branch.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final ids = (branch.data!.data()?['staffIds'] as List? ?? [])
                .map((id) => '$id')
                .toSet();
            final staff = snapshot.data!.docs
                .where(
                  (doc) =>
                      _assignmentRole(doc.data()) ==
                          (widget.includeAdmins ? _selectedRole : 'staff') &&
                      (_isActiveForAssignment(
                            doc.data(),
                            _assignmentRole(doc.data()),
                          ) ||
                          ids.contains(_staffKey(doc))),
                )
                .where((doc) {
                  if (!widget.allowAssignment &&
                      !ids.contains(_staffKey(doc))) {
                    return false;
                  }
                  if (ids.contains(_staffKey(doc))) return true;
                  final branchIds = (doc.data()['branchIds'] as List? ?? [])
                      .map((id) => '$id');
                  return !branchIds.any((id) => id != widget.branch.id);
                })
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
                  subtitle: Text(
                    widget.allowAssignment
                        ? 'Assigned staff and available accounts'
                        : 'Staff assigned to this branch',
                  ),
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
                if (widget.includeAdmins)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Select role to assign',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'staff',
                          child: Text('Staff / Cashier'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: _saving
                          ? null
                          : (role) {
                              if (role != null) {
                                setState(() => _selectedRole = role);
                              }
                            },
                    ),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      if (staff.isEmpty)
                        const ListTile(
                          title: Text('No available accounts for this role.'),
                        ),
                      ...staff.map((doc) {
                        final data = doc.data();
                        final assigned = ids.contains(_staffKey(doc));
                        final elsewhere = (data['branchIds'] as List? ?? [])
                            .any((id) => id != widget.branch.id);
                        final title = Text(
                          '${_staffName(data)}${widget.includeAdmins ? ' • ${_assignmentRole(data) == 'admin' ? 'Admin' : 'Cashier'}' : ''}',
                        );
                        if (!widget.allowAssignment) {
                          return ListTile(
                            leading: ProfileAvatar(data: data),
                            title: title,
                          );
                        }
                        return CheckboxListTile(
                          value: assigned,
                          secondary: ProfileAvatar(data: data),
                          title: title,
                          subtitle: Text(
                            assigned
                                ? (data['status'] == 'accepted'
                                      ? 'Assigned to this branch'
                                      : 'Deactivated')
                                : elsewhere
                                ? 'Assigned to another branch'
                                : 'Available to assign',
                          ),
                          activeColor: AppColors.primary,
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
