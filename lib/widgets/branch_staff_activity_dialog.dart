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
  late final sessions = (widget.firestore ?? FirebaseFirestore.instance)
      .collection('staff_login_sessions')
      .where(
        widget.userId == null ? 'branchId' : 'userId',
        isEqualTo: widget.userId ?? widget.branchId,
      )
      .snapshots();
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.all(20),
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
                      fontSize: 21,
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
                      hintText: 'Search staff name or ID',
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
                if (_date != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _date = null),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: sessions,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(
                    child: Text(
                      'Unable to load session logs. Check connection and access permissions.',
                    ),
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final records = snapshot.data!.docs
                    .map((doc) => doc.data())
                    .toList();
                records.sort(
                  (a, b) => (sessionTime(b['loginAt']) ?? DateTime(1970))
                      .compareTo(sessionTime(a['loginAt']) ?? DateTime(1970)),
                );
                final latest = records;
                final filtered = latest.where((row) {
                  final date = sessionTime(row['loginAt']);
                  return (_date == null ||
                          (date != null &&
                              date.year == _date!.year &&
                              date.month == _date!.month &&
                              date.day == _date!.day)) &&
                      (row.values.join(' ') +
                              ' ' +
                              publicItemId((row['staffId'] ?? '').toString()))
                          .toLowerCase()
                          .contains(_search);
                }).toList();
                return StaffSessionTable(sessions: filtered);
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
      if (photo.startsWith('data:image/'))
        return Image.memory(
          base64Decode(photo.split(',').last),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      return Image.network(
        photo,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty)
      return const Center(
        child: Text('No recorded login sessions for this branch.'),
      );
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
          'Login',
          'Logout',
          'Status',
          'Hours',
          'IP address',
        ],
        flex: const {0: 1, 1: 2, 2: 1.8, 3: 1.8, 4: 1, 5: .8, 6: 1.5},
        rows: sessions
            .map(
              (session) => <Widget>[
                Text(publicItemId('${session['staffId'] ?? 'Not recorded'}')),
                Text('${session['staffName'] ?? 'Not recorded'}'),
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
}
