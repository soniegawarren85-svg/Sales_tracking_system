import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

DateTime? sessionTime(dynamic value) =>
    value is Timestamp ? value.toDate() : DateTime.tryParse('$value');
String sessionHours(Map<String, dynamic> session) {
  final start = sessionTime(session['loginAt']);
  final end = sessionTime(session['logoutAt']);
  if (start == null || end == null) return 'Not closed';
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
  });
  final String branchId, branchName;
  @override
  State<BranchStaffActivityDialog> createState() =>
      _BranchStaffActivityDialogState();
}

class _BranchStaffActivityDialogState extends State<BranchStaffActivityDialog> {
  late final sessions = FirebaseFirestore.instance
      .collection('staff_login_sessions')
      .where('branchId', isEqualTo: widget.branchId)
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
              color: Color(0xFFFCE4EC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Activity Logs - ${widget.branchName}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC2105C),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close activity logs',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Login and logout sessions - newest first'),
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
                return StaffSessionTable(sessions: records);
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
      color: Color(0xFFE91E63),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFFFF0F6)),
          dataRowMinHeight: 64,
          dataRowMaxHeight: 80,
          columns: [
            'Login time',
            'Staff ID number',
            'Staff name',
            'Branch',
            'Type',
            'IP address',
            'Logout time',
            'Work hours',
          ].map((label) => DataColumn(label: Text(label))).toList(),
          rows: sessions
              .map(
                (session) => DataRow(
                  cells: [
                    DataCell(Text(date(session['loginAt']))),
                    DataCell(
                      SelectableText('${session['staffId'] ?? 'Not recorded'}'),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipOval(
                            child: avatar('${session['photoUrl'] ?? ''}'),
                          ),
                          const SizedBox(width: 10),
                          Text('${session['staffName'] ?? 'Not recorded'}'),
                        ],
                      ),
                    ),
                    DataCell(
                      Text('${session['branchName'] ?? 'Not assigned'}'),
                    ),
                    DataCell(Text('${session['type'] ?? 'User'}')),
                    DataCell(
                      Tooltip(
                        message: '${session['ipType'] ?? 'IP address'}',
                        child: SelectableText(
                          '${session['ipAddress'] ?? 'Not recorded'}',
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        session['logoutAt'] == null
                            ? 'Not recorded / session open'
                            : date(session['logoutAt']),
                      ),
                    ),
                    DataCell(Text(sessionHours(session))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
