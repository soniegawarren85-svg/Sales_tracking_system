import 'package:flutter/material.dart';

DateTimeRange lossRecordPeriod(DateTime anchor, String range) {
  final day = DateTime(anchor.year, anchor.month, anchor.day);
  if (range == 'Month') {
    return DateTimeRange(
      start: DateTime(day.year),
      end: DateTime(day.year + 1),
    );
  }
  if (range == 'Week') {
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return DateTimeRange(
      start: monday,
      end: monday.add(const Duration(days: 7)),
    );
  }
  return DateTimeRange(start: day, end: day.add(const Duration(days: 1)));
}

String lossItemCategory(Map item) {
  if (item['isBundle'] == true) return 'Bundle';
  if (item['isCoffee'] == true ||
      (item['category']?.toString().toLowerCase() ?? '').contains('coffee') ||
      (item['coffeeSize']?.toString().isNotEmpty ?? false)) {
    return 'Coffee';
  }
  return 'Categories';
}

List<Map<String, dynamic>> filterLossRecords(
  List<Map<String, dynamic>> records, {
  required DateTimeRange period,
  DateTime? date,
  String query = '',
  String category = 'All',
}) {
  final results = <Map<String, dynamic>>[];
  final search = query.trim().toLowerCase();
  for (final record in records) {
    final time = record['timestamp'];
    if (time is! DateTime ||
        time.isBefore(period.start) ||
        !time.isBefore(period.end))
      continue;
    if (date != null && !DateUtils.isSameDay(time, date)) continue;
    final items = (record['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .where(
          (item) => category == 'All' || lossItemCategory(item) == category,
        )
        .toList();
    if (category != 'All' && items.isEmpty) continue;
    final searchable = [
      record['staffName'],
      record['staffPublicId'],
      record['staffId'],
      record['userId'],
      record['salesId'],
      record['reason'],
      record['comment'],
      items,
    ].join(' ').toLowerCase();
    if (search.isNotEmpty && !searchable.contains(search)) continue;
    results.add({
      ...record,
      'items': items,
      '_filteredItems': category != 'All',
    });
  }
  results.sort(
    (a, b) =>
        (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime),
  );
  return results;
}

class BranchLossRecordsDialog extends StatefulWidget {
  const BranchLossRecordsDialog({
    super.key,
    required this.status,
    required this.anchor,
    required this.range,
    required this.records,
    required this.staffRecords,
    required this.cardBuilder,
  });

  final String status;
  final DateTime anchor;
  final String range;
  final List<Map<String, dynamic>> records;
  final Future<List<Map<String, dynamic>>> staffRecords;
  final Widget Function(Map<String, dynamic>) cardBuilder;

  @override
  State<BranchLossRecordsDialog> createState() =>
      _BranchLossRecordsDialogState();
}

class _BranchLossRecordsDialogState extends State<BranchLossRecordsDialog> {
  String _query = '';
  String _category = 'All';
  DateTime? _date;
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  String _dayLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final period = lossRecordPeriod(widget.anchor, widget.range);
    final periodLabel = _date != null
        ? _dayLabel(_date!)
        : widget.range == 'Month'
        ? 'January–December ${widget.anchor.year}'
        : widget.range == 'Week'
        ? '${_dayLabel(period.start)} – ${_dayLabel(period.end.subtract(const Duration(days: 1)))}'
        : _dayLabel(widget.anchor);
    return Dialog(
      child: SizedBox(
        width: 800,
        height: 740,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.status} items',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFC2105C),
                          ),
                        ),
                        Text(periodLabel),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search staff, ID, item, or reason',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Filter by date',
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date ?? widget.anchor,
                            firstDate: period.start,
                            lastDate: period.end.subtract(
                              const Duration(days: 1),
                            ),
                          );
                          if (picked != null && mounted)
                            setState(() => _date = picked);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ...['All', 'Categories', 'Bundle', 'Coffee'].map(
                          (category) => ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: (_) =>
                                setState(() => _category = category),
                          ),
                        ),
                        if (_date != null)
                          InputChip(
                            label: Text(_dayLabel(_date!)),
                            onDeleted: () => setState(() => _date = null),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: widget.staffRecords,
                initialData: widget.records,
                builder: (context, snapshot) {
                  final records = filterLossRecords(
                    snapshot.data ?? widget.records,
                    period: period,
                    date: _date,
                    query: _query,
                    category: _category,
                  );
                  if (records.isEmpty)
                    return const Center(
                      child: Text('No records match these filters.'),
                    );
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final time = record['timestamp'] as DateTime;
                      final previous = index == 0
                          ? null
                          : records[index - 1]['timestamp'] as DateTime;
                      final newMonth =
                          previous == null ||
                          previous.month != time.month ||
                          previous.year != time.year;
                      final newDay =
                          previous == null ||
                          !DateUtils.isSameDay(previous, time);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.range == 'Month' && newMonth)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                '${_months[time.month - 1]} ${time.year}',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (newDay)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _dayLabel(time),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          widget.cardBuilder(record),
                          const SizedBox(height: 12),
                        ],
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
}
