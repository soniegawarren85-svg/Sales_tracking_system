import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/branch_report_data.dart';
import 'historical_cash_drawer.dart';
import 'branch_allocation_table.dart';

bool inventoryNearExpiry(dynamic value, [DateTime? now]) {
  final expiry = cashRecordDate(value);
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  return expiry != null &&
      !DateUtils.dateOnly(expiry).isBefore(today) &&
      !DateUtils.dateOnly(expiry).isAfter(today.add(const Duration(days: 5)));
}

bool inventoryAlertSearch(String query) {
  final value = query.trim().toLowerCase();
  return [
        'low stock',
        'near expiry',
        'expiring soon',
        'malapit ma expire',
      ].contains(value) ||
      DateTime.tryParse(value) != null;
}

class BranchInventoryMonitor extends StatefulWidget {
  const BranchInventoryMonitor({
    super.key,
    required this.branchId,
    this.type = 'All',
    this.query = '',
    this.firestore,
  });
  final FirebaseFirestore? firestore;
  final String branchId, type, query;
  @override
  State<BranchInventoryMonitor> createState() => _BranchInventoryMonitorState();
}

class _BranchInventoryMonitorState extends State<BranchInventoryMonitor> {
  late final _stream = BranchReportData.watch(firestore: widget.firestore);
  @override
  Widget build(BuildContext context) => StreamBuilder<BranchReportData>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Unable to load branch inventory.');
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      final all = data.currentInventory(widget.branchId, DateTime.now());
      bool low(Map row) =>
          row['remaining'] != null &&
          reportValue(row['remaining']) <= 50 &&
          row['type'] != 'Beverages';
      final rows = all
          .where(
            (row) =>
                (widget.type == 'All' || row['type'] == widget.type) &&
                '${row['id']} ${row['name']} ${row['expirationDate']} ${low(row) ? 'low stock' : ''} ${inventoryNearExpiry(row['expirationDate']) ? 'near expiry expiring soon malapit ma expire' : ''}'
                    .toLowerCase()
                    .contains(widget.query.trim().toLowerCase()),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inventoryAlertSearch(widget.query))
            Wrap(
              spacing: 12,
              children: [
                Chip(
                  avatar: const Icon(Icons.warning_amber, color: Colors.orange),
                  label: Text('Low stock: ${rows.where(low).length}'),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.event_busy,
                    color: Colors.deepOrange,
                  ),
                  label: Text(
                    'Near expiry: ${rows.where((r) => inventoryNearExpiry(r['expirationDate'])).length}',
                  ),
                ),
              ],
            ),
          BranchAllocationTable(
            rows: rows,
            beverages: widget.type == 'Beverages',
            inventory: true,
            actions: (row) => IconButton(
              tooltip: 'View history',
              icon: const Icon(Icons.history),
              onPressed: () =>
                  showBranchItemHistory(context, data, widget.branchId, row),
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matching branch inventory.'),
            ),
        ],
      );
    },
  );
}
