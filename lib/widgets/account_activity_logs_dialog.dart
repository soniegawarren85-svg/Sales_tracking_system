import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/account_presence.dart';
import '../theme/app_colors.dart';

class AccountActivityLogsDialog extends StatefulWidget {
  const AccountActivityLogsDialog({
    super.key,
    required this.actorId,
    this.firestore,
  });

  final String actorId;
  final FirebaseFirestore? firestore;

  @override
  State<AccountActivityLogsDialog> createState() =>
      _AccountActivityLogsDialogState();
}

class _AccountActivityLogsDialogState extends State<AccountActivityLogsDialog> {
  late DateTimeRange? _range = DateTimeRange(
    start: DateUtils.dateOnly(DateTime.now()),
    end: DateUtils.dateOnly(DateTime.now()),
  );
  String _search = '';

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  DateTime? _dateOf(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  String _dateLabel(BuildContext context, dynamic value) {
    final date = _dateOf(value);
    if (date == null) return 'Not recorded';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(date)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  String _duration(Map<String, dynamic> session) {
    final start = _dateOf(session['loginAt']);
    final end = _dateOf(session['logoutAt']) ?? DateTime.now();
    if (start == null) return 'Not recorded';
    if (end.isBefore(start)) return 'Invalid times';
    final minutes = end.difference(start).inMinutes;
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  Future<void> _pickDateRange() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final selection = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: now, end: now),
    );
    if (selection != null && mounted) {
      setState(() => _range = selection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _db
        .collection('staff_login_sessions')
        .where('actorId', isEqualTo: widget.actorId)
        .snapshots();

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 1050,
        height: MediaQuery.sizeOf(context).height * .82,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search ID, name, status, or IP address',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Filter by date range',
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.calendar_month_rounded),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _search = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _range == null
                              ? 'Showing all dates'
                              : 'Showing ${MaterialLocalizations.of(context).formatShortDate(_range!.start)} – ${MaterialLocalizations.of(context).formatShortDate(_range!.end)}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      if (_range != null)
                        TextButton.icon(
                          onPressed: () => setState(() => _range = null),
                          icon: const Icon(Icons.clear, size: 18),
                          label: const Text('Clear dates'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: sessions,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Unable to load account session logs.'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows =
                      snapshot.data!.docs.map((doc) => doc.data()).where((
                        session,
                      ) {
                        final date = _dateOf(session['loginAt']);
                        final inRange =
                            _range == null ||
                            (date != null &&
                                !date.isBefore(_range!.start) &&
                                date.isBefore(
                                  _range!.end.add(const Duration(days: 1)),
                                ));
                        final text = [
                          session['staffId'],
                          session['staffName'],
                          session['role'],
                          session['type'],
                          session['ipAddress'],
                          session['logoutAt'] == null
                              ? 'online active'
                              : 'offline',
                        ].join(' ').toLowerCase();
                        return inRange && text.contains(_search.toLowerCase());
                      }).toList()..sort(
                        (a, b) => (_dateOf(b['loginAt']) ?? DateTime(1970))
                            .compareTo(_dateOf(a['loginAt']) ?? DateTime(1970)),
                      );

                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        _range == null
                            ? 'No account sessions found.'
                            : 'No activity logs found for this date.',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _db
                        .collection('super_admin_profiles')
                        .doc(widget.actorId)
                        .snapshots(),
                    builder: (context, superAdminSnapshot) {
                      final superAdminProfile = superAdminSnapshot.data;
                      if (superAdminProfile?.exists == true) {
                        return _sessionList(
                          context,
                          rows,
                          superAdminProfile!.data() ?? const {},
                        );
                      }
                      return StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>
                      >(
                        stream: _db
                            .collection('staff_requests')
                            .doc(widget.actorId)
                            .snapshots(),
                        builder: (context, profileSnapshot) => _sessionList(
                          context,
                          rows,
                          profileSnapshot.data?.data() ?? const {},
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionList(
    BuildContext context,
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> profile,
  ) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
    itemCount: rows.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      final session = rows[index];
      final active =
          session['logoutAt'] == null &&
          AccountPresenceService.isOnline(profile);
      final fields = <(String, String)>[
        ('ID', '${session['staffId'] ?? 'Not recorded'}'),
        ('Name', '${session['staffName'] ?? 'Not recorded'}'),
        ('Login time', _dateLabel(context, session['loginAt'])),
        ('Logout time', _dateLabel(context, session['logoutAt'])),
        ('Status', active ? 'Online' : 'Offline'),
        ('Hours', _duration(session)),
        ('IP address', '${session['ipAddress'] ?? 'Not recorded'}'),
      ];
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.blush),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    active ? Icons.circle : Icons.circle_outlined,
                    color: active ? Colors.green : AppColors.textMuted,
                    size: 14,
                  ),
                  label: Text(active ? 'Online' : 'Offline'),
                  visualDensity: VisualDensity.compact,
                ),
                if ('${session['role'] ?? session['type'] ?? ''}'.isNotEmpty)
                  Chip(
                    label: Text(
                      '${session['role'] ?? session['type']}'.replaceAll(
                        '_',
                        ' ',
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 560 ? 1 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: fields
                      .map(
                        (field) => SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                field.$1,
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              SelectableText(field.$2),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
