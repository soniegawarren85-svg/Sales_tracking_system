import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/public_item_id.dart';
import '../theme/app_colors.dart';
import 'inventory_records_table.dart';

class AccountActivityLogsDialog extends StatelessWidget {
  const AccountActivityLogsDialog({
    super.key,
    required this.actorId,
    this.firestore,
  });

  final String actorId;
  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SizedBox(
      width: 1050,
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: Colors.white),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Activity Logs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
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
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: (firestore ?? FirebaseFirestore.instance)
                  .collection('activity_logs')
                  .where('actorId', isEqualTo: actorId)
                  .limit(200)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load activity logs.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final logs =
                    snapshot.data!.docs.map((doc) => doc.data()).toList()..sort(
                      (a, b) => _dateOf(
                        b['createdAt'],
                      ).compareTo(_dateOf(a['createdAt'])),
                    );
                if (logs.isEmpty) {
                  return const Center(
                    child: Text('No activity has been recorded yet.'),
                  );
                }
                String dateLabel(dynamic value) {
                  final date = _dateOf(value);
                  if (date.millisecondsSinceEpoch == 0) return 'Pending';
                  final local = date.toLocal();
                  return '${MaterialLocalizations.of(context).formatMediumDate(local)} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: InventoryRecordsTable(
                    headings: const [
                      'Date & Time',
                      'Activity',
                      'Description',
                      'Role',
                      'Branch',
                    ],
                    flex: const {0: 1.5, 1: 1, 2: 2.5, 3: 1, 4: 1.5},
                    rows: logs
                        .map(
                          (log) => <Widget>[
                            Text(dateLabel(log['createdAt'])),
                            Text(_label('${log['action'] ?? 'activity'}')),
                            Text(
                              '${log['description'] ?? 'Activity recorded'}',
                            ),
                            Text(_label('${log['actorRole'] ?? ''}')),
                            Text(
                              ((log['branchIds'] as List?) ?? const [])
                                  .map((id) => publicItemId('$id'))
                                  .join(', '),
                            ),
                          ],
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  static DateTime _dateOf(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime(1970);
    return DateTime(1970);
  }

  static String _label(String value) => value
      .replaceAll('_', ' ')
      .replaceFirstMapped(
        RegExp(r'^[a-z]'),
        (match) => match[0]!.toUpperCase(),
      );
}
