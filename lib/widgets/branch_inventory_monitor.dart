import 'branch_inventory_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/bundle_stock_service.dart';
import '../services/branch_inventory_editor.dart';
import '../services/branch_permissions.dart';
import '../services/branch_report_data.dart';
import 'historical_cash_drawer.dart';
import 'branch_allocation_table.dart';
import 'inventory_batches.dart';

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
    this.showBatchHistory = true,
    this.addons = false,
  });
  final FirebaseFirestore? firestore;
  final bool showBatchHistory;
  final bool addons;
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
          inventoryLowStock(
            row['remaining'],
            type: '${row['type'] ?? 'Categories'}',
          ) &&
          row['type'] != 'Beverages';
      final rows = all
          .where(
            (row) =>
                (widget.addons
                    ? row['type'] == 'Add-ons'
                    : widget.type == 'All' || row['type'] == widget.type) &&
                '${row['id']} ${row['name']} ${row['expirationDate']} ${low(row) ? 'low stock' : ''} ${inventoryNearExpiry(row['expirationDate']) ? 'near expiry expiring soon malapit ma expire' : ''}'
                    .toLowerCase()
                    .contains(widget.query.trim().toLowerCase()),
          )
          .toList();
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: (widget.firestore ?? FirebaseFirestore.instance)
            .collection('admin_settings')
            .doc('transactions')
            .snapshots(),
        builder: (context, _) => FutureBuilder<bool>(
          future: BranchPermissions.allowed(
            'adminAllowInventoryEdits',
            database: widget.firestore,
            branchId: widget.branchId,
          ),
          builder: (context, permission) => _buildInventory(
            context,
            data,
            rows,
            canEdit: permission.data == true,
          ),
        ),
      );
    },
  );

  Widget _buildInventory(
    BuildContext context,
    BranchReportData data,
    List<Map<String, dynamic>> rows, {
    required bool canEdit,
  }) {
    bool low(Map row) =>
        inventoryLowStock(
          row['remaining'],
          type: '${row['type'] ?? 'Categories'}',
        ) &&
        row['type'] != 'Beverages';
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
                avatar: const Icon(Icons.event_busy, color: Colors.deepOrange),
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
          addons: widget.addons,
          actions: (row) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ('${row['allocationId'] ?? ''}'.isNotEmpty)
                IconButton(
                  tooltip: 'View batches',
                  icon: const Icon(Icons.layers_outlined),
                  onPressed: () => showInventoryBatches(
                    context,
                    allocationId: '${row['allocationId']}',
                    scopeIds: [widget.branchId],
                    itemId: row['allocationItemId']?.toString(),
                    readOnly: widget.showBatchHistory,
                    database: widget.firestore,
                  ),
                ),
              IconButton(
                tooltip: 'View history',
                icon: const Icon(Icons.history),
                onPressed: () =>
                    showBranchItemHistory(context, data, widget.branchId, row),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'Edit branch inventory',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editInventoryItem(context, row),
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching branch inventory.'),
          ),
      ],
    );
  }

  Future<void> _editInventoryItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final branchId = widget.branchId;
    final db = widget.firestore ?? FirebaseFirestore.instance;
    final result = await showDialog<BranchInventoryEdit>(
      context: context,
      builder: (_) => BranchInventoryEditDialog(
        item: item,
        onSave: (value) async {
          await BranchPermissions.require(
            'adminAllowInventoryEdits',
            database: db,
            branchId: branchId,
          );
          await updateBranchInventoryItem(
            firestore: db,
            branchId: branchId,
            item: item,
            name: value.name,
            price: value.price,
            stock: value.stock,
            sizePrices: value.sizePrices.isEmpty ? null : value.sizePrices,
            expirationDate: value.expirationDate,
            updateExpirationDate: item['type'] == 'Add-ons',
          );
        },
      ),
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch inventory updated.')),
      );
    }
  }
}
