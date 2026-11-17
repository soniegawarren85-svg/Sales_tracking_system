import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../services/bundle_stock_service.dart';
import '../services/branch_inventory_void_service.dart';
import '../services/branch_report_data.dart';
import 'historical_cash_drawer.dart';
import 'branch_allocation_table.dart';
import 'inventory_batches.dart';
import '../services/low_stock_reports.dart';
import 'low_stock_selection_dialog.dart';
import 'low_stock_reminder_dialog.dart';

bool inventoryNearExpiry(dynamic value, [DateTime? now]) {
  final expiry = cashRecordDate(value);
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  return expiry != null &&
      DateUtils.dateOnly(expiry).isAfter(today) &&
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
    this.addons = false,
    this.categoryName,
    this.onCategoriesChanged,
    this.showActions = true,
    this.allowLowStockReport = false,
    this.allowLowStockVoids = false,
    this.allowVoidAllocation = true,
  });
  final FirebaseFirestore? firestore;
  final bool addons;
  final String? categoryName;
  final ValueChanged<Set<String>>? onCategoriesChanged;
  final bool showActions;
  final bool allowLowStockReport;
  final bool allowLowStockVoids;
  final bool allowVoidAllocation;
  final String branchId, type, query;
  @override
  State<BranchInventoryMonitor> createState() => _BranchInventoryMonitorState();
}

class _BranchInventoryMonitorState extends State<BranchInventoryMonitor> {
  late final _stream = BranchReportData.watch(firestore: widget.firestore);
  String? _lastNotifiedCategories;
  bool _adminReminderScheduled = false;
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
      bool low(Map row) {
        final type = '${row['type'] ?? 'Categories'}';
        if (type == 'Beverages' || type == 'Add-ons') {
          return row['isLowStock'] == true ||
              (widget.allowLowStockReport &&
                  row['staffLowStockPendingAdmin'] == true);
        }
        return inventoryLowStock(row['remaining'], type: type);
      }
      final lowStockRows = all.where(low).toList();
      if (widget.allowLowStockReport &&
          lowStockRows.isNotEmpty &&
          !_adminReminderScheduled) {
        _adminReminderScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_showAdminLowStockReminder(data, lowStockRows));
        });
      }
      final reportedLowStockRows = all
          .where(
            (row) =>
                (low(row) && row['lowStockReportStatus'] == 'reported') ||
                (row['isLowStock'] == true &&
                    row['staffLowStockPendingAdmin'] != true &&
                    (row['type'] == 'Beverages' ||
                        row['type'] == 'Add-ons')),
          )
          .toList();
      final categories = {
        for (final row in all)
          if (row['type'] == 'Categories' &&
              '${row['categoryName'] ?? ''}'.trim().isNotEmpty)
            '${row['categoryName']}'.trim().toLowerCase(),
      };
      final categoryKey = (categories.toList()..sort()).join('|');
      if (categoryKey != _lastNotifiedCategories) {
        _lastNotifiedCategories = categoryKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCategoriesChanged?.call(categories);
        });
      }
      final rows = all
          .where(
            (row) =>
                (widget.showActions ||
                    row['type'] == 'Beverages' ||
                    row['type'] == 'Add-ons' ||
                    (num.tryParse('${row['remaining']}') ?? 0) > 0) &&
                (widget.addons
                    ? row['type'] == 'Add-ons'
                    : widget.type == 'All' || row['type'] == widget.type) &&
                (widget.type != 'Categories' ||
                    widget.categoryName == null ||
                    '${row['categoryName'] ?? ''}'.trim().toLowerCase() ==
                        widget.categoryName!.trim().toLowerCase()) &&
                '${row['id']} ${row['name']} ${row['expirationDate']} ${low(row) ? 'low stock' : ''} ${inventoryNearExpiry(row['expirationDate']) ? 'near expiry expiring soon malapit ma expire' : ''}'
                    .toLowerCase()
                    .contains(widget.query.trim().toLowerCase()),
          )
          .toList();
      return _buildInventory(
        context,
        data,
        rows,
        lowStockRows,
        reportedLowStockRows,
      );
    },
  );

  Widget _buildInventory(
    BuildContext context,
    BranchReportData data,
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> lowStockRows,
    List<Map<String, dynamic>> reportedLowStockRows,
  ) {
    bool low(Map row) {
      final type = '${row['type'] ?? 'Categories'}';
      if (type == 'Beverages' || type == 'Add-ons') {
        return row['isLowStock'] == true ||
            (widget.allowLowStockReport &&
                row['staffLowStockPendingAdmin'] == true);
      }
      return inventoryLowStock(row['remaining'], type: type);
    }
    final visibleRows = widget.allowLowStockReport
        ? rows
              .map(
                (row) => row['staffLowStockPendingAdmin'] == true
                    ? {...row, 'isLowStock': true}
                    : row,
              )
              .toList()
        : rows;
    final lowStockItems = [
      for (final row in lowStockRows)
        {
          ...row,
          'autoLowStock': true,
          'stock': row['remaining'],
          'categoryName': row['categoryName'] ?? row['type'],
          'allocationItemId': row['allocationItemId'] ?? row['id'],
        },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.allowLowStockReport &&
            widget.allowLowStockVoids &&
            reportedLowStockRows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD591)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mark_chat_unread_outlined,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${reportedLowStockRows.length} low-stock item(s) reported from this branch',
                      style: const TextStyle(
                        color: Color(0xFF8A4B08),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showLowStockReminderDialog(
                      context: context,
                      title: 'Branch low-stock request',
                      description:
                          'These are the low-stock items reported for this branch.',
                      items: reportedLowStockRows,
                      readOnly: true,
                      onRequest: (_) async {},
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                ],
              ),
            ),
          ),
        if (widget.allowLowStockReport && lowStockRows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD591)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${lowStockRows.length} low-stock item(s) in this branch',
                      style: const TextStyle(
                        color: Color(0xFF8A4B08),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showLowStockReminderDialog(
                      context: context,
                      title: 'Low stock in this branch',
                      description:
                          'Review the affected inventory and request replenishment from Super Admin.',
                      items: lowStockItems,
                      onRequest: (selected) =>
                          _sendLowStockRequest(context, data, selected),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                ],
              ),
            ),
          ),
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
          rows: visibleRows,
          beverages: widget.type == 'Beverages',
          inventory: true,
          addons: widget.addons,
          showActions: widget.showActions,
          actions: (row) {
            if (widget.type == 'Beverages' &&
                !widget.addons &&
                !['S', 'Small'].contains('${row['_sizeLabel']}')) {
              return const SizedBox.shrink();
            }
            return Row(
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
                      readOnly: true,
                      database: widget.firestore,
                      reportData: data,
                    ),
                  ),
                if (widget.allowVoidAllocation)
                  IconButton(
                    tooltip: 'Void allocation',
                    icon: const Icon(
                      Icons.block_outlined,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _voidAllocation(context, row),
                  ),
              ],
            );
          },
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching branch inventory.'),
          ),
      ],
    );
  }

  Future<void> _showAdminLowStockReminder(
    BranchReportData data,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'low_stock_reminder_admin_${widget.branchId}';
      final lastShown = prefs.getInt(key) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - lastShown <
          const Duration(hours: 1).inMilliseconds) {
        return;
      }
      if (!mounted) return;
      final branch = data
          .rows('branches')
          .where((row) => '${row['_id']}' == widget.branchId)
          .firstOrNull;
      final branchName =
          '${branch?['name'] ?? branch?['branchName'] ?? widget.branchId}';
      final saved = await showLowStockReminderDialog(
        context: context,
        title: 'Low stock in $branchName',
        description:
            'Choose the low-stock items to request from Super Admin. You can view the request later from this branch inventory.',
        items: [
          for (final row in rows)
            {
              ...row,
              'autoLowStock': true,
              'stock': row['remaining'],
              'categoryName': row['categoryName'] ?? row['type'],
              'allocationItemId': row['allocationItemId'] ?? row['id'],
            },
        ],
        onRequest: (selected) => _sendLowStockRequest(context, data, selected),
      );
      if (saved != null) {
        await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to prepare low-stock request: $error')),
      );
    }
  }

  Future<void> _sendLowStockRequest(
    BuildContext context,
    BranchReportData data,
    List<Map<String, dynamic>> selected,
  ) async {
    final admin = await currentBranchAdmin(
      firestore: widget.firestore ?? FirebaseFirestore.instance,
    );
    final branch = data
        .rows('branches')
        .where((row) => '${row['_id']}' == widget.branchId)
        .firstOrNull;
    await submitLowStockReportToSuperAdmin(
      firestore: widget.firestore ?? FirebaseFirestore.instance,
      adminId: admin.id,
      adminName: admin.name,
      branchId: widget.branchId,
      branchName:
          '${branch?['name'] ?? branch?['branchName'] ?? widget.branchId}',
      items: selected,
    );
  }

  Future<void> _voidAllocation(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final type = '${item['type'] ?? ''}';
    final isPhysicalInventory = type == 'Categories' || type == 'Bundle';
    final remaining = num.tryParse('${item['remaining']}')?.toInt();
    final canVoidMarkedLowStock =
        widget.allowLowStockVoids &&
        item['isLowStock'] == true &&
        (type == 'Beverages' || type == 'Add-ons');
    if ((!isPhysicalInventory && !canVoidMarkedLowStock) ||
        (isPhysicalInventory && (remaining == null || remaining > 0))) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.88, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: AlertDialog(
            icon: const Icon(
              Icons.inventory_2_outlined,
              color: Colors.deepOrange,
              size: 34,
            ),
            title: const Text('Not sold out yet'),
            content: Text(
              !isPhysicalInventory && !canVoidMarkedLowStock
                  ? 'Only physical branch inventory or Super Admin-approved low-stock beverages/add-ons can be voided here.'
                  : 'This item still has $remaining unit${remaining == 1 ? '' : 's'} in stock. Sell out the remaining stock before voiding it.',
              textAlign: TextAlign.center,
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: const Text('I understand'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void allocation?'),
        content: Text(
          'Remove "${item['name'] ?? 'this item'}" from the branch?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db = widget.firestore ?? FirebaseFirestore.instance;
    final allocationId = '${item['allocationId'] ?? ''}';
    final itemId = '${item['allocationItemId'] ?? ''}';
    if (allocationId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to identify this allocation.')),
        );
      }
      return;
    }

    var loadingShown = false;
    try {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 16),
                  Expanded(child: Text('Voiding allocation...')),
                ],
              ),
            ),
          ),
        ),
      );
      loadingShown = true;
      final removed = await voidBranchInventoryAllocation(
        firestore: db,
        allocationId: allocationId,
        allocationItemId: itemId,
        branchId: widget.branchId,
        item: item,
        allowLowStock: canVoidMarkedLowStock,
      );
      if (context.mounted) {
        if (loadingShown) Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed
                  ? 'Sold-out item removed from branch inventory.'
                  : 'This item was already removed from branch inventory.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        if (loadingShown) Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to void allocation: $error')),
        );
      }
    }
  }
}
