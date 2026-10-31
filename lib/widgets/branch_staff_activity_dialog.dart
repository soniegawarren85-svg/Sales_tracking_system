import 'inventory_records_table.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import '../services/public_item_id.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

DateTime? sessionTime(dynamic value) =>
    value is Timestamp ? value.toDate() : DateTime.tryParse('$value');
String sessionHours(Map<String, dynamic> session) {
  final start = sessionTime(session['loginAt']);
  final end = sessionTime(session['logoutAt']) ?? DateTime.now();
  if (start == null) return 'Not recorded';
  if (end.isBefore(start)) return 'Invalid times';
  final minutes = end.difference(start).inMinutes;
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

Future<void> showBranchStaffActivity(
  BuildContext context,
  String branchId,
  String branchName,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      BranchStaffActivityDialog(branchId: branchId, branchName: branchName),
);

class BranchStaffActivityDialog extends StatefulWidget {
  const BranchStaffActivityDialog({
    super.key,
    required this.branchId,
    required this.branchName,
    this.firestore,
    this.userId,
  });
  final String branchId, branchName;
  final String? userId;
  final FirebaseFirestore? firestore;
  @override
  State<BranchStaffActivityDialog> createState() =>
      _BranchStaffActivityDialogState();
}

class _BranchStaffActivityDialogState extends State<BranchStaffActivityDialog> {
  String _search = '';
  DateTime? _date = DateUtils.dateOnly(DateTime.now());
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;

  List<Query<Map<String, dynamic>>> _sessionQueries(
    List<String> assignedUserIds,
  ) {
    final collection = _firestore.collection('staff_login_sessions');
    if (widget.userId != null) {
      return [collection.where('userId', isEqualTo: widget.userId)];
    }
    if (assignedUserIds.isEmpty) {
      return [collection.where('branchId', isEqualTo: widget.branchId)];
    }
    return [
      for (var start = 0; start < assignedUserIds.length; start += 30)
        collection.where(
          'userId',
          whereIn: assignedUserIds.skip(start).take(30).toList(),
        ),
    ];
  }

  Widget _sessionList(List<String> assignedUserIds) => _sessionQueryList(
    _sessionQueries(assignedUserIds),
    0,
    const [],
  );

  Widget _sessionQueryList(
    List<Query<Map<String, dynamic>>> queries,
    int index,
    List<Map<String, dynamic>> records,
  ) {
    if (index == queries.length) return _filteredSessions(records);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: queries[index].snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load session logs. Check connection and access permissions.',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _sessionQueryList(
            queries,
            index + 1,
            [...records, ...snapshot.data!.docs.map((doc) => doc.data())],
          );
        },
      );
  }

  Widget _filteredSessions(List<Map<String, dynamic>> records) {
    records.sort(
      (a, b) => (sessionTime(b['loginAt']) ?? DateTime(1970))
          .compareTo(sessionTime(a['loginAt']) ?? DateTime(1970)),
    );
    final filtered = records.where((row) {
      final date = sessionTime(row['loginAt']);
      final role = _sessionRole(row);
      return (_date == null ||
              (date != null &&
                  date.year == _date!.year &&
                  date.month == _date!.month &&
                  date.day == _date!.day)) &&
          ('$role ${row.values.join(' ')} ${publicItemId((row['staffId'] ?? '').toString())}')
              .toLowerCase()
              .contains(_search);
    }).toList();
    return StaffSessionTable(sessions: filtered);
  }

  String _sessionRole(Map<String, dynamic> session) {
    final role = '${session['role'] ?? session['type'] ?? ''}'
        .trim()
        .toLowerCase();
    return switch (role) {
      'admin' => 'Admin',
      'super_admin' => 'Super Admin',
      _ => 'Staff',
    };
  }
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SizedBox(
      width: 1200,
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.userId == null
                        ? 'Activity Logs - ${widget.branchName}'
                        : 'My Activity Logs',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close activity logs',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search account, role, name or ID',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                  ),
                ),
                IconButton(
                  tooltip: _date == null
                      ? 'Filter by date'
                      : MaterialLocalizations.of(
                          context,
                        ).formatShortDate(_date!),
                  icon: const Icon(
                    Icons.calendar_month,
                    color: AppColors.primaryDark,
                  ),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _date ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null && mounted) setState(() => _date = date);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.userId != null
                ? _sessionList(const [])
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _firestore
                        .collection('branches')
                        .doc(widget.branchId)
                        .snapshots(),
                    builder: (context, branch) {
                      if (branch.hasError) {
                        return const Center(
                          child: Text('Unable to load branch staff.'),
                        );
                      }
                      if (!branch.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      final userIds = (branch.data!.data()?['staffIds']
                                  as List? ??
                              [])
                          .map((id) => '$id'.trim())
                          .where((id) => id.isNotEmpty)
                          .toSet()
                          .toList();
                      return _sessionList(userIds);
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class StaffSessionTable extends StatelessWidget {
  const StaffSessionTable({super.key, required this.sessions});
  final List<Map<String, dynamic>> sessions;
  Widget avatar(String photo) {
    const fallback = Icon(
      Icons.account_circle,
      size: 36,
      color: AppColors.primary,
    );
    if (photo.isEmpty) return fallback;
    try {
      if (photo.startsWith('data:image/')) {
        return Image.memory(
          base64Decode(photo.split(',').last),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
      }
      return Image.network(
        photo,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text('No recorded login sessions for this branch.'),
      );
    }
    String date(dynamic raw) {
      final time = sessionTime(raw)?.toLocal();
      if (time == null) return 'Not recorded';
      final local = MaterialLocalizations.of(context);
      return '${local.formatMediumDate(time)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: InventoryRecordsTable(
        headings: const [
          'Staff ID',
          'Staff',
          'Account',
          'Login',
          'Logout',
          'Status',
          'Hours',
          'IP address',
        ],
        flex: const {
          0: 1,
          1: 2,
          2: 1,
          3: 1.8,
          4: 1.8,
          5: 1,
          6: .8,
          7: 1.5,
        },
        rows: sessions
            .map(
              (session) => <Widget>[
                Text(publicItemId('${session['staffId'] ?? 'Not recorded'}')),
                Text('${session['staffName'] ?? 'Not recorded'}'),
                Text(_roleLabel(session)),
                Text(date(session['loginAt'])),
                Text(
                  session['logoutAt'] == null ? '—' : date(session['logoutAt']),
                ),
                Text(
                  session['logoutAt'] == null ? 'Active' : 'Offline',
                  style: TextStyle(
                    color: session['logoutAt'] == null
                        ? Colors.green.shade700
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(sessionHours(session)),
                SelectableText('${session['ipAddress'] ?? 'Not recorded'}'),
              ],
            )
            .toList(),
      ),
    );
  }

  String _roleLabel(Map<String, dynamic> session) {
    final role = '${session['role'] ?? session['type'] ?? ''}'
        .trim()
        .toLowerCase();
    return switch (role) {
      'admin' => 'Admin',
      'super_admin' => 'Super Admin',
      _ => 'Staff',
    };
  }
}
