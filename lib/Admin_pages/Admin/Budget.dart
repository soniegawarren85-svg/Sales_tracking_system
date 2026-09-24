import '../../widgets/branch_loss_records_dialog.dart';
import '../../widgets/branch_analytics_bars.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../services/cash_drawer_service.dart';

// ── Color Palette ─────────────────────────────────────────────────
const kPrimary = Color(0xFFE91E63);
const kDeep = Color(0xFFC2105C);
const kLight = Color(0xFFF48FB1);
const kAccent = Color(0xFFF8BBD0);
const kCream = Color(0xFFFFF8F3);
const kBannerTop = Color(0xFF8B0038);
const kBannerMid = Color(0xFFC2105C);
const kBannerBot = Color(0xFFE91E63);
// ──────────────────────────────────────────────────────────────────

class _RefundBadge extends StatelessWidget {
  const _RefundBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'REFUNDED',
        style: TextStyle(
          color: Color(0xFFC62828),
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _AllocationTableRow {
  const _AllocationTableRow({
    required this.documentId,
    required this.itemId,
    required this.id,
    required this.name,
    required this.allocated,
    required this.remaining,
    required this.price,
    required this.type,
  });

  final String documentId;
  final String? itemId;
  final String id;
  final String name;
  final int allocated;
  final int remaining;
  final double price;
  final String type;
}

class _AssignInventoryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final TextEditingController controller;
  final bool enabled;

  const _AssignInventoryTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.controller,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFFFF8F3) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAccent.withOpacity(0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: enabled ? kDeep : Colors.grey, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? kBannerTop : Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: enabled ? Colors.grey.shade600 : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 116,
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                color: kBannerTop,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: 'Qty',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  color: enabled ? kDeep : Colors.grey,
                  onPressed: !enabled
                      ? null
                      : () {
                          final value = int.tryParse(controller.text) ?? 0;
                          controller.text = value <= 1
                              ? ''
                              : (value - 1).toString();
                        },
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 36,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  color: enabled ? kDeep : Colors.grey,
                  onPressed: !enabled
                      ? null
                      : () {
                          final value = int.tryParse(controller.text) ?? 0;
                          controller.text = (value + 1).toString();
                        },
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 36,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kAccent.withOpacity(0.8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPrimary, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignCoffeeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  const _AssignCoffeeTile({
    required this.title,
    required this.subtitle,
    this.icon = Icons.coffee_rounded,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? kPrimary.withOpacity(0.08) : const Color(0xFFFFF8F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? kPrimary : kAccent.withOpacity(0.7),
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: onChanged,
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: kPrimary,
        secondary: Icon(icon, color: kDeep),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: kBannerTop,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AssignModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AssignModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kPrimary : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kPrimary : kAccent.withOpacity(0.8),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : kDeep),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : kBannerTop,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedBudgetHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  const _PinnedBudgetHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedBudgetHeaderDelegate oldDelegate) {
    return minHeight != oldDelegate.minHeight ||
        maxHeight != oldDelegate.maxHeight ||
        child != oldDelegate.child;
  }
}

class _BudgetPageState extends State<BudgetPage>
    with SingleTickerProviderStateMixin {
  final _budgetControllers = <String, TextEditingController>{};
  final _branchSearchController = TextEditingController();
  final _allocationSearchController = TextEditingController();
  final _currentAllocations = <String, double>{};
  final _branchInventoryStreams =
      <String, Stream<QuerySnapshot<Map<String, dynamic>>>>{};
  final _firestore = FirebaseFirestore.instance;
  // Transaction details are shown in their own dialog to keep report cards compact.
  final bool _showInlineTransactionDetails = false;
  String _branchSearchQuery = '';
  String? _selectedBranchId;
  String _allocationFilter = 'All';
  String _allocationSearchQuery = '';
  bool _branchFabExpanded = false;
  String _activeBranchName = 'Branch';
  List<String> _activeBranchStaffIds = const [];
  List<String> _activeBranchStaffNames = const [];
  String _analyticsRange = 'Day';
  String _sellingRank = 'All';
  String _sellingType = 'All';
  String _analyticsStatus = 'All';
  DateTime? _analyticsDate;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _branchesStream;

  @override
  void initState() {
    super.initState();
    _branchesStream = _firestore
        .collection('branches')
        .orderBy('name')
        .snapshots();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    for (var c in _budgetControllers.values) {
      c.dispose();
    }
    _branchSearchController.dispose();
    _allocationSearchController.dispose();
    _budgetControllers.clear();
    _currentAllocations.clear();
    _branchInventoryStreams.clear();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveBudget(
    String targetId,
    String targetName,
    double budget, {
    bool isBranch = false,
    bool replaceDailyOpening = false,
  }) async {
    if (targetId.trim().isEmpty) {
      _showSnack('Missing target ID', Colors.red.shade600);
      return;
    }
    try {
      final now = DateTime.now();
      final dateKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final budgetRef = _firestore.collection('staff_budget').doc(targetId);
      final existingBudgetSnapshot = await budgetRef.get();
      final lastBudgetDate =
          existingBudgetSnapshot.data()?['budgetDate']?.toString() ?? '';
      final previousAllocation = existingBudgetSnapshot.exists
          ? (existingBudgetSnapshot.data()?['allocatedBudget'] as num?)
                    ?.toDouble() ??
                0.0
          : 0.0;
      final sameBudgetDay = lastBudgetDate == dateKey;
      final newAllocation = replaceDailyOpening
          ? budget
          : (sameBudgetDay ? previousAllocation + budget : budget);

      // Update current allocation total
      await budgetRef.set({
        'staffId': targetId,
        'staffName': targetName,
        if (isBranch) 'branchId': targetId,
        if (isBranch) 'branchName': targetName,
        'targetType': isBranch ? 'branch' : 'staff',
        'allocatedBudget': newAllocation,
        'budgetDate': dateKey,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // Add to today's drawer or replace today's opening balance.
      final cashDrawerRef = _firestore
          .collection('staff_cash_drawer')
          .doc(targetId);
      await _firestore.runTransaction((transaction) async {
        final cashDrawerSnapshot = await transaction.get(cashDrawerRef);
        final currentBalance = cashDrawerSnapshot.exists
            ? (cashDrawerSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        final drawerDate =
            cashDrawerSnapshot.data()?['drawerDate']?.toString() ?? '';
        final sameDrawerDay = drawerDate == dateKey;
        final nextBalance = replaceDailyOpening
            ? budget
            : (sameDrawerDay ? currentBalance + budget : budget);
        transaction.set(cashDrawerRef, {
          'balance': nextBalance,
          'openingCash': replaceDailyOpening ? budget : nextBalance,
          'dailyOpeningCash': replaceDailyOpening ? budget : nextBalance,
          'drawerDate': dateKey,
          'updatedAt': now,
          'staffId': targetId,
          if (isBranch) 'branchId': targetId,
          if (isBranch) 'branchName': targetName,
          'targetType': isBranch ? 'branch' : 'staff',
        }, SetOptions(merge: true));
      });

      // Add to budget history for audit trail
      await _firestore.collection('budget_history').add({
        'staffId': targetId,
        'staffName': targetName,
        if (isBranch) 'branchId': targetId,
        if (isBranch) 'branchName': targetName,
        'targetType': isBranch ? 'branch' : 'staff',
        'amount': budget,
        'createdAt': Timestamp.fromDate(now),
        'type': replaceDailyOpening ? 'set_daily_cash_drawer' : 'allocation',
      });

      if (!mounted) return;
      setState(() {
        _currentAllocations[targetId] = newAllocation;
        _budgetControllers[targetId]?.clear();
      });
      _showSnack(
        replaceDailyOpening
            ? 'Daily cash drawer set for $targetName'
            : 'Budget updated for $targetName',
        Colors.green.shade600,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error saving budget: $e', Colors.red.shade600);
    }
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _parsePrice(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
          value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '',
        ) ??
        0.0;
  }

  bool _isExpiredInventoryItem(String expirationDate) {
    if (expirationDate.trim().isEmpty) return false;
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.isBefore(
        DateTime(today.year, today.month, today.day + 1),
      );
    } catch (_) {
      return false;
    }
  }

  bool _isNearExpiryInventoryItem(String expirationDate) {
    if (expirationDate.trim().isEmpty || expirationDate == '--') return false;
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);
      final expiryDay = DateTime(
        expiryDate.year,
        expiryDate.month,
        expiryDate.day,
      );
      final daysLeft = expiryDay.difference(startOfToday).inDays;
      return daysLeft >= 0 && daysLeft <= 7;
    } catch (_) {
      return false;
    }
  }

  String _branchCode(String sourceId) {
    var value = 0;
    for (final codeUnit in sourceId.codeUnits) {
      value = (value * 31 + codeUnit) % 10000000000;
    }
    final digits = value.toString().padLeft(10, '0');
    return 'BR-${digits.substring(0, 5)}-${digits.substring(5, 9)}-${digits.substring(9)}';
  }

  bool _isActiveAllocationDocument(Map<String, dynamic> data) {
    if (data['isDeleted'] == true ||
        _isExpiredInventoryItem(data['expirationDate']?.toString() ?? '')) {
      return false;
    }
    if (data['isBundle'] == true) {
      return !_hasExpiredAssignedBundleItem(data) &&
          _availableAssignedBundleCount(data) > 0;
    }
    if (data['isCoffee'] == true || data['isAddon'] == true) return true;
    return (data['items'] as List<dynamic>? ?? []).whereType<Map>().any((raw) {
      final item = Map<String, dynamic>.from(raw);
      return _parseInt(item['stock']) > 0 &&
          !_isExpiredInventoryItem(item['expirationDate']?.toString() ?? '');
    });
  }

  int _stockForAssignableItem(Map<String, dynamic> item) {
    return item.containsKey('stock')
        ? _parseInt(item['stock'])
        : _parseInt(item['startingStock']);
  }

  int _displayAssignableStock(
    Map<String, dynamic> item,
    String sourceDocId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> assignedDocs,
  ) {
    final currentStock = _stockForAssignableItem(item);
    final startingStock = _parseInt(item['startingStock']);
    if (currentStock > 0 || startingStock <= 0) return currentStock;

    final itemId = item['id']?.toString() ?? '';
    final itemName = item['name']?.toString() ?? '';
    var assignedStock = 0;
    for (final assignedDoc in assignedDocs) {
      final assignedData = assignedDoc.data();
      if (assignedData['sourceInventoryId']?.toString() != sourceDocId) {
        continue;
      }
      final assignedItems =
          (assignedData['items'] as List<dynamic>? ?? []).whereType<Map>();
      for (final rawAssignedItem in assignedItems) {
        final assignedItem = Map<String, dynamic>.from(rawAssignedItem);
        final sameId =
            itemId.isNotEmpty && assignedItem['id']?.toString() == itemId;
        final sameName = itemName.isNotEmpty &&
            assignedItem['name']?.toString() == itemName;
        if (sameId || sameName) {
          assignedStock += _parseInt(
            assignedItem['stock'] ?? assignedItem['startingStock'],
          );
        }
      }
    }
    return (startingStock - assignedStock).clamp(0, startingStock).toInt();
  }

  bool _isRemovedVariant(
    Map<String, dynamic> item,
    List<dynamic> removedItems,
  ) {
    final itemName = item['name']?.toString() ?? '';
    final itemPrice = item['price']?.toString() ?? '';
    return removedItems.any((raw) {
      if (raw is! Map) return false;
      final removed = Map<String, dynamic>.from(raw);
      return (removed['name']?.toString() ?? '') == itemName &&
          (removed['price']?.toString() ?? '') == itemPrice;
    });
  }

  List<MapEntry<int, Map<String, dynamic>>> _assignableCategoryItems(
    Map<String, dynamic> data,
  ) {
    final items = data['items'] as List<dynamic>? ?? [];
    final removedItems = data['removedItems'] as List<dynamic>? ?? [];

    return items
        .asMap()
        .entries
        .where((entry) {
          final item = entry.value;
          if (item is! Map) return false;
          final normalizedItem = Map<String, dynamic>.from(item);
          final expirationDate = item['expirationDate']?.toString() ?? '';
          return !_isExpiredInventoryItem(expirationDate) &&
              !_isRemovedVariant(normalizedItem, removedItems);
        })
        .map((entry) {
          return MapEntry(entry.key, Map<String, dynamic>.from(entry.value));
        })
        .toList();
  }

  String _staffInventoryDocId(String staffId, String sourceDocId) {
    return '${staffId}_$sourceDocId'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  Map<String, int> _staffInventoryTotals(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var starting = 0;
    var remaining = 0;
    var reduced = 0;

    for (final doc in docs) {
      final data = doc.data();
      if (data['isDeleted'] == true) continue;

      if (data['isBundle'] == true) {
        final bundleCount = _parseInt(data['bundleCount']);
        starting += _parseInt(
          data['assignedStartingStock'],
          fallback: bundleCount,
        );
        remaining += bundleCount;
        continue;
      }

      final items = (data['items'] as List<dynamic>? ?? []).whereType<Map>();
      for (final rawItem in items) {
        final item = Map<String, dynamic>.from(rawItem);
        final stock = item.containsKey('stock')
            ? _parseInt(item['stock'])
            : _parseInt(item['startingStock']);
        starting += _parseInt(
          item['assignedStartingStock'],
          fallback: _parseInt(item['startingStock'], fallback: stock),
        );
        remaining += stock;
        reduced += _parseInt(item['reducedQuantity']);
      }
    }

    return {'starting': starting, 'remaining': remaining, 'reduced': reduced};
  }

  String _assignedInventoryLabel(Map<String, dynamic> data) {
    final name = data['name']?.toString().trim();
    final safeName = name == null || name.isEmpty ? 'Inventory' : name;

    if (data['isCoffee'] == true) {
      return '$safeName - Coffee';
    }

    if (data['isAddon'] == true) {
      return '$safeName - Add-on';
    }

    if (data['isBundle'] == true) {
      final count = _parseInt(data['bundleCount']);
      return '$safeName - $count bundle${count == 1 ? '' : 's'}';
    }

    final items = (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((item) {
          final stock = item.containsKey('stock')
              ? _parseInt(item['stock'])
              : _parseInt(item['startingStock']);
          return stock > 0;
        })
        .map((item) {
          final itemName = item['name']?.toString().trim();
          final stock = item.containsKey('stock')
              ? _parseInt(item['stock'])
              : _parseInt(item['startingStock']);
          return '${itemName == null || itemName.isEmpty ? 'Item' : itemName} x$stock';
        })
        .toList();

    return items.isEmpty ? safeName : '$safeName - ${items.join(', ')}';
  }

  bool _hasExpiredAssignedBundleItem(Map<String, dynamic> data) {
    final bundleItems = data['items'] as List<dynamic>? ?? [];
    for (final raw in bundleItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (_isExpiredInventoryItem(item['expirationDate']?.toString() ?? '')) {
        return true;
      }
    }

    final instances = data['bundleInstances'] as List<dynamic>? ?? [];
    for (final rawInstance in instances) {
      if (rawInstance is! Map) continue;
      final instance = Map<String, dynamic>.from(rawInstance);
      final items = instance['items'] as List<dynamic>? ?? [];
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        if (_isExpiredInventoryItem(item['expirationDate']?.toString() ?? '')) {
          return true;
        }
      }
    }
    return false;
  }

  int _availableAssignedBundleCount(Map<String, dynamic> data) {
    final instances = data['bundleInstances'] as List<dynamic>? ?? [];
    if (instances.isEmpty) return _parseInt(data['bundleCount']);
    return instances.where((raw) {
      if (raw is! Map) return false;
      final status =
          raw['status']?.toString().trim().toLowerCase() ?? 'available';
      return status == 'available';
    }).length;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _activeAssignedInventoryDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final rootSnapshot = await _firestore.collection('sales_inventory').get();
    final activeRootById = <String, Map<String, dynamic>>{};
    final activeRootByName = <String, Map<String, dynamic>>{};
    for (final rootDoc in rootSnapshot.docs) {
      final rootData = rootDoc.data();
      if (rootData['isDeleted'] == true) continue;
      activeRootById[rootDoc.id] = rootData;
      final rootName = rootData['name']?.toString().trim().toLowerCase() ?? '';
      if (rootName.isNotEmpty) activeRootByName[rootName] = rootData;
    }

    String itemKey(Map<String, dynamic> item) =>
        '${item['name'] ?? ''}|${item['price'] ?? ''}'.toLowerCase();

    return docs.where((doc) {
      final data = doc.data();
      if (data['isDeleted'] == true) return false;
      if (data['isCoffee'] == true || data['isAddon'] == true) return true;

      final sourceId = data['sourceInventoryId']?.toString().trim() ?? '';
      final name = data['name']?.toString().trim().toLowerCase() ?? '';
      final rootData = activeRootById[sourceId] ?? activeRootByName[name];
      if (rootData == null) return false;

      if (data['isBundle'] == true) {
        if (rootData['isBundle'] != true) return false;
        if (_hasExpiredAssignedBundleItem(data)) return false;
        if (_hasExpiredAssignedBundleItem(rootData)) return false;
        return _availableAssignedBundleCount(data) > 0;
      }

      final rootKeys = ((rootData['items'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((item) => itemKey(Map<String, dynamic>.from(item)))
          .toSet();
      final activeItems = ((data['items'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) {
            final stock = item.containsKey('stock')
                ? _parseInt(item['stock'])
                : _parseInt(item['startingStock']);
            return stock > 0 &&
                !_isExpiredInventoryItem(
                  item['expirationDate']?.toString() ?? '',
                ) &&
                (rootKeys.isEmpty || rootKeys.contains(itemKey(item)));
          })
          .toList();
      return activeItems.isNotEmpty;
    }).toList();
  }

  Widget _assignedTableCell(
    String text, {
    FontWeight weight = FontWeight.w600,
    Color color = kBannerTop,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: weight, color: color),
      ),
    );
  }

  Widget _assignedWarningCell(
    String text, {
    required bool showWarning,
    Color color = kBannerTop,
    FontWeight weight = FontWeight.w700,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showWarning) ...[
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: Color(0xFFF9A825),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: weight, color: color),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _assignedInventoryRows(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final name = data['name']?.toString().trim() ?? 'Inventory';
    if (data['isBundle'] == true) {
      final count = _availableAssignedBundleCount(data);
      return [
        {
          'id': data['bundleId']?.toString().trim().isNotEmpty == true
              ? data['bundleId'].toString()
              : doc.id,
          'name': name,
          'type': 'Bundle',
          'stock': count,
          'used':
              _parseInt(data['assignedStartingStock'], fallback: count) - count,
          'reduced': 0,
          'expiry': '--',
        },
      ];
    }

    final items = ((data['items'] as List<dynamic>?) ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
          final stock = item.containsKey('stock')
              ? _parseInt(item['stock'])
              : _parseInt(item['startingStock']);
          return stock > 0 &&
              !_isExpiredInventoryItem(
                item['expirationDate']?.toString() ?? '',
              );
        })
        .toList();

    return items.map((item) {
      final stock = item.containsKey('stock')
          ? _parseInt(item['stock'])
          : _parseInt(item['startingStock']);
      final starting = _parseInt(
        item['assignedStartingStock'],
        fallback: _parseInt(item['startingStock'], fallback: stock),
      );
      final reduced = _parseInt(item['reducedQuantity']);
      return {
        'id': item['id']?.toString().trim().isNotEmpty == true
            ? item['id'].toString()
            : doc.id,
        'name': item['name']?.toString().trim().isNotEmpty == true
            ? item['name'].toString()
            : name,
        'type': data['isCoffee'] == true
            ? 'Coffee'
            : data['isAddon'] == true
            ? 'Add-on'
            : 'Item',
        'stock': stock,
        'used': (starting - stock - reduced).clamp(0, starting),
        'reduced': reduced,
        'expiry': item['expirationDate']?.toString().trim().isNotEmpty == true
            ? item['expirationDate'].toString()
            : '--',
      };
    }).toList();
  }

  Widget _buildAssignedInventoryPreview(String staffId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('staff_inventory')
          .where('staffId', isEqualTo: staffId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => _isActiveAllocationDocument(doc.data()))
            .toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAccent.withOpacity(0.75)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: kDeep,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Assigned to this staff (${docs.length})',
                    style: const TextStyle(
                      color: kBannerTop,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SizedBox(
                  height: 28,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: kPrimary,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                )
              else if (docs.isEmpty)
                Text(
                  'No assigned inventory yet.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 108),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: const BoxDecoration(
                              color: kPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _assignedInventoryLabel(data),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: kBannerTop,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeAssignedInventoryFromStaff(
    QueryDocumentSnapshot<Map<String, dynamic>> staffDoc,
  ) async {
    final staffRef = staffDoc.reference;
    final staffData = staffDoc.data();
    final sourceId = staffData['sourceInventoryId']?.toString() ?? '';
    final sourceRef = sourceId.isEmpty
        ? null
        : _firestore.collection('sales_inventory').doc(sourceId);

    await _firestore.runTransaction((transaction) async {
      final sourceSnapshot = sourceRef == null
          ? null
          : await transaction.get(sourceRef);
      final sourceData = sourceSnapshot?.data();

      if (sourceRef != null && sourceData != null) {
        if (staffData['isBundle'] == true) {
          final restoreCount = _parseInt(staffData['bundleCount']);
          final sourceCount = _parseInt(sourceData['bundleCount']);
          final sourceInstances =
              (sourceData['bundleInstances'] as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList();
          final staffInstances =
              (staffData['bundleInstances'] as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .map(
                    (entry) => {
                      ...Map<String, dynamic>.from(entry),
                      'status': 'available',
                    },
                  )
                  .toList();

          transaction.update(sourceRef, {
            'bundleCount': sourceCount + restoreCount,
            'bundleInstances': [...sourceInstances, ...staffInstances],
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final sourceItems = (sourceData['items'] as List<dynamic>? ?? [])
              .map(
                (entry) =>
                    entry is Map ? Map<String, dynamic>.from(entry) : entry,
              )
              .toList();
          final staffItems = (staffData['items'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();

          final updatedSourceItems = sourceItems.map((entry) {
            if (entry is! Map<String, dynamic>) return entry;
            final matchingStaffItem = staffItems
                .where((item) {
                  final staffId = item['id']?.toString() ?? '';
                  final sourceItemId = entry['id']?.toString() ?? '';
                  if (staffId.isNotEmpty && sourceItemId.isNotEmpty) {
                    return staffId == sourceItemId;
                  }
                  final staffName = item['name']?.toString() ?? '';
                  final sourceName = entry['name']?.toString() ?? '';
                  return staffName.isNotEmpty && staffName == sourceName;
                })
                .fold<int>(0, (sum, item) {
                  final stock = item.containsKey('stock')
                      ? _parseInt(item['stock'])
                      : _parseInt(item['startingStock']);
                  return sum + stock;
                });

            if (matchingStaffItem <= 0) return entry;
            final currentStock = entry.containsKey('stock')
                ? _parseInt(entry['stock'])
                : _parseInt(entry['startingStock']);
            return {...entry, 'stock': currentStock + matchingStaffItem};
          }).toList();

          transaction.update(sourceRef, {
            'items': updatedSourceItems,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      transaction.delete(staffRef);
    });
  }

  void _showAssignedInventoryDialog(String staffId, String staffName) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFFFFF8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.72,
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$staffName assigned items',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kBannerTop,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                      color: kDeep,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _firestore
                        .collection('staff_inventory')
                        .where('staffId', isEqualTo: staffId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final docs = (snapshot.data?.docs ?? []).where((doc) {
                        final data = doc.data();
                        if (data['isDeleted'] == true) return false;
                        if (data['isBundle'] == true) {
                          return !_hasExpiredAssignedBundleItem(data) &&
                              _availableAssignedBundleCount(data) > 0;
                        }
                        final activeItems =
                            ((data['items'] as List<dynamic>?) ?? [])
                                .whereType<Map>()
                                .map((item) => Map<String, dynamic>.from(item))
                                .where((item) {
                                  final stock = item.containsKey('stock')
                                      ? _parseInt(item['stock'])
                                      : _parseInt(item['startingStock']);
                                  return stock > 0 &&
                                      !_isExpiredInventoryItem(
                                        item['expirationDate']?.toString() ??
                                            '',
                                      );
                                })
                                .toList();
                        return data['isCoffee'] == true ||
                            data['isAddon'] == true ||
                            activeItems.isNotEmpty;
                      }).toList();

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: kPrimary),
                        );
                      }
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No assigned inventory.'),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(
                            kPrimary.withOpacity(0.08),
                          ),
                          columnSpacing: 18,
                          columns: const [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Type')),
                            DataColumn(label: Text('Stock')),
                            DataColumn(label: Text('Used')),
                            DataColumn(label: Text('Reduced')),
                            DataColumn(label: Text('Expiry')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: docs.expand((doc) {
                            final rows = _assignedInventoryRows(doc);
                            return rows.map((row) {
                              final stock = _parseInt(row['stock']);
                              final expiry = row['expiry']?.toString() ?? '--';
                              final isLowStock = stock > 0 && stock <= 50;
                              final isNearExpiry = _isNearExpiryInventoryItem(
                                expiry,
                              );
                              const warningColor = Color(0xFFF9A825);
                              return DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 140,
                                      child: _assignedTableCell(
                                        row['id']?.toString() ?? '--',
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 160,
                                      child: _assignedTableCell(
                                        row['name']?.toString() ?? 'Item',
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _assignedTableCell(
                                      row['type']?.toString() ?? 'Item',
                                    ),
                                  ),
                                  DataCell(
                                    _assignedWarningCell(
                                      stock.toString(),
                                      showWarning: isLowStock,
                                      color: isLowStock
                                          ? warningColor
                                          : kPrimary,
                                    ),
                                  ),
                                  DataCell(
                                    _assignedTableCell(
                                      row['used']?.toString() ?? '0',
                                    ),
                                  ),
                                  DataCell(
                                    _assignedTableCell(
                                      row['reduced']?.toString() ?? '0',
                                    ),
                                  ),
                                  DataCell(
                                    _assignedWarningCell(
                                      expiry,
                                      showWarning: isNearExpiry,
                                      color: isNearExpiry
                                          ? warningColor
                                          : kBannerTop,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      tooltip: 'Remove assigned item',
                                      onPressed: () async {
                                        try {
                                          await _removeAssignedInventoryFromStaff(
                                            doc,
                                          );
                                          if (!mounted) return;
                                          _showSnack(
                                            'Assigned item removed',
                                            Colors.green.shade600,
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          _showSnack(
                                            'Unable to remove item: $e',
                                            Colors.red.shade600,
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: kDeep,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            });
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAssignInventoryDialog(
    String staffId,
    String staffName, {
    bool isBranch = false,
  }) async {
    final qtyControllers = <String, TextEditingController>{};
    final selectedCoffeeIds = <String>{};
    final selectedAddonIds = <String>{};
    var showCategories = true;
    var showCoffee = false;
    var showAddons = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFFFFF8F3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxWidth: 760,
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Assign Inventory',
                            style: TextStyle(
                              color: kBannerTop,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                          color: kDeep,
                        ),
                      ],
                    ),
                    Text(
                      staffName,
                      style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildAssignedInventoryPreview(staffId),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.68,
                        ),
                        child: FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
                          future: Future.wait([
                            _firestore.collection('sales_inventory').get(),
                            _firestore
                                .collection('coffee_products')
                                .where('isDeleted', isEqualTo: false)
                                .get(),
                            _firestore
                                .collection('coffee_addons')
                                .where('isDeleted', isEqualTo: false)
                                .get(),
                            _firestore.collection('staff_inventory').get(),
                          ]),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              // Keep the dialog usable while inventory loads;
                              // do not show the large blocking loader.
                              return const SizedBox.shrink();
                            }
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text('Error loading inventory'),
                              );
                            }

                            final inventorySnapshot = snapshot.data?[0];
                            final coffeeSnapshot = snapshot.data?[1];
                            final addonSnapshot = snapshot.data?[2];
                            final assignedInventorySnapshot = snapshot.data?[3];
                            final assignedDocs =
                              assignedInventorySnapshot?.docs ??
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                            final activeDocs = (inventorySnapshot?.docs ?? [])
                                .where((doc) {
                                  final data = doc.data();
                                  final isSalesRecord =
                                      data['status'] == 'completed' ||
                                      data['salesId'] != null;
                                  return data['isDeleted'] != true &&
                                      data['deletedAt'] == null &&
                                      !isSalesRecord;
                                })
                                .toList();
                            final categoryDocs = activeDocs.where((doc) {
                              final data = doc.data();
                              return data['isBundle'] != true &&
                                  _assignableCategoryItems(data).isNotEmpty;
                            }).toList();
                            final bundleDocs = activeDocs.where((doc) {
                              final data = doc.data();
                              return data['isBundle'] == true &&
                                  _parseInt(data['bundleCount']) > 0;
                            }).toList();
                            final coffeeDocs = coffeeSnapshot?.docs ?? [];
                            final addonDocs = addonSnapshot?.docs ?? [];
                            final docs = showAddons
                                ? addonDocs
                                : showCoffee
                                ? coffeeDocs
                                : showCategories
                                ? categoryDocs
                                : bundleDocs;

                            if (categoryDocs.isEmpty &&
                                bundleDocs.isNotEmpty &&
                                showCategories &&
                                !showCoffee &&
                                !showAddons) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                setDialogState(() => showCategories = false);
                              });
                            }

                            if (categoryDocs.isEmpty &&
                                bundleDocs.isEmpty &&
                                coffeeDocs.isEmpty &&
                                addonDocs.isEmpty) {
                              return const Center(
                                child: Text('No inventory available.'),
                              );
                            }

                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _AssignModeButton(
                                        selected: showCategories,
                                        icon: Icons.category_rounded,
                                        label:
                                            'Categories (${categoryDocs.length})',
                                        onTap: () => setDialogState(() {
                                          showCategories = true;
                                          showCoffee = false;
                                          showAddons = false;
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _AssignModeButton(
                                        selected:
                                            !showCategories &&
                                            !showCoffee &&
                                            !showAddons,
                                        icon: Icons.inventory_2_rounded,
                                        label: 'Bundle (${bundleDocs.length})',
                                        onTap: () => setDialogState(() {
                                          showCategories = false;
                                          showCoffee = false;
                                          showAddons = false;
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _AssignModeButton(
                                        selected: showCoffee,
                                        icon: Icons.coffee_rounded,
                                        label: 'Coffee (${coffeeDocs.length})',
                                        onTap: () => setDialogState(() {
                                          showCategories = false;
                                          showCoffee = true;
                                          showAddons = false;
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _AssignModeButton(
                                        selected: showAddons,
                                        icon: Icons.add_circle_outline_rounded,
                                        label: 'Add-ons (${addonDocs.length})',
                                        onTap: () => setDialogState(() {
                                          showCategories = false;
                                          showCoffee = false;
                                          showAddons = true;
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: docs.isEmpty
                                      ? Center(
                                          child: Text(
                                            showCategories
                                                ? 'No active categories available.'
                                                : showAddons
                                                ? 'No add-ons available.'
                                                : showCoffee
                                                ? 'No coffee products available.'
                                                : 'No active bundles available.',
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: docs.length,
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(height: 10),
                                          itemBuilder: (context, index) {
                                            final doc = docs[index];
                                            final data = doc.data();
                                            if (showAddons) {
                                              final addonId = doc.id;
                                              return _AssignCoffeeTile(
                                                icon: Icons
                                                    .add_circle_outline_rounded,
                                                title:
                                                    data['name']?.toString() ??
                                                    'Add-on',
                                                subtitle:
                                                    '+ P${_parsePrice(data['priceDelta']).toStringAsFixed(2)}',
                                                selected: selectedAddonIds
                                                    .contains(addonId),
                                                onChanged: (checked) {
                                                  setDialogState(() {
                                                    if (checked == true) {
                                                      selectedAddonIds.add(
                                                        addonId,
                                                      );
                                                    } else {
                                                      selectedAddonIds.remove(
                                                        addonId,
                                                      );
                                                    }
                                                  });
                                                },
                                              );
                                            }
                                            if (showCoffee) {
                                              final productId = doc.id;
                                              final sizes =
                                                  (data['sizes']
                                                              as List<
                                                                dynamic
                                                              >? ??
                                                          [])
                                                      .length;
                                              return _AssignCoffeeTile(
                                                title:
                                                    data['name']?.toString() ??
                                                    'Coffee',
                                                subtitle:
                                                    '${data['category'] ?? 'Coffee'} - P${_parsePrice(data['basePrice']).toStringAsFixed(2)} - $sizes sizes',
                                                selected: selectedCoffeeIds
                                                    .contains(productId),
                                                onChanged: (checked) {
                                                  setDialogState(() {
                                                    if (checked == true) {
                                                      selectedCoffeeIds.add(
                                                        productId,
                                                      );
                                                    } else {
                                                      selectedCoffeeIds.remove(
                                                        productId,
                                                      );
                                                    }
                                                  });
                                                },
                                              );
                                            }
                                            final isBundle =
                                                data['isBundle'] == true;
                                            final name =
                                                data['name']?.toString() ??
                                                'Inventory';

                                            if (isBundle) {
                                              final stock = _parseInt(
                                                data['bundleCount'],
                                              );
                                              final key = '${doc.id}::bundle';
                                              final controller = qtyControllers
                                                  .putIfAbsent(
                                                    key,
                                                    () =>
                                                        TextEditingController(),
                                                  );
                                              return _AssignInventoryTile(
                                                title: name,
                                                subtitle:
                                                    'Bundle stock: $stock - P${_parsePrice(data['price']).toStringAsFixed(2)}',
                                                icon: Icons.inventory_2_rounded,
                                                controller: controller,
                                                enabled: stock > 0,
                                              );
                                            }

                                            final items =
                                                _assignableCategoryItems(data);
                                            return Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: kAccent,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: const TextStyle(
                                                      color: kBannerTop,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  ...items.map((entry) {
                                                    final item = entry.value;
                                                    final stock =
                                                        _displayAssignableStock(
                                                          item,
                                                          doc.id,
                                                          assignedDocs,
                                                        );
                                                    final itemName =
                                                        item['name']
                                                            ?.toString() ??
                                                        'Item';
                                                    final key =
                                                        '${doc.id}::${entry.key}';
                                                    final controller =
                                                        qtyControllers.putIfAbsent(
                                                          key,
                                                          () =>
                                                              TextEditingController(),
                                                        );
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      child: _AssignInventoryTile(
                                                        title: itemName,
                                                        subtitle:
                                                            'Stock: $stock - P${_parsePrice(item['price']).toStringAsFixed(2)}',
                                                        icon: Icons
                                                            .category_rounded,
                                                        controller: controller,
                                                        enabled: stock > 0,
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          FocusManager.instance.primaryFocus?.unfocus();
                          await _assignInventoryToStaff(
                            staffId: staffId,
                            staffName: staffName,
                            quantities: qtyControllers.map(
                              (key, controller) =>
                                  MapEntry(key, _parseInt(controller.text)),
                            ),
                            coffeeProductIds: selectedCoffeeIds,
                            addonIds: selectedAddonIds,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (e) {
                          if (!mounted) return;
                          _showSnack(
                            'Failed to assign inventory: $e',
                            Colors.red.shade600,
                          );
                        }
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: Text(
                        isBranch ? 'Assign to Branch' : 'Assign to Staff',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    FocusManager.instance.primaryFocus?.unfocus();
    for (final controller in qtyControllers.values) {
      controller.dispose();
    }
  }

  Future<void> _assignInventoryToStaff({
    required String staffId,
    required String staffName,
    required Map<String, int> quantities,
    Set<String> coffeeProductIds = const {},
    Set<String> addonIds = const {},
  }) async {
    final selected = quantities.entries
        .where((entry) => entry.value > 0)
        .toList();
    if (selected.isEmpty && coffeeProductIds.isEmpty && addonIds.isEmpty) {
      _showSnack(
        'Select coffee, add-ons, or enter at least one quantity',
        Colors.orange.shade700,
      );
      return;
    }

    final assignedStockByItem = <String, int>{};
    for (final sourceDocId in quantities.keys.map((key) => key.split('::').first).toSet()) {
      final assignedSnapshot = await _firestore
          .collection('staff_inventory')
          .where('sourceInventoryId', isEqualTo: sourceDocId)
          .get();
      for (final assignedDoc in assignedSnapshot.docs) {
        final assignedItems =
            (assignedDoc.data()['items'] as List<dynamic>? ?? []).whereType<Map>();
        for (final rawItem in assignedItems) {
          final assignedItem = Map<String, dynamic>.from(rawItem);
          final itemKey = assignedItem['id']?.toString().isNotEmpty == true
              ? assignedItem['id'].toString()
              : assignedItem['name']?.toString() ?? '';
          assignedStockByItem['$sourceDocId::$itemKey'] =
              (assignedStockByItem['$sourceDocId::$itemKey'] ?? 0) +
              _parseInt(assignedItem['stock'] ?? assignedItem['startingStock']);
        }
      }
    }

    final selectedAddonOptions = <Map<String, dynamic>>[];
    for (final addonId in addonIds) {
      final addonSnapshot = await _firestore
          .collection('coffee_addons')
          .doc(addonId)
          .get();
      final addonData = addonSnapshot.data();
      if (addonData == null || addonData['isDeleted'] == true) continue;
      selectedAddonOptions.add({
        'id': addonId,
        'name': addonData['name']?.toString() ?? 'Add-on',
        'priceDelta': _parsePrice(addonData['priceDelta']),
      });
    }

    await _firestore.runTransaction((transaction) async {
      final grouped = <String, Map<String, int>>{};
      for (final entry in selected) {
        final parts = entry.key.split('::');
        if (parts.length != 2) continue;
        grouped.putIfAbsent(parts.first, () => {})[parts.last] = entry.value;
      }

      final sourceSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final staffSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final coffeeSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final coffeeId in coffeeProductIds) {
        coffeeSnapshots[coffeeId] = await transaction.get(
          _firestore.collection('coffee_products').doc(coffeeId),
        );
      }
      final coffeeAddonOptions = <String, List<Map<String, dynamic>>>{};
      for (final coffeeId in coffeeProductIds) {
        final coffeeData = coffeeSnapshots[coffeeId]?.data();
        final addonIds = List<String>.from(
          coffeeData?['addonIds'] as List? ?? [],
        );
        final options = <Map<String, dynamic>>[];
        for (final addonId in addonIds) {
          final addonSnapshot = await transaction.get(
            _firestore.collection('coffee_addons').doc(addonId),
          );
          final addonData = addonSnapshot.data();
          if (addonData == null || addonData['isDeleted'] == true) continue;
          options.add({
            'id': addonId,
            'name': addonData['name']?.toString() ?? 'Add-on',
            'priceDelta': _parsePrice(addonData['priceDelta']),
          });
        }
        for (final addon in selectedAddonOptions) {
          final selectedAddonId = addon['id']?.toString() ?? '';
          if (selectedAddonId.isEmpty ||
              options.any((item) => item['id'] == selectedAddonId)) {
            continue;
          }
          options.add(addon);
        }
        coffeeAddonOptions[coffeeId] = options;
      }
      for (final sourceDocId in grouped.keys) {
        final sourceRef = _firestore
            .collection('sales_inventory')
            .doc(sourceDocId);
        final staffRef = _firestore
            .collection('staff_inventory')
            .doc(_staffInventoryDocId(staffId, sourceDocId));
        sourceSnapshots[sourceDocId] = await transaction.get(sourceRef);
        staffSnapshots[sourceDocId] = await transaction.get(staffRef);
      }

      for (final coffeeId in coffeeProductIds) {
        final coffeeData = coffeeSnapshots[coffeeId]?.data();
        if (coffeeData == null || coffeeData['isDeleted'] == true) continue;
        final staffRef = _firestore
            .collection('staff_inventory')
            .doc(_staffInventoryDocId(staffId, 'coffee_$coffeeId'));
        transaction.set(staffRef, {
          ...coffeeData,
          'staffId': staffId,
          'staffName': staffName,
          'sourceInventoryId': coffeeId,
          'sourceCollection': 'coffee_products',
          'addonOptions': coffeeAddonOptions[coffeeId] ?? const [],
          'isCoffee': true,
          'isBundle': false,
          'isDeleted': false,
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      for (final addon in selectedAddonOptions) {
        final addonId = addon['id']?.toString() ?? '';
        if (addonId.isEmpty) continue;
        final staffRef = _firestore
            .collection('staff_inventory')
            .doc(_staffInventoryDocId(staffId, 'addon_$addonId'));
        transaction.set(staffRef, {
          'staffId': staffId,
          'staffName': staffName,
          'sourceInventoryId': addonId,
          'sourceCollection': 'coffee_addons',
          'name': addon['name'] ?? 'Add-on',
          'priceDelta': addon['priceDelta'] ?? 0,
          'isAddon': true,
          'isCoffee': false,
          'isBundle': false,
          'isDeleted': false,
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      for (final sourceDocId in grouped.keys) {
        final sourceRef = _firestore
            .collection('sales_inventory')
            .doc(sourceDocId);
        final staffRef = _firestore
            .collection('staff_inventory')
            .doc(_staffInventoryDocId(staffId, sourceDocId));
        final sourceSnapshot = sourceSnapshots[sourceDocId]!;
        final staffSnapshot = staffSnapshots[sourceDocId]!;
        final sourceData = sourceSnapshot.data();
        if (sourceData == null) continue;

        final isBundle = sourceData['isBundle'] == true;
        final staffData = staffSnapshot.data();
        final selectedForDoc = grouped[sourceDocId]!;

        if (isBundle) {
          final qty = selectedForDoc['bundle'] ?? 0;
          if (qty <= 0) continue;
          final currentStock = _parseInt(sourceData['bundleCount']);
          if (qty > currentStock) {
            throw Exception(
              'Not enough bundle stock for ${sourceData['name']}',
            );
          }
          final currentStaffCount = _parseInt(staffData?['bundleCount']);
          final currentAssignedStartingStock = _parseInt(
            staffData?['assignedStartingStock'],
            fallback: currentStaffCount,
          );
          final sourceInstances =
              (sourceData['bundleInstances'] as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList();
          final existingStaffInstances =
              (staffData?['bundleInstances'] as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList();
          final assignedAt = Timestamp.now();
          final selectedInstances = sourceInstances
              .where(
                (instance) =>
                    (instance['status']?.toString() ?? 'available') ==
                    'available',
              )
              .take(qty)
              .map(
                (instance) => {
                  ...instance,
                  'status': 'available',
                  'assignedAt': assignedAt,
                },
              )
              .toList();
          if (selectedInstances.length < qty) {
            final items = sourceData['items'] as List<dynamic>? ?? [];
            for (var i = selectedInstances.length; i < qty; i++) {
              final number = currentStaffCount + i + 1;
              selectedInstances.add({
                'number': number,
                'id': '${sourceData['bundleId'] ?? sourceDocId}-$number',
                'status': 'available',
                'assignedAt': assignedAt,
                'items': items,
              });
            }
          }
          final remainingSourceInstances = sourceInstances
              .where(
                (instance) => !selectedInstances.any(
                  (selected) => selected['id'] == instance['id'],
                ),
              )
              .toList();
          transaction.update(sourceRef, {
            'bundleCount': currentStock - qty,
            'bundleInstances': remainingSourceInstances,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(staffRef, {
            ...sourceData,
            'staffId': staffId,
            'staffName': staffName,
            'sourceInventoryId': sourceDocId,
            'bundleCount': currentStaffCount + qty,
            'assignedStartingStock': currentAssignedStartingStock + qty,
            'bundleInstances': [
              ...existingStaffInstances,
              ...selectedInstances,
            ],
            'isDeleted': false,
            'assignedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          continue;
        }

        final sourceItems = (sourceData['items'] as List<dynamic>? ?? [])
            .toList();
        final staffItems = (staffData?['items'] as List<dynamic>? ?? [])
            .toList();
        final updatedSourceItems = <dynamic>[];
        final assignedItems = <Map<String, dynamic>>[];

        for (var i = 0; i < sourceItems.length; i++) {
          final rawItem = sourceItems[i];
          if (rawItem is! Map<String, dynamic>) {
            updatedSourceItems.add(rawItem);
            continue;
          }
          final qty = selectedForDoc[i.toString()] ?? 0;
          if (qty <= 0) {
            updatedSourceItems.add(rawItem);
            continue;
          }
            var stock = rawItem.containsKey('stock')
              ? _parseInt(rawItem['stock'])
              : _parseInt(rawItem['startingStock']);
            if (stock <= 0) {
            final itemKey = rawItem['id']?.toString().isNotEmpty == true
              ? rawItem['id'].toString()
              : rawItem['name']?.toString() ?? '';
            stock = (_parseInt(rawItem['startingStock']) -
                (assignedStockByItem['$sourceDocId::$itemKey'] ?? 0))
              .clamp(0, _parseInt(rawItem['startingStock']))
              .toInt();
            }
          if (qty > stock) {
            throw Exception('Not enough stock for ${rawItem['name']}');
          }
          updatedSourceItems.add({...rawItem, 'stock': stock - qty});

          final existingIndex = staffItems.indexWhere((item) {
            if (item is! Map<String, dynamic>) return false;
            final staffItemId = item['id']?.toString() ?? '';
            final sourceItemId = rawItem['id']?.toString() ?? '';
            if (staffItemId.isNotEmpty && sourceItemId.isNotEmpty) {
              return staffItemId == sourceItemId;
            }
            return (item['name']?.toString() ?? '') ==
                (rawItem['name']?.toString() ?? '');
          });
          if (existingIndex >= 0 && staffItems[existingIndex] is Map) {
            final existing = Map<String, dynamic>.from(
              staffItems[existingIndex] as Map,
            );
            final existingStock = existing.containsKey('stock')
                ? _parseInt(existing['stock'])
                : _parseInt(existing['startingStock']);
            final existingStartingStock = existing.containsKey('startingStock')
                ? _parseInt(existing['startingStock'])
                : existingStock;
            staffItems[existingIndex] = {
              ...existing,
              'stock': existingStock + qty,
              'startingStock': existingStartingStock + qty,
              'assignedStartingStock':
                  _parseInt(
                    existing['assignedStartingStock'],
                    fallback: existingStartingStock,
                  ) +
                  qty,
            };
          } else {
            assignedItems.add({
              ...rawItem,
              'stock': qty,
              'startingStock': qty,
              'assignedStartingStock': qty,
            });
          }
        }

        staffItems.addAll(assignedItems);
        transaction.update(sourceRef, {
          'items': updatedSourceItems,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(staffRef, {
          ...sourceData,
          'staffId': staffId,
          'staffName': staffName,
          'sourceInventoryId': sourceDocId,
          'items': staffItems,
          'isDeleted': false,
          'isBundle': false,
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    if (selectedAddonOptions.isNotEmpty) {
      final coffeeSnapshot = await _firestore
          .collection('staff_inventory')
          .where('staffId', isEqualTo: staffId)
          .where('isCoffee', isEqualTo: true)
          .get();
      final batch = _firestore.batch();
      var updates = 0;
      for (final doc in coffeeSnapshot.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;
        final currentOptions = (data['addonOptions'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
        var changed = false;
        for (final addon in selectedAddonOptions) {
          final selectedAddonId = addon['id']?.toString() ?? '';
          if (selectedAddonId.isEmpty ||
              currentOptions.any((item) => item['id'] == selectedAddonId)) {
            continue;
          }
          currentOptions.add(addon);
          changed = true;
        }
        if (!changed) continue;
        batch.update(doc.reference, {
          'addonOptions': currentOptions,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updates++;
      }
      if (updates > 0) {
        await batch.commit();
      } else if (coffeeProductIds.isEmpty) {
        _showSnack(
          'Assign coffee first before assigning add-ons',
          Colors.orange.shade700,
        );
        return;
      }
    }

    await _firestore.collection('staff_inventory_history').add({
      'staffId': staffId,
      'staffName': staffName,
      'type': 'assignment',
      'quantities': quantities,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    _showSnack('Inventory assigned to $staffName', Colors.green.shade600);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadReportDocs(
    String staffId,
    String staffName,
  ) async {
    final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> collectReports(
      String collection,
      Query<Map<String, dynamic>> query,
    ) async {
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final reportType = (data['type'] as String?)?.trim().toLowerCase();
        if (collection == 'admin_notifications' && reportType != 'report') {
          continue;
        }
        allDocs[doc.id] = doc;
      }
    }

    try {
      if (staffId.trim().isNotEmpty) {
        await collectReports(
          'daily_reports',
          _firestore
              .collection('daily_reports')
              .where('staffId', isEqualTo: staffId),
        );
      }
      if (staffName.trim().isNotEmpty) {
        await collectReports(
          'daily_reports',
          _firestore
              .collection('daily_reports')
              .where('staffName', isEqualTo: staffName),
        );
      }
    } catch (_) {
      // Ignore.
    }

    try {
      if (staffId.trim().isNotEmpty) {
        await collectReports(
          'admin_notifications',
          _firestore
              .collection('admin_notifications')
              .where('type', isEqualTo: 'report')
              .where('staffId', isEqualTo: staffId),
        );
      }
      if (staffName.trim().isNotEmpty) {
        await collectReports(
          'admin_notifications',
          _firestore
              .collection('admin_notifications')
              .where('type', isEqualTo: 'report')
              .where('staffName', isEqualTo: staffName),
        );
      }
    } catch (_) {
      // Ignore.
    }

    final docs = allDocs.values.toList();
    docs.sort((a, b) {
      final aTime =
          (a.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          (b.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadBranchReportDocs({
    required String branchId,
    required List<String> staffIds,
    required List<String> staffNames,
  }) async {
    final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final staffId in staffIds) {
      final docs = await _loadReportDocs(staffId, '');
      for (final doc in docs) {
        allDocs[doc.id.replaceFirst(RegExp(r'^notification_'), '')] = doc;
      }
    }

    for (final staffName in staffNames) {
      final docs = await _loadReportDocs('', staffName);
      for (final doc in docs) {
        allDocs[doc.id.replaceFirst(RegExp(r'^notification_'), '')] = doc;
      }
    }

    Future<void> collectBranchReports(Query<Map<String, dynamic>> query) async {
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        allDocs[doc.id.replaceFirst(RegExp(r'^notification_'), '')] = doc;
      }
    }

    try {
      await collectBranchReports(
        _firestore
            .collection('daily_reports')
            .where('branchId', isEqualTo: branchId),
      );
      await collectBranchReports(
        _firestore
            .collection('admin_notifications')
            .where('type', isEqualTo: 'report')
            .where('branchId', isEqualTo: branchId),
      );
    } catch (_) {
      // Older reports do not always have branchId, so staff matching above is
      // still the main source.
    }

    final docs = allDocs.values.toList();
    docs.sort((a, b) {
      final aTime =
          (a.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          (b.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return docs;
  }

  Widget _buildUnsubmittedBranchReport(String branchId, String branchName, DateTime day) {
    return SizedBox(width: 720, height: 650, child: Column(children: [
      Padding(padding: const EdgeInsets.all(20), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Branch Staff Reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kDeep)),
          Text('$branchName · ${_reportDateLabel(day)}'),
          const SizedBox(height: 8),
          const Text('No saved closing report yet. Sales records for this date are shown below.'),
        ])),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('completed_sales').where('branchId', isEqualTo: branchId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Unable to load sales records.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: kPrimary));
          final records = snapshot.data!.docs.where((doc) => DateUtils.isSameDay(_dateValue(doc.data()['timestamp']), day)).toList()
            ..sort((a, b) => _dateValue(b.data()['timestamp']).compareTo(_dateValue(a.data()['timestamp'])));
          if (records.isEmpty) return const Center(child: Text('No sales records for this date.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _buildBranchReceiptCard(records[index].data(), records[index].id),
          );
        },
      )),
    ]));
  }

  void _showBranchReportDetail({
    required String branchId,
    required String branchName,
    required List<String> staffIds,
    required List<String> staffNames,
  }) {
    final reportDay = _analyticsDate ?? DateTime.now();
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFFFF8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _loadBranchReportDocs(
              branchId: branchId,
              staffIds: staffIds,
              staffNames: staffNames,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  width: 520,
                  height: 650,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Branch Staff Reports',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kBannerTop,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    branchName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF999999),
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(color: kPrimary),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final reportDocs = (snapshot.data ?? []).where((doc) {
                final data = doc.data();
                final savedBranch = data['branchId']?.toString() ?? '';
                return (savedBranch.isEmpty || savedBranch == branchId) &&
                    DateUtils.isSameDay(_reportDayFromData(data), reportDay);
              }).toList();
              if (!snapshot.hasError && reportDocs.isEmpty) {
                return _buildUnsubmittedBranchReport(branchId, branchName, reportDay);
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.assignment_outlined,
                        size: 48,
                        color: Color(0xFFCCCCCC),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        snapshot.hasError
                            ? 'Unable to load reports'
                            : '$branchName has no reports for ${_reportDateLabel(reportDay)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF666666),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Builder(builder: (context) {
                  final filteredReportDocs = reportDocs;
                  return SizedBox(
                    width: 520,
                    height: 650,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Branch Staff Reports',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: kBannerTop,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          branchName,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF666666),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Color(0xFF999999),
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                              Text(_reportDateLabel(reportDay)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            children: filteredReportDocs.map((doc) {
                              final data = doc.data();
                              final staffId = data['staffId']?.toString() ?? '';
                              final staffName =
                                  data['staffName']?.toString() ?? 'Staff';
                              return _buildReportCard(
                                doc,
                                staffId,
                                staffName,
                                branchName: branchName,
                                branchId: branchId,
                                branchCode: _branchCode(branchId),

                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showReportDetail(String staffId, String staffName) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFFFF8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child:
              FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                future: _loadReportDocs(staffId, staffName),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: kPrimary),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Color(0xFFCCCCCC),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Unable to load reports',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF666666),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final reportDocs = snapshot.data ?? [];

                  if (reportDocs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.assignment_outlined,
                            size: 48,
                            color: Color(0xFFCCCCCC),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '$staffName has no reports yet',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF666666),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Daily Reports',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: kBannerTop,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        staffName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF666666),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF999999),
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Column(
                              children: reportDocs
                                  .map(
                                    (doc) => _buildReportCard(
                                      doc,
                                      staffId,
                                      staffName,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadTransactionDetails(
    Map<String, dynamic> tx,
  ) async {
    final rawItems = tx['items'] as List<dynamic>?;
    final items = rawItems?.whereType<Map<String, dynamic>>().toList() ?? [];
    final salesId = tx['salesId']?.toString();
    final paidAmount = tx['paidAmount'] is num
        ? (tx['paidAmount'] as num).toDouble()
        : double.tryParse(tx['paidAmount']?.toString() ?? '') ?? 0.0;
    final change = tx['change'] is num
        ? (tx['change'] as num).toDouble()
        : double.tryParse(tx['change']?.toString() ?? '') ?? 0.0;

    if (items.isNotEmpty || salesId?.isEmpty != false) {
      return {'items': items, 'paidAmount': paidAmount, 'change': change};
    }

    final snapshot = await _firestore
        .collection('completed_sales')
        .where('salesId', isEqualTo: salesId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return {'items': items, 'paidAmount': paidAmount, 'change': change};
    }

    final fallbackData = snapshot.docs.first.data();
    final fallbackItems =
        (fallbackData['items'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final fallbackPaidAmount = fallbackData['paidAmount'] is num
        ? (fallbackData['paidAmount'] as num).toDouble()
        : double.tryParse(fallbackData['paidAmount']?.toString() ?? '') ?? 0.0;
    final fallbackChange = fallbackData['change'] is num
        ? (fallbackData['change'] as num).toDouble()
        : double.tryParse(fallbackData['change']?.toString() ?? '') ?? 0.0;

    return {
      'items': items.isNotEmpty ? items : fallbackItems,
      'paidAmount': paidAmount > 0 ? paidAmount : fallbackPaidAmount,
      'change': change > 0 ? change : fallbackChange,
    };
  }

  DateTime _reportDayFromData(Map<String, dynamic> data) {
    final reportDate = data['reportDate']?.toString();
    final parsedReportDate = reportDate == null
        ? null
        : DateTime.tryParse(reportDate);
    if (parsedReportDate != null) {
      return DateTime(
        parsedReportDate.year,
        parsedReportDate.month,
        parsedReportDate.day,
      );
    }

    final createdAt = data['createdAt'] as Timestamp?;
    final createdDate = createdAt?.toDate() ?? DateTime.now();
    return DateTime(createdDate.year, createdDate.month, createdDate.day);
  }

  bool _isSameReportDay(Timestamp? timestamp, DateTime reportDay) {
    if (timestamp == null) return false;
    final date = timestamp.toDate();
    return date.year == reportDay.year &&
        date.month == reportDay.month &&
        date.day == reportDay.day;
  }

  double _parseMoney(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _parseQty(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isRefundTransaction(Map<String, dynamic> data) {
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    final salesId = data['salesId']?.toString().trim().toLowerCase() ?? '';
    final items = data['items'] as List<dynamic>? ?? [];
    return type == 'refund' ||
        status == 'refund' ||
        salesId.startsWith('r-') ||
        data['fullyRefunded'] == true ||
        items.whereType<Map>().any((item) => _parseQty(item['refunded']) > 0);
  }

  Future<Map<String, dynamic>> _loadRefundDetails(
    String staffId,
    DateTime reportDay,
  ) async {
    final snapshot = await _firestore
        .collection('completed_sales')
        .where('userId', isEqualTo: staffId)
        .get();

    final refunds =
        snapshot.docs
            .where((doc) {
              final data = doc.data();
              final type = data['type']?.toString().toLowerCase();
              final status = data['status']?.toString().toLowerCase();
              return (type == 'refund' || status == 'refund') &&
                  _isSameReportDay(data['timestamp'] as Timestamp?, reportDay);
            })
            .map((doc) => doc.data())
            .toList()
          ..sort((a, b) {
            final aTs = (a['timestamp'] as Timestamp?)?.toDate();
            final bTs = (b['timestamp'] as Timestamp?)?.toDate();
            if (aTs == null || bTs == null) return 0;
            return bTs.compareTo(aTs);
          });

    final totalRefundAmount = refunds.fold<double>(0.0, (sum, refund) {
      final total = _parseMoney(refund['total']).abs();
      final delta = _parseMoney(refund['cashDrawerDelta']).abs();
      final subtotal = _parseMoney(refund['subtotal']).abs();
      return sum +
          (total > 0
              ? total
              : delta > 0
              ? delta
              : subtotal);
    });

    final totalRefundItems = refunds.fold<int>(0, (sum, refund) {
      final items = refund['items'] as List<dynamic>? ?? [];
      return sum +
          items.fold<int>(
            0,
            (itemSum, item) =>
                item is Map ? itemSum + _parseQty(item['quantity']) : itemSum,
          );
    });

    return {
      'refunds': refunds,
      'totalRefundAmount': totalRefundAmount,
      'totalRefundItems': totalRefundItems,
    };
  }

  void _showTransactionDetailsDialog(List<dynamic> transactions) {
    var query = '';
    var selectedFilter = 'All';
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFFFFF8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: SizedBox(
            width: 500,
            height: 560,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: kDeep),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Transaction details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kBannerTop,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => setDialogState(
                      () => query = value.trim().toLowerCase(),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search transaction',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: kDeep,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: kAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Categories', 'Bundle', 'Coffee items']
                          .map(
                            (label) => Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: selectedFilter == label,
                                selectedColor: kPrimary,
                                labelStyle: TextStyle(
                                  color: selectedFilter == label
                                      ? Colors.white
                                      : kDeep,
                                ),
                                onSelected: (_) => setDialogState(
                                  () => selectedFilter = label,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        final tx = Map<String, dynamic>.from(
                          transactions[index] as Map,
                        );
                        final salesId =
                            tx['salesId']?.toString() ??
                            'Transaction ${index + 1}';
                        final isRefund = _isRefundTransaction(tx);
                        final total = tx['total'] is num
                            ? (tx['total'] as num).toDouble()
                            : double.tryParse(tx['total']?.toString() ?? '') ??
                                  0;
                        return FutureBuilder<Map<String, dynamic>>(
                          future: _loadTransactionDetails(tx),
                          builder: (context, snapshot) {
                            final items =
                                (snapshot.data?['items']
                                    as List<Map<String, dynamic>>?) ??
                                [];
                            final summary = items.isEmpty
                                ? 'No item details'
                                : items
                                      .map(
                                        (item) =>
                                            '${_parseQty(item['quantity'])}× ${item['name'] ?? 'Product'}',
                                      )
                                      .join(', ');
                            final itemText =
                                '$summary ${tx['category'] ?? ''} ${tx['type'] ?? ''}'
                                    .toLowerCase();
                            final matchesSearch =
                                query.isEmpty ||
                                salesId.toLowerCase().contains(query) ||
                                itemText.contains(query);
                            final matchesFilter =
                                selectedFilter == 'All' ||
                                (selectedFilter == 'Bundle' &&
                                    itemText.contains('bundle')) ||
                                (selectedFilter == 'Coffee items' &&
                                    (itemText.contains('coffee') ||
                                        itemText.contains('smoothie'))) ||
                                (selectedFilter == 'Categories' &&
                                    !itemText.contains('bundle') &&
                                    !itemText.contains('coffee') &&
                                    !itemText.contains('smoothie'));
                            if (!matchesSearch || !matchesFilter) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: kAccent.withOpacity(.7),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                salesId,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: kBannerTop,
                                                ),
                                              ),
                                            ),
                                            if (isRefund) const _RefundBadge(),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          summary,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF777777),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '₱${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: kDeep,
                                    ),
                                  ),
                                ],
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
          ),
        ),
      ),
    );
  }

  Widget _buildReportCard(
    QueryDocumentSnapshot<Map<String, dynamic>> reportDoc,
    String staffId,
    String staffName, {
    String? branchName,
    String? branchId,
    String? branchCode,
    String paymentFilter = 'All',
  }) {
    final data = reportDoc.data();
    final createdAt = data['createdAt'] as Timestamp?;
    final reportDate = data['reportDate'] as String?;
    final cashDrawerTotal = data['cashDrawerTotal'];
    final openingCashValue =
        (data['openingCash'] as num?)?.toDouble() ??
        (data['allocatedBudget'] as num?)?.toDouble() ??
        0.0;
    final closingCashValue =
        (data['closingCash'] as num?)?.toDouble() ??
        (cashDrawerTotal as num?)?.toDouble() ??
        0.0;
    final drawerGainValue =
        (data['cashOverOpening'] as num?)?.toDouble() ??
        (closingCashValue - openingCashValue);
    final allTransactions = data['transactions'] as List<dynamic>? ?? [];
    final transactions = paymentFilter == 'All'
        ? allTransactions
        : allTransactions.where((transaction) {
            if (transaction is! Map) return false;
            final mode =
                transaction['paymentMode']?.toString().trim().toLowerCase() ??
                'cash';
            return mode == paymentFilter.toLowerCase();
          }).toList();
    final totalSales = paymentFilter == 'All'
        ? data['totalSales']
        : transactions.fold<double>(
            0,
            (sum, transaction) =>
                sum + _parseMoney((transaction as Map)['total']),
          );
    final transactionCount = transactions.length;
    final staffPublicId = data['staffPublicId']?.toString().trim() ?? '';
    final displayStaffId = staffPublicId.isNotEmpty ? staffPublicId : staffId;
    final branchLabel = branchName?.trim().isNotEmpty == true
        ? '$branchName - ${branchCode ?? ''}'
        : '$staffName${displayStaffId.isNotEmpty ? ' • $displayStaffId' : ''}';
    final closingInventory =
        (data['closingInventory'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final reportDay = _reportDayFromData(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          branchLabel,
          style: const TextStyle(
            color: kBannerTop,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          'Report: ${reportDate?.split('T').first ?? 'Unknown'}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Report Date',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF999999),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reportDate?.split('T').first ??
                              (createdAt != null
                                  ? createdAt
                                        .toDate()
                                        .toLocal()
                                        .toString()
                                        .split(' ')
                                        .first
                                  : 'Unknown'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kBannerTop,
                          ),
                        ),
                      ],
                    ),
                    if (createdAt != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Submitted At',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF999999),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            createdAt
                                .toDate()
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kAccent.withOpacity(0.45)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.badge_rounded, color: kDeep, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$staffName${displayStaffId.isNotEmpty ? '  •  ID: $displayStaffId' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: kBannerTop,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F2F5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Sales',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9E9E9E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₱${(totalSales as num?)?.toStringAsFixed(2) ?? '0.00'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kBannerTop,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F2F5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Closing Drawer',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF9E9E9E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₱${(cashDrawerTotal as num?)?.toStringAsFixed(2) ?? '0.00'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kBannerTop,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildRefundSummaryMetric(
                          'Opening Change Fund',
                          '₱${openingCashValue.toStringAsFixed(2)}',
                        ),
                      ),
                      Expanded(
                        child: _buildRefundSummaryMetric(
                          'Drawer Gain',
                          '₱${drawerGainValue.toStringAsFixed(2)}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Transactions',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9E9E9E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              transactionCount?.toString() ?? '0',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kBannerTop,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (transactions != null && transactions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${transactions.length} details',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (transactions != null && transactions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showTransactionDetailsDialog(transactions),
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: Text(
                        'View all ${transactions.length} transactions',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kDeep,
                        side: const BorderSide(color: kAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                if (branchId != null && branchId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showBranchItemsDialog(branchId, branchName ?? 'Branch'),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('View all items'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kDeep,
                        side: const BorderSide(color: kAccent),
                      ),
                    ),
                  ),
                ],
                if (_showInlineTransactionDetails &&
                    transactions != null &&
                    transactions.isNotEmpty) ...[
                  ...transactions.map((transaction) {
                    final tx = transaction as Map<String, dynamic>;
                    final salesId = tx['salesId']?.toString() ?? 'Unknown';
                    final isRefund = _isRefundTransaction(tx);
                    final transactionTotal = tx['total'] is num
                        ? (tx['total'] as num).toDouble()
                        : double.tryParse(tx['total']?.toString() ?? '') ?? 0.0;

                    return FutureBuilder<Map<String, dynamic>>(
                      future: _loadTransactionDetails(tx),
                      builder: (context, snapshot) {
                        final details = snapshot.data;
                        final items = details == null
                            ? null
                            : (details['items']
                                      as List<Map<String, dynamic>>?) ??
                                  [];
                        final paidAmount = details == null
                            ? 0.0
                            : (details['paidAmount'] as double?) ?? 0.0;
                        final change = details == null
                            ? 0.0
                            : (details['change'] as double?) ?? 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F2F5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Sales ID: $salesId',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: kBannerTop,
                                            ),
                                          ),
                                        ),
                                        if (isRefund) const _RefundBadge(),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₱${transactionTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: kBannerTop,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) ...[
                                const Text(
                                  'Loading transaction details...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF999999),
                                  ),
                                ),
                              ] else if (snapshot.hasError) ...[
                                Text(
                                  'Unable to load item details.',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF999999),
                                  ),
                                ),
                              ] else if (items == null || items.isEmpty) ...[
                                const Text(
                                  'No item details available for this transaction.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF999999),
                                  ),
                                ),
                              ] else ...[
                                ...items.map((item) {
                                  final itemName =
                                      item['name']?.toString().isNotEmpty ==
                                          true
                                      ? item['name'].toString()
                                      : 'Product';
                                  final variant =
                                      item['variant']?.toString() ?? '';
                                  final category =
                                      item['category']?.toString() ?? '';
                                  final title = variant.isNotEmpty
                                      ? '$itemName • $variant'
                                      : itemName;
                                  final qty = item['quantity'] is num
                                      ? (item['quantity'] as num).toInt()
                                      : int.tryParse(
                                              item['quantity']?.toString() ??
                                                  '',
                                            ) ??
                                            0;
                                  final priceValue = item['price'] is num
                                      ? (item['price'] as num).toDouble()
                                      : double.tryParse(
                                              item['price']?.toString() ?? '',
                                            ) ??
                                            0.0;
                                  final categoryText = category.isNotEmpty
                                      ? ' • $category'
                                      : '';

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$qty × $title$categoryText',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: kBannerTop,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Price: ₱${priceValue.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF999999),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 6),
                                if (paidAmount > 0) ...[
                                  Text(
                                    'Customer Payment: ₱${paidAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF999999),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Change',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                    Text(
                                      '₱${change.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  }),
                ],
                if (closingInventory.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Closing Inventory',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kBannerTop,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...closingInventory.map((entry) {
                    final categoryName =
                        entry['categoryName']?.toString() ?? 'Category';
                    final startingTotal = _parseQty(entry['startingTotal']);
                    final remainingTotal = _parseQty(entry['remainingTotal']);
                    final soldTotal = _parseQty(entry['soldTotal']);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F2F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kBannerTop,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildRefundSummaryMetric(
                                  'Started',
                                  '$startingTotal',
                                ),
                              ),
                              Expanded(
                                child: _buildRefundSummaryMetric(
                                  'Remaining',
                                  '$remainingTotal',
                                ),
                              ),
                              Expanded(
                                child: _buildRefundSummaryMetric(
                                  'Sold',
                                  '$soldTotal',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                FutureBuilder<Map<String, dynamic>>(
                  future: _loadRefundDetails(staffId, reportDay),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text(
                        'Loading refund records...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return const Text(
                        'Unable to load refund records.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
                      );
                    }

                    final details = snapshot.data ?? {};
                    final refunds = (details['refunds'] as List<dynamic>? ?? [])
                        .whereType<Map<String, dynamic>>()
                        .toList();
                    final totalRefundAmount =
                        (details['totalRefundAmount'] as double?) ?? 0.0;
                    final totalRefundItems =
                        (details['totalRefundItems'] as int?) ?? 0;

                    if (refunds.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Refund Records',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kBannerTop,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildRefundSummaryMetric(
                                  'Items Refunded',
                                  '$totalRefundItems',
                                ),
                              ),
                              Expanded(
                                child: _buildRefundSummaryMetric(
                                  'Money Deducted',
                                  '₱${totalRefundAmount.toStringAsFixed(2)}',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...refunds.map((refund) {
                          final salesId =
                              refund['salesId']?.toString() ?? 'Refund';
                          final reason =
                              refund['reason']?.toString() ?? 'No reason';
                          final source = refund['source']?.toString() ?? '';
                          final total = _parseMoney(refund['total']).abs();
                          final delta = _parseMoney(
                            refund['cashDrawerDelta'],
                          ).abs();
                          final subtotal = _parseMoney(
                            refund['subtotal'],
                          ).abs();
                          final amount = total > 0
                              ? total
                              : delta > 0
                              ? delta
                              : subtotal;
                          final items = refund['items'] as List<dynamic>? ?? [];
                          final itemCount = items.fold<int>(
                            0,
                            (sum, item) => item is Map
                                ? sum + _parseQty(item['quantity'])
                                : sum,
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F2F5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        salesId,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: kBannerTop,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '-₱${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: Color(0xFFC62828),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$itemCount item${itemCount == 1 ? '' : 's'} refunded',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: kBannerTop,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Reason${source.isNotEmpty ? ' ($source)' : ''}: $reason',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF777777),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundSummaryMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF999999),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: kBannerTop,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmResetStaffCashDrawer(String staffId) async {
    if (!mounted) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final dailyReportSnapshot = await _firestore
        .collection('daily_reports')
        .where('staffId', isEqualTo: staffId)
        .get();

    final notificationReportSnapshot = await _firestore
        .collection('admin_notifications')
        .where('type', isEqualTo: 'report')
        .where('staffId', isEqualTo: staffId)
        .get();

    final hasTodayReport =
        [...dailyReportSnapshot.docs, ...notificationReportSnapshot.docs].any((
          doc,
        ) {
          final createdAt = doc.data()['createdAt'] as Timestamp?;
          if (createdAt == null) return false;
          return createdAt.toDate().isAfter(
            startOfDay.subtract(const Duration(microseconds: 1)),
          );
        });

    if (!hasTodayReport) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Report Required'),
            content: const Text(
              'Cannot reset cash drawer until the staff submits a cash drawer report.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset Cash Drawer'),
          content: const Text(
            'Are you sure you want to reset this cash drawer to zero?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _firestore
                      .collection('staff_cash_drawer')
                      .doc(staffId)
                      .set({'balance': 0}, SetOptions(merge: true));
                  if (!mounted) return;
                  _showSnack(
                    'Cash drawer reset to ₱0.00',
                    Colors.green.shade600,
                  );
                } catch (e) {
                  if (!mounted) return;
                  _showSnack(
                    'Unable to reset cash drawer: $e',
                    Colors.red.shade600,
                  );
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _showBudgetHistory() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFFFF8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('branches')
                .orderBy('name')
                .snapshots(),
            builder: (context, branchSnapshot) {
              if (branchSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: kPrimary),
                );
              }

              if (branchSnapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Color(0xFFCCCCCC),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Unable to load budget history',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF666666),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final branchNamesById = <String, String>{};
              for (var doc in branchSnapshot.data?.docs ?? []) {
                final data = doc.data() as Map<String, dynamic>;
                branchNamesById[doc.id] =
                    data['name']?.toString().trim().isNotEmpty == true
                    ? data['name'].toString().trim()
                    : 'Branch';
              }

              if (branchNamesById.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 48,
                        color: Color(0xFFCCCCCC),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No branches yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF666666),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('budget_history')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, budgetSnapshot) {
                  if (budgetSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: kPrimary),
                    );
                  }

                  final allHistoryDocs = budgetSnapshot.data?.docs ?? [];
                  final budgetDocs = allHistoryDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final branchId =
                        data['branchId']?.toString() ??
                        data['staffId']?.toString() ??
                        '';
                    final targetType =
                        data['targetType']?.toString().toLowerCase() ?? '';
                    return branchNamesById.containsKey(branchId) ||
                        targetType == 'branch';
                  }).toList();

                  if (budgetDocs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.history_outlined,
                            size: 48,
                            color: Color(0xFFCCCCCC),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No budget allocations yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF666666),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 32,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Budget Allocation History',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kBannerTop,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF999999),
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Column(
                              children: budgetDocs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final branchId =
                                    data['branchId']?.toString() ??
                                    data['staffId']?.toString() ??
                                    '';
                                final branchName =
                                    data['branchName']?.toString() ??
                                    branchNamesById[branchId] ??
                                    data['staffName']?.toString() ??
                                    'Unknown Branch';
                                final amount = data['amount'] as num? ?? 0;
                                final createdAt =
                                    data['createdAt'] as Timestamp?;

                                final dateStr = createdAt != null
                                    ? createdAt
                                          .toDate()
                                          .toLocal()
                                          .toString()
                                          .split('.')
                                          .first
                                    : 'Unknown Date';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  branchName,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: kBannerTop,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Allocated: ₱${amount.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF999999),
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '₱${amount.toStringAsFixed(2)}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: kPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Allocated',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF999999),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5F0F5),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Allocated At: $dateStr',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF888888),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimary,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Close',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green.shade600
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5EEF0),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _selectedBranchId == null
          ? null
          : _buildBranchQuickActions(
              branchId: _selectedBranchId!,
              branchName: _activeBranchName,
              staffIds: _activeBranchStaffIds,
              staffNames: _activeBranchStaffNames,
              controller: _budgetControllers.putIfAbsent(
                _selectedBranchId!,
                () => TextEditingController(),
              ),
              enabled: _activeBranchStaffIds.isNotEmpty,
            ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              if (_selectedBranchId == null)
                SliverToBoxAdapter(child: _buildHeader())
              else
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedBudgetHeaderDelegate(
                    minHeight: 118, maxHeight: 118,
                    child: _buildSelectedBranchHeader(),
                  ),
                ),
              if (_selectedBranchId != null)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedBudgetHeaderDelegate(
                    minHeight: 80,
                    maxHeight: 80,
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        child: _buildAllocationSearch(),
                      ),
                    ),
                  ),
                ),
              if (_selectedBranchId == null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedBudgetHeaderDelegate(
                    minHeight: 142,
                    maxHeight: 142,
                    child: _buildPinnedBudgetControls(),
                  ),
                ),
              ],
              if (_selectedBranchId == null) ...[
                SliverToBoxAdapter(child: _buildBranchManagementSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ] else
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildSelectedBranchContent(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedBudgetControls() {
    return Material(
      color: const Color(0xFFF5EEF0),
      elevation: 4,
      shadowColor: kPrimary.withOpacity(0.10),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildBranchToolbar(),
          const SizedBox(height: 10),
          _buildBranchSearchField(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildBranchToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('branches').snapshots(),
        builder: (context, snapshot) {
          final branchCount =
              snapshot.data?.docs
                  .where((doc) => doc.data()['isVoided'] != true)
                  .length ??
              0;
          return Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Branches',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kBannerTop,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kPrimary.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Text(
                  branchCount == 1 ? '1 branch' : '$branchCount branches',
                  style: const TextStyle(
                    fontSize: 11,
                    color: kDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _showCreateBranchDialog,
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: const Text('Create'),
                style: TextButton.styleFrom(foregroundColor: kPrimary),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('branches')
                    .where('isVoided', isEqualTo: true)
                    .snapshots(),
                builder: (context, voidedSnapshot) {
                  final count = voidedSnapshot.data?.docs.length ?? 0;
                  return TextButton.icon(
                    onPressed: count == 0 ? null : _showVoidedBranchesDialog,
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text('Voided${count == 0 ? '' : ' ($count)'}'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBranchSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _branchSearchController,
        onChanged: (value) =>
            setState(() => _branchSearchQuery = value.trim().toLowerCase()),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search branches',
          prefixIcon: const Icon(Icons.search_rounded, color: kDeep),
          suffixIcon: _branchSearchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: kDeep),
                  onPressed: () {
                    _branchSearchController.clear();
                    setState(() => _branchSearchQuery = '');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: kAccent.withOpacity(0.65)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: kAccent.withOpacity(0.65)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
        ),
      ),
    );
  }

  // ─── PREMIUM HEADER BANNER ───────────────────────────────────────
  Widget _buildSelectedBranchContent() {
    final branchId = _selectedBranchId!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('branches').doc(branchId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load branch: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: kPrimary),
          );
        }
        final branch = snapshot.data!;
        if (!branch.exists) {
          return const Center(child: Text('This branch no longer exists.'));
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildSelectedBranchDetail(branch),
        );
      },
    );
  }

  Widget _buildBranchManagementSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _branchesStream,
        builder: (context, snapshot) {
          final branches = (snapshot.data?.docs ?? [])
              .where((doc) => doc.data()['isVoided'] != true)
              .toList();
          final visibleBranches = _branchSearchQuery.isEmpty
              ? branches
              : branches.where((doc) {
                  final data = doc.data();
                  final name = data['name']?.toString().toLowerCase() ?? '';
                  final staffNames =
                      (data['staffNames'] as List<dynamic>? ?? [])
                          .map((name) => name.toString().toLowerCase())
                          .join(' ');
                  return name.contains(_branchSearchQuery) ||
                      staffNames.contains(_branchSearchQuery);
                }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  ),
                )
              else if (branches.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kAccent.withOpacity(0.55)),
                  ),
                  child: const Text(
                    'Create a branch first, then assign inventory to it.',
                    style: TextStyle(
                      color: Color(0xFF777777),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (visibleBranches.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kAccent.withOpacity(0.55)),
                  ),
                  child: Text(
                    'No branch found for "${_branchSearchController.text.trim()}".',
                    style: const TextStyle(
                      color: Color(0xFF777777),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (_selectedBranchId == null)
                ...visibleBranches.map((doc) {
                  final data = doc.data();
                  final name = data['name']?.toString() ?? 'Branch';
                  final staffIds = (data['staffIds'] as List<dynamic>? ?? [])
                      .map((id) => id.toString().trim())
                      .where((id) => id.isNotEmpty)
                      .toList();
                  final branchId = doc.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () =>
                            setState(() {
                              _selectedBranchId = branchId;
                              _activeBranchName = name;
                              _activeBranchStaffIds = (data['staffIds'] as List<dynamic>? ?? []).map((id) => id.toString()).toList();
                              _activeBranchStaffNames = (data['staffNames'] as List<dynamic>? ?? []).map((staff) => staff.toString()).toList();
                            }),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: kAccent.withOpacity(0.6)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.store_mall_directory_rounded,
                                  color: kDeep,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: kBannerTop,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit branch',
                                onPressed: () =>
                                    _showEditBranchDialog(branchId, name),
                                icon: const Icon(Icons.edit_rounded),
                                color: kDeep,
                              ),
                              IconButton(
                                tooltip: 'Void branch',
                                onPressed: () => _voidBranch(branchId, name),
                                icon: const Icon(Icons.archive_outlined),
                                color: Colors.orange.shade800,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                })
              else
                ...visibleBranches
                    .where((doc) => doc.id == _selectedBranchId)
                    .map((doc) => _buildSelectedBranchDetail(doc)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectedBranchDetail(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final branchId = doc.id;
    final branchName = data['name']?.toString() ?? 'Branch';
    final staffNames = (data['staffNames'] as List<dynamic>? ?? [])
        .map((name) => name.toString())
        .where((name) => name.trim().isNotEmpty)
        .toList();
    final staffIds = (data['staffIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final hasAssignedStaff = staffIds.isNotEmpty;
    final controller = _budgetControllers.putIfAbsent(
      branchId,
      () => TextEditingController(),
    );
    if (!_currentAllocations.containsKey(branchId)) {
      _firestore.collection('staff_budget').doc(branchId).get().then((budget) {
        if (!mounted || !budget.exists) return;
        setState(() {
          _currentAllocations[branchId] =
              (budget.data()?['allocatedBudget'] as num?)?.toDouble() ?? 0;
        });
      });
    }

    return Stack(
      children: [
        Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAccent.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          if (!hasAssignedStaff)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Assign staff first to allocate items or cash.',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 10),
          _buildBranchSalesSummary(branchId),
          const SizedBox(height: 8),
          _buildAllocationCategories(),
          const SizedBox(height: 8),
          _buildBranchItemsTable(branchId),
          const SizedBox(height: 12),
          const SizedBox(height: 16),
          _buildPeriodBranchAnalytics(branchId, branchName),
          const SizedBox(height: 82),
        ],
      ),
        ),
      ],
    );
  }

  Widget _branchActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: 160,
    height: 44,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  Widget _buildDatedCashDrawer(String branchId, DateTime day, double currentCash) {
    Widget amount(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
      ],
    );
    if (DateUtils.isSameDay(day, DateTime.now())) {
      return amount('Current Cash Drawer', '₱${currentCash.toStringAsFixed(2)}');
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('daily_reports').where('branchId', isEqualTo: branchId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return amount('Closing Cash Drawer', 'Unable to load');
        if (!snapshot.hasData) return amount('Closing Cash Drawer', 'Loading…');
        final reports = snapshot.data!.docs.where((doc) {
          final data = doc.data();
          return DateUtils.isSameDay(_reportDayFromData(data), day) &&
              (data['closingCash'] != null || data['cashDrawerTotal'] != null);
        }).toList()
          ..sort((a, b) => _dateValue(b.data()['createdAt']).compareTo(_dateValue(a.data()['createdAt'])));
        // Each report is a snapshot of the shared branch drawer, not an
        // amount to add across staff. Use the latest closing snapshot.
        if (reports.isEmpty) return amount('Closing Cash Drawer', 'No closing record');
        final report = reports.first.data();
        final closing = _parsePrice(report['closingCash'] ?? report['cashDrawerTotal']);
        return amount('Closing Cash Drawer', '₱${closing.toStringAsFixed(2)}');
      },
    );
  }

  Widget _buildBranchSalesSummary(String branchId) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _firestore.collection('completed_sales').where('branchId', isEqualTo: branchId).snapshots(),
    builder: (context, snapshot) {
      var revenue = 0.0;
      final now = DateTime.now();
      final selectedDay = _analyticsDate ?? now;
      for (final doc in snapshot.data?.docs ?? const []) {
        final sale = doc.data();
        final timestamp = sale['timestamp'];
        final soldAt = timestamp is Timestamp
            ? timestamp.toDate()
            : timestamp is DateTime
            ? timestamp
            : DateTime.tryParse(timestamp?.toString() ?? '');
        if (soldAt == null || soldAt.year != selectedDay.year || soldAt.month != selectedDay.month || soldAt.day != selectedDay.day) continue;
        revenue += _parsePrice(sale['total']);
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('staff_cash_drawer').doc(branchId).snapshots(),
        builder: (context, drawerSnapshot) {
          final drawer = drawerSnapshot.data?.data() ?? const <String, dynamic>{};
          // `balance` can include an old value that was left in the drawer.
          // Show today's opening cash plus today's cash sales instead, so a
          // newly allocated ₱1200 still displays as ₱1200 before any sale.
          final openingCash = _parsePrice(
            drawer['dailyOpeningCash'] ?? drawer['openingCash'] ?? drawer['balance'],
          );
          final cashSales = (snapshot.data?.docs ?? const [])
              .where((doc) {
                final sale = doc.data();
                final timestamp = sale['timestamp'];
                final soldAt = timestamp is Timestamp
                    ? timestamp.toDate()
                    : timestamp is DateTime
                    ? timestamp
                    : DateTime.tryParse(timestamp?.toString() ?? '');
                final payment = sale['paymentMethod']?.toString().toLowerCase() ??
                    sale['paymentMode']?.toString().toLowerCase() ?? 'cash';
                return soldAt != null &&
                    soldAt.year == now.year &&
                    soldAt.month == now.month &&
                    soldAt.day == now.day &&
                    payment == 'cash';
              })
              .fold<double>(0, (sum, doc) => sum + _parsePrice(doc.data()['total']));
          final cashDrawer = openingCash + cashSales;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kBannerTop, kPrimary]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Icon(Icons.insights_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("${_reportDateLabel(selectedDay)} Total Revenue", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            Text('₱${revenue.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
          ])),
          _buildDatedCashDrawer(branchId, selectedDay, cashDrawer),
        ]),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _showBranchReceipts(
                  branchId: branchId,
                  branchName: _activeBranchName,
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('View all records'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kDeep,
                  side: const BorderSide(color: kAccent),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  void _showBranchReceipts({
    required String branchId,
    required String branchName,
  }) {
    final now = _analyticsDate ?? DateTime.now();
    var receiptQuery = '';
    var paymentFilter = 'All';
    final receiptsStream = _firestore
        .collection('completed_sales')
        .where('branchId', isEqualTo: branchId)
        .snapshots();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => Dialog(
        backgroundColor: const Color(0xFFFFF8FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
          width: 720,
          height: 700,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: receiptsStream,
            builder: (context, snapshot) {
              final receipts = (snapshot.data?.docs ?? []).where((doc) {
                final sale = doc.data();
                final payment = _receiptPayment(sale);
                final searchable = [doc.id, sale['salesId'], sale['staffName'], sale['staffFullName'], sale['total'], payment, sale['items']].join(' ').toLowerCase();
                if (paymentFilter != 'All' && payment != paymentFilter.toLowerCase()) return false;
                if (receiptQuery.isNotEmpty && !searchable.contains(receiptQuery)) return false;
                final value = sale['timestamp'];
                final date = value is Timestamp
                    ? value.toDate()
                    : value is DateTime
                    ? value
                    : DateTime.tryParse(value?.toString() ?? '');
                return date != null &&
                    date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
              }).toList()
                ..sort((a, b) {
                  final aTime = _dateValue(a.data()['timestamp']);
                  final bTime = _dateValue(b.data()['timestamp']);
                  return bTime.compareTo(aTime);
                });
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kPrimary.withOpacity(.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: kDeep),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${_reportDateLabel(now)} receipts", style: const TextStyle(color: kBannerTop, fontSize: 20, fontWeight: FontWeight.w900)),
                              Text(branchName, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          onChanged: (value) => setDialogState(() => receiptQuery = value.trim().toLowerCase()),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search receipt ID, staff, item, or total',
                            prefixIcon: const Icon(Icons.search_rounded, color: kDeep),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: ['All', 'Cash', 'GCash'].map((payment) => ChoiceChip(
                          label: Text(payment),
                          selected: paymentFilter == payment,
                          onSelected: (_) => setDialogState(() => paymentFilter = payment),
                        )).toList()),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                    const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary)))
                  else if (receipts.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 54, color: Color(0xFFFFB6CC)),
                            SizedBox(height: 12),
                            Text('No matching receipts', style: TextStyle(color: kDeep, fontSize: 17, fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('Try another search, payment filter, or date.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: receipts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _buildBranchReceiptCard(receipts[index].data(), receipts[index].id),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      )),
    );
  }

  String _reportDateLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

  String _receiptPayment(Map<String, dynamic> sale) =>
      (sale['paymentMethod'] ?? sale['paymentMode'] ?? 'cash').toString().trim().toLowerCase();

  DateTime _dateValue(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);

  double _analyticsSaleValue(Map<String, dynamic> data) {
    final total = _parsePrice(data['total']);
    if (total != 0) return total.abs();
    final drawerDelta = _parsePrice(data['cashDrawerDelta']);
    if (drawerDelta != 0) return drawerDelta.abs();
    return _parsePrice(data['subtotal']).abs();
  }

  Future<String> _receiptStaffName(Map<String, dynamic> sale) async {
    final userId = sale['userId']?.toString().trim() ??
        sale['staffId']?.toString().trim() ?? '';
    final savedName = sale['staffName']?.toString().trim() ??
        sale['cashierName']?.toString().trim() ??
        sale['userName']?.toString().trim() ?? '';
    if (savedName.isNotEmpty) return savedName;
    if (userId.isEmpty) return 'Staff not recorded';
    try {
      final staff = await _firestore.collection('staff_requests').doc(userId).get();
      final data = staff.data();
      if (data == null) return 'Staff not recorded';
      final name = [
        data['firstName']?.toString().trim() ?? '',
        data['middleName']?.toString().trim() ?? '',
        data['lastName']?.toString().trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      return name.isEmpty ? (data['name']?.toString().trim() ?? 'Staff not recorded') : name;
    } catch (_) {
      return 'Staff not recorded';
    }
  }

  Widget _buildBranchReceiptCard(Map<String, dynamic> sale, String documentId) =>
      FutureBuilder<String>(
        future: _receiptStaffName(sale),
        builder: (context, snapshot) => _buildBranchReceiptCardContent(
          sale,
          documentId,
          snapshot.data ?? 'Loading staff…',
        ),
      );

  Widget _buildBranchReceiptCardContent(
    Map<String, dynamic> sale,
    String documentId,
    String staff,
  ) {
    final date = _dateValue(sale['timestamp']);
    final receiptId = sale['salesId']?.toString() ?? documentId;
    final activityStatus = _activityStatus(sale);
    final staffId = (sale['staffPublicId'] ?? sale['staffId'] ?? sale['userId'] ?? '').toString();
    final cardTitle = activityStatus == 'Reduced' ? staff : receiptId;
    final payment = sale['paymentMethod']?.toString() ?? sale['paymentMode']?.toString() ?? 'Cash';
    final total = _parsePrice(sale['total']);
    final paid = _parsePrice(sale['paidAmount']);
    final change = _parsePrice(sale['change']);
    final discount = _parsePrice(sale['discount']);
    final discountType = sale['discountType']?.toString() ?? '';
    final items = (sale['items'] as List<dynamic>? ?? []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: kAccent.withOpacity(.65))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_rounded, color: kPrimary), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(cardTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text('${date.hour % 12 == 0 ? 12 : date.hour % 12}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'} · $staff', style: const TextStyle(color: Colors.grey, fontSize: 12))])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(color: kDeep, fontWeight: FontWeight.w900, fontSize: 18)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE1F5EA), borderRadius: BorderRadius.circular(10)), child: Text(activityStatus, style: const TextStyle(color: Color(0xFF16834A), fontSize: 11, fontWeight: FontWeight.w800)))])
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
        ...items.map((item) { final quantity = _parseInt(item['quantity'], fallback: 1); final name = item['name']?.toString() ?? 'Item'; final variant = item['variant']?.toString() ?? item['coffeeSize']?.toString() ?? ''; final price = _parsePrice(item['price']) * quantity; return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: kPrimary.withOpacity(.10), borderRadius: BorderRadius.circular(8)), child: Text('${quantity}x', style: const TextStyle(color: kDeep, fontWeight: FontWeight.w800))), const SizedBox(width: 10), Expanded(child: Text(variant.isEmpty ? name : '$name · $variant', style: const TextStyle(fontWeight: FontWeight.w700))), Text('₱${price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700))])); }),
        Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF6F9), borderRadius: BorderRadius.circular(12)), child: Column(children: [
          _receiptDetail('Staff', staff),
          if (activityStatus == 'Reduced') _receiptDetail('Staff ID', staffId.isEmpty ? 'Not recorded' : staffId),
          if (sale['_filteredItems'] == true) const Align(alignment: Alignment.centerLeft, child: Text('Matching items shown; loss below is the full record total.', style: TextStyle(fontSize: 11, color: Colors.grey))),
          if (activityStatus != 'Reduced') _receiptDetail('Payment', payment),
          if (activityStatus != 'Completed') ...[
            _receiptDetail('Date', _reportDateLabel(date)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('Reason: ${sale['reason'] ?? "Not recorded"}')),
            ),
            if ((sale['comment']?.toString().trim() ?? '').isNotEmpty)
              Align(alignment: Alignment.centerLeft, child: Text('Comment: ${sale['comment']}')),
          ],
          if (discount > 0) _receiptDetail(discountType.isEmpty ? 'Discount' : 'Discount ($discountType)', '-₱${discount.toStringAsFixed(2)}'),
          if (paid > 0) _receiptDetail('Customer paid', '₱${paid.toStringAsFixed(2)}'),
          if (change > 0) _receiptDetail('Change', '₱${change.toStringAsFixed(2)}'),
          _receiptDetail(activityStatus == 'Completed' ? 'Total' : 'Loss', '₱${total.abs().toStringAsFixed(2)}', isTotal: true),
        ])),
      ]),
    );
  }

  Widget _receiptDetail(String label, String value, {bool isTotal = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600))), Text(value, style: TextStyle(color: isTotal ? kPrimary : kBannerTop, fontWeight: FontWeight.w900))]),
  );

  Widget _buildBranchAnalytics(String branchId) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _firestore.collection('completed_sales').where('branchId', isEqualTo: branchId).snapshots(),
    builder: (context, snapshot) {
      final sold = <String, int>{};
      for (final doc in snapshot.data?.docs ?? const []) {
        for (final raw in doc.data()['items'] as List<dynamic>? ?? const []) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final name = item['name']?.toString() ?? 'Item';
          sold[name] = (sold[name] ?? 0) + _parseInt(item['quantity']);
        }
      }
      final top = sold.entries.toList()
        ..sort((a, b) => _sellingRank == 'Low Selling'
            ? a.value.compareTo(b.value)
            : b.value.compareTo(a.value));
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFFFBFC), borderRadius: BorderRadius.circular(18), border: Border.all(color: kAccent)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sales Analytics', style: TextStyle(color: kBannerTop, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Daily · Weekly · Monthly sales overview', style: TextStyle(color: Colors.grey, fontSize: 12)),
          Wrap(spacing: 8, children: ['Day', 'Week', 'Month'].map((period) => ChoiceChip(label: Text(period), selected: _analyticsRange == period, selectedColor: kPrimary, labelStyle: TextStyle(color: _analyticsRange == period ? Colors.white : kDeep, fontWeight: FontWeight.w800), onSelected: (_) => setState(() => _analyticsRange = period))).toList()),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(_analyticsRange == 'Day' ? 8 : _analyticsRange == 'Week' ? 7 : 6, (i) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Container(height: 18.0 + ((i * (_analyticsRange == 'Month' ? 23 : 17)) % 70), decoration: BoxDecoration(color: kPrimary.withOpacity(.25 + i * .08), borderRadius: BorderRadius.circular(5))))))),
          const SizedBox(height: 16),
          const Text('Best-selling items', style: TextStyle(color: kDeep, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: ['Top Selling', 'Low Selling'].map((rank) => ChoiceChip(label: Text(rank), selected: _sellingRank == rank, selectedColor: kPrimary, labelStyle: TextStyle(color: _sellingRank == rank ? Colors.white : kDeep, fontWeight: FontWeight.w800), onSelected: (_) => setState(() => _sellingRank = rank))).toList()),
          const SizedBox(height: 8),
          if (top.isEmpty) const Text('No completed sales yet.', style: TextStyle(color: Colors.grey)) else ...top.take(3).map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 18), const SizedBox(width: 8), Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))), Text('${e.value} sold', style: const TextStyle(color: kDeep, fontWeight: FontWeight.w900))]))),
        ]),
      );
    },
  );

  Widget _buildBranchActivity(String branchId,
      Widget Function(List<Map<String, dynamic>>) builder) {
    // Each activity view owns stable subscriptions; nested rebuilds must not
    // replace streams or reuse another widget's single-subscription stream.
    final salesStream = _firestore.collection('completed_sales').where('branchId', isEqualTo: branchId).snapshots();
    final inventoryStream = _firestore.collection('staff_inventory').where('staffId', isEqualTo: branchId).snapshots();
    final adjustmentsStream = _firestore.collection('stock_adjustments').snapshots();
    return
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: salesStream,
        builder: (context, sales) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: inventoryStream,
          builder: (context, inventory) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: adjustmentsStream,
            builder: (context, adjustments) {
              if (sales.hasError || inventory.hasError || adjustments.hasError) {
                return const Padding(padding: EdgeInsets.all(16), child: Text('Unable to load branch activity.'));
              }
              if (!sales.hasData || !inventory.hasData || !adjustments.hasData) {
                return const Center(child: CircularProgressIndicator(color: kPrimary));
              }
              final sources = {for (final doc in inventory.data!.docs) doc.id: doc.data()};
              final records = sales.data!.docs.map((doc) => <String, dynamic>{...doc.data(), '_id': doc.id}).toList();
              for (final doc in adjustments.data!.docs) {
                final data = doc.data();
                final savedBranch = data['branchId']?.toString() ?? '';
                final source = sources[data['categoryId']?.toString()];
                if (savedBranch.isNotEmpty ? savedBranch != branchId : source == null) continue;
                final quantity = _parseInt(data['quantity']);
                if (quantity <= 0) continue;
                final price = _parsePrice(data['unitPrice'] ?? data['bundlePrice'] ?? source?['price']);
                final loss = data['lossAmount'] == null ? price * quantity : _parsePrice(data['lossAmount']).abs();
                records.add({
                  ...data,
                  '_id': doc.id,
                  'salesId': doc.id,
                  'type': 'reduced',
                  'status': 'Reduced',
                  'timestamp': data['createdAt'],
                  'total': loss,
                  'items': [{
                    'name': data['itemName'] ?? data['categoryName'] ?? 'Item',
                    'variant': data['variant'] ?? '',
                    'quantity': quantity,
                    'price': price,
                    'isBundle': source?['isBundle'] == true || data['type']?.toString().contains('bundle') == true,
                    'isCoffee': source?['isCoffee'] == true || data['type']?.toString().contains('coffee') == true,
                  }],
                });
              }
              return builder(records);
            },
          ),
        ),
      );
  }

  String _activityStatus(Map<String, dynamic> data) {
    final type = data['type']?.toString().toLowerCase();
    final status = data['status']?.toString().toLowerCase();
    if (type == 'refund' || status == 'refund') return 'Refund';
    if (type == 'reduce' || type == 'reduced' || status == 'reduce' || status == 'reduced') return 'Reduced';
    return 'Completed';
  }

  Future<List<Map<String, dynamic>>> _loadLossRecordStaff(List<Map<String, dynamic>> records) async {
    final staffLookups = <String, Future<Map<String, dynamic>>>{};
    Future<Map<String, dynamic>> lookup(String id) async {
      if (id.isEmpty) return {};
      try {
        final doc = await _firestore.collection('staff_requests').doc(id).get()
            .timeout(const Duration(seconds: 10));
        if (doc.exists) return doc.data() ?? {};
        final byPublicId = await _firestore.collection('staff_requests')
            .where('staffId', isEqualTo: id).limit(1).get()
            .timeout(const Duration(seconds: 10));
        return byPublicId.docs.isEmpty ? {} : byPublicId.docs.first.data();
      } catch (_) {
        return {};
      }
    }
    return Future.wait(records.map((record) async {
      final id = (record['userId'] ?? record['staffId'] ?? '').toString();
      final data = await staffLookups.putIfAbsent(id, () => lookup(id));
      final fullName = [data['firstName'], data['middleName'], data['lastName']]
          .map((part) => part?.toString().trim() ?? '').where((part) => part.isNotEmpty).join(' ');
      final savedName = (record['staffName'] ?? record['cashierName'] ?? record['userName'] ?? '').toString().trim();
      return <String, dynamic>{
        ...record,
        'staffName': savedName.isNotEmpty ? savedName
            : fullName.isNotEmpty ? fullName : data['name'] ?? 'Staff not recorded',
        'staffPublicId': record['staffPublicId'] ?? data['staffId'] ?? record['staffId'] ?? record['userId'] ?? '',
      };
    }));
  }

  void _showBranchLossItems(String branchId, String status, List<Map<String, dynamic>> records) {
    final day = _analyticsDate ?? DateTime.now();
    final range = _analyticsRange;
    final period = lossRecordPeriod(day, range);
    final matching = records.where((record) {
      final date = _dateValue(record['timestamp']);
      return _activityStatus(record) == status && !date.isBefore(period.start) && date.isBefore(period.end);
    }).map((record) => <String, dynamic>{...record, 'timestamp': _dateValue(record['timestamp'])}).toList();
    final staffRecords = _loadLossRecordStaff(matching);
    showDialog<void>(context: context, builder: (context) => BranchLossRecordsDialog(
      status: status, anchor: day, range: range, records: matching, staffRecords: staffRecords,
      cardBuilder: (record) => _buildBranchReceiptCardContent(
        record, record['_id']?.toString() ?? '', record['staffName']?.toString() ?? 'Loading staff…',
      ),
    ));
  }
  Widget _buildPeriodBranchAnalytics(String branchId, String branchName) => _buildBranchActivity(branchId,
    (records) {
      final now = _analyticsDate ?? DateTime.now();
      final isRefundView = _analyticsStatus == 'Refund';
      final isReducedView = _analyticsStatus == 'Reduced';
      final rankingTitle = isRefundView ? (_sellingRank == 'Low Selling' ? 'Low refund items' : 'High refund items') : isReducedView ? (_sellingRank == 'Low Selling' ? 'Low reduced items' : 'High reduced items') : 'Best-selling items';
      final itemAction = isRefundView ? 'refunded' : isReducedView ? 'reduced' : 'sold';
      String rankLabel(String rank) => rank == 'All' ? 'All'
          : isRefundView ? (rank == 'Top Selling' ? 'High refund items' : 'Low refund items')
          : isReducedView ? (rank == 'Top Selling' ? 'High reduced items' : 'Low reduced items')
          : rank;
      final today = DateTime(now.year, now.month, now.day);
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      const dayStartHour = 10;
      const dayEndHour = 19;
      final count = _analyticsRange == 'Day'
          ? dayEndHour - dayStartHour + 1
          : _analyticsRange == 'Week'
          ? 7
          : 12;
      final amounts = List<double>.filled(count, 0);
      final refundAmounts = List<double>.filled(count, 0);
      final reducedAmounts = List<double>.filled(count, 0);
      final allQuantities = <String, int>{};
      final categoryQuantities = <String, int>{};
      final bundleQuantities = <String, int>{};
      final coffeeQuantities = <String, int>{};
      var totalLoss = 0.0;
      var totalCompleted = 0.0;
      var totalRefund = 0.0;
      var totalReduced = 0.0;
      bool matches(DateTime date) => _analyticsRange == 'Day'
          ? date.year == now.year && date.month == now.month && date.day == now.day
          : _analyticsRange == 'Week'
          ? !DateTime(date.year, date.month, date.day).isBefore(weekStart) && DateTime(date.year, date.month, date.day).isBefore(weekStart.add(const Duration(days: 7)))
          : date.year == now.year;
      for (final data in records) {
        final status = _activityStatus(data);
        final isRefund = status == 'Refund';
        final isReduced = status == 'Reduced';
        final isCompleted = !isRefund && !isReduced;
        if ((_analyticsStatus == 'Refund' && !isRefund) ||
            (_analyticsStatus == 'Reduced' && !isReduced) ||
            (_analyticsStatus == 'Completed' && !isCompleted)) continue;
        final raw = data['timestamp'];
        final date = raw is Timestamp ? raw.toDate() : raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '');
        if (date == null || !matches(date)) continue;
        if (_analyticsRange == 'Day' &&
            (date.hour < dayStartHour || date.hour > dayEndHour)) {
          continue;
        }
        final bucket = _analyticsRange == 'Day'
            ? date.hour - dayStartHour
            : _analyticsRange == 'Week'
            ? DateTime(date.year, date.month, date.day).difference(weekStart).inDays
            : date.month - 1;
        final value = _analyticsSaleValue(data);
        amounts[bucket] += value;
        if (isRefund) refundAmounts[bucket] += value;
        if (isReduced) reducedAmounts[bucket] += value;
        if (isRefund) {
          totalRefund += value;
        } else if (isReduced) {
          totalReduced += value;
        } else {
          totalCompleted += value;
        }
        if (isRefund || isReduced) totalLoss += value.abs();
        for (final rawItem in data['items'] as List<dynamic>? ?? const []) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          // Sales data stores a parent category (e.g. Cookies) in `name`
          // and the actual sold product/flavor in `variant`.
          final variant = item['variant']?.toString().trim() ??
              item['coffeeSize']?.toString().trim() ?? '';
          final name = variant.isNotEmpty
              ? variant
              : item['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          final quantity = _parseInt(item['quantity'], fallback: 1);
          // Quantities are used only for the best-selling item ranking.
          // The graph aggregates each receipt total once, above.



          if (_analyticsStatus == 'All' && !isCompleted) continue;
          final category = item['category']?.toString().toLowerCase() ?? '';
          final isBundle = item['isBundle'] == true;
          final isCoffee = item['isCoffee'] == true || category.contains('coffee');

          allQuantities[name] = (allQuantities[name] ?? 0) + quantity;
          if (isBundle) {
            bundleQuantities[name] = (bundleQuantities[name] ?? 0) + quantity;
          } else if (isCoffee) {
            coffeeQuantities[name] = (coffeeQuantities[name] ?? 0) + quantity;
          } else {
            categoryQuantities[name] = (categoryQuantities[name] ?? 0) + quantity;
          }
        }
      }
      final labels = List.generate(count, (i) {
        if (_analyticsRange == 'Day') {
          final hour = i + dayStartHour;
          return '${hour % 12 == 0 ? 12 : hour % 12}${hour < 12 ? 'AM' : 'PM'}';
        }
        if (_analyticsRange == 'Week') {
          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final date = weekStart.add(Duration(days: i));
          return '${days[i]}\n${date.month}/${date.day}';
        }
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[i];
      });
      final selectedQuantities = switch (_sellingType) {
        'Categories' => categoryQuantities,
        'Bundle' => bundleQuantities,
        'Coffee Items' => coffeeQuantities,
        _ => allQuantities,
      };
      final ranked = selectedQuantities.entries.toList()
        ..sort((a, b) => _sellingRank == 'Low Selling'
            ? a.value.compareTo(b.value)
            : b.value.compareTo(a.value));
      final rangeLabel = _analyticsRange == 'Day'
          ? '${now.month}/${now.day}/${now.year} hourly sales (10AM–7PM)'
          : _analyticsRange == 'Week'
          ? '${weekStart.month}/${weekStart.day} - ${weekStart.add(const Duration(days: 6)).month}/${weekStart.add(const Duration(days: 6)).day}/${now.year}'
          : 'January - December ${now.year}';
      final graphColors = _analyticsStatus == 'Refund'
          ? const [Color(0xFFF9A825), Color(0xFFFFD54F)]
          : _analyticsStatus == 'Reduced'
          ? const [Color(0xFF1976D2), Color(0xFF64B5F6)]
          : _analyticsStatus == 'Completed'
          ? const [Color(0xFFE53935), Color(0xFFEF5350)]
          : const [kDeep, kPrimary];
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFFFBFC), borderRadius: BorderRadius.circular(18), border: Border.all(color: kAccent)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sales Analytics', style: TextStyle(color: kBannerTop, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4), Text(rangeLabel, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(spacing: 8, children: ['Day', 'Week', 'Month'].map((period) => ChoiceChip(label: Text(period), selected: _analyticsRange == period, selectedColor: kPrimary, labelStyle: TextStyle(color: _analyticsRange == period ? Colors.white : kDeep, fontWeight: FontWeight.w800), onSelected: (_) => setState(() => _analyticsRange = period))).toList()),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ['Refund', const Color(0xFFF9A825)],
                  ['Reduced', const Color(0xFF1976D2)],
                  ['Completed', const Color(0xFFE53935)],
                ].map((entry) {
                  final label = entry[0] as String;
                  final color = entry[1] as Color;
                  final active = _analyticsStatus == label;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _analyticsStatus = active ? 'All' : label),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: active ? [BoxShadow(color: color.withOpacity(.45), blurRadius: 7)] : [])),
                        const SizedBox(width: 7),
                        Text(label, style: TextStyle(color: active ? color : Colors.grey.shade700, fontSize: 12, fontWeight: active ? FontWeight.w900 : FontWeight.w700)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          if (_analyticsStatus == 'All') Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Total Completed: ₱${totalCompleted.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.w800)), Text('Total Reduced: ₱${totalReduced.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF1976D2), fontSize: 12, fontWeight: FontWeight.w800)), Text('Total Refund: ₱${totalRefund.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF9A825), fontSize: 12, fontWeight: FontWeight.w800))])),
          if (_analyticsStatus == 'Refund' || _analyticsStatus == 'Reduced') Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Total loss: ₱${totalLoss.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w900)), TextButton.icon(onPressed: () => _showBranchLossItems(branchId, _analyticsStatus, records), icon: const Icon(Icons.visibility_outlined, size: 16), label: Text(_analyticsStatus == 'Refund' ? 'View Refund items' : 'View Reduced items'), style: TextButton.styleFrom(foregroundColor: kDeep, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)))])),
          const SizedBox(height: 14), SizedBox(height: 240, child: BranchAnalyticsBars(values: amounts, labels: labels, colors: graphColors, refunds: _analyticsStatus == 'All' ? refundAmounts : null, reduced: _analyticsStatus == 'All' ? reducedAmounts : null, selectedStatus: _analyticsStatus)),
          const SizedBox(height: 16), Text(rankingTitle, style: const TextStyle(color: kDeep, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: ['All', 'Categories', 'Bundle', 'Coffee Items'].map((type) => ChoiceChip(label: Text(type), selected: _sellingType == type, selectedColor: kPrimary, labelStyle: TextStyle(color: _sellingType == type ? Colors.white : kDeep, fontWeight: FontWeight.w800), onSelected: (_) => setState(() => _sellingType = type))).toList()),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: ['All', 'Top Selling', 'Low Selling'].map((rank) => ChoiceChip(label: Text(rankLabel(rank)), selected: _sellingRank == rank, selectedColor: kPrimary, labelStyle: TextStyle(color: _sellingRank == rank ? Colors.white : kDeep, fontWeight: FontWeight.w800), onSelected: (_) => setState(() => _sellingRank = rank))).toList()),
          const SizedBox(height: 8),
          if (ranked.isEmpty) Text('No $itemAction items in this period yet.', style: const TextStyle(color: Colors.grey)) else ...(_sellingRank == 'All' ? ranked : ranked.take(5)).map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Icon(_sellingRank == 'Low Selling' ? Icons.trending_down_rounded : Icons.star_rounded, color: _sellingRank == 'Low Selling' ? Colors.orange : const Color(0xFFFFB300), size: 18), const SizedBox(width: 8), Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))), Text('${e.value} $itemAction', style: const TextStyle(color: kDeep, fontWeight: FontWeight.w900))]))),
        ]),
      );
    },
  );

  Widget _buildBranchQuickActions({required String branchId, required String branchName, required List<String> staffIds, required List<String> staffNames, required TextEditingController controller, required bool enabled}) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (_branchFabExpanded) ...[
        _animatedQuickAction(
        FloatingActionButton.small(heroTag: 'items_$branchId', onPressed: enabled ? () => _showAssignInventoryDialog(branchId, branchName, isBranch: true) : null, child: const Icon(Icons.add_box_rounded)),
          delay: 90,
        ),
        const SizedBox(height: 8),
        _animatedQuickAction(
        FloatingActionButton.small(heroTag: 'cash_$branchId', onPressed: enabled ? () => _showBranchCashDrawerDialog(branchId, branchName, controller, staffIds) : null, child: const Icon(Icons.payments_rounded)),
          delay: 135,
        ),
        const SizedBox(height: 8),
      ],
      FloatingActionButton(heroTag: 'quick_$branchId', backgroundColor: kPrimary, onPressed: () => setState(() => _branchFabExpanded = !_branchFabExpanded), child: Icon(_branchFabExpanded ? Icons.close_rounded : Icons.add_rounded)),
    ]);


  Widget _animatedQuickAction(Widget child, {required int delay}) => TweenAnimationBuilder<double>(
    duration: Duration(milliseconds: 220 + delay),
    curve: Curves.easeOutBack,
    tween: Tween(begin: 0, end: 1),
    builder: (context, value, _) => Opacity(opacity: value.clamp(0, 1), child: Transform.translate(offset: Offset(0, 18 * (1 - value)), child: Transform.scale(scale: value, child: child))),
  );

  Widget _buildAllocationFilters() => Column(children: [
    _buildAllocationSearch(),
    const SizedBox(height: 10),
    _buildAllocationCategories(),
  ]);

  Widget _buildAllocationCategories() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ['All', 'Categories', 'Bundle', 'Coffee']
            .map(
              (filter) => ChoiceChip(
                label: Text(filter),
                selected: _allocationFilter == filter,
                selectedColor: kPrimary.withOpacity(0.18),
                labelStyle: TextStyle(
                  color: _allocationFilter == filter
                      ? kBannerTop
                      : Colors.grey.shade700,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => setState(() => _allocationFilter = filter),
              ),
            )
            .toList(),
      );

  Widget _buildAllocationSearch() => TextField(
        controller: _allocationSearchController,
        onChanged: (value) =>
            setState(() => _allocationSearchQuery = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText:
              'Search',
          prefixIcon: const Icon(Icons.search_rounded, color: kDeep),
          suffixIcon: IconButton(
            tooltip: 'Filter sales, revenue, and receipts by date',
            icon: Icon(
              Icons.calendar_month_rounded,
              color: _analyticsDate == null ? kDeep : kPrimary,
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _analyticsDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null && mounted) {
                setState(() => _analyticsDate = picked);
              }
            },
          ),
          filled: true,
          fillColor: const Color(0xFFFFFBFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kAccent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kAccent),
          ),
        ),
      );

  void _showBranchCashDrawerDialog(
    String branchId,
    String branchName,
    TextEditingController controller,
    List<String> staffIds,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 390, maxWidth: 760),
            child: Material(
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildBranchAllocationPanel(
                  branchId: branchId,
                  branchName: branchName,
                  controller: controller,
                  staffIds: staffIds,
                  enabled: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBranchItemsDialog(String branchId, String branchName) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Allocated items · $branchName',
                        style: const TextStyle(
                          color: kBannerTop,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildAllocationFilters(),
                const SizedBox(height: 10),
                Expanded(
                  child: _buildBranchItemsTable(
                    branchId,
                    showAllocationDetails: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchItemsTable(
    String branchId, {
    bool showAllocationDetails = false,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _branchInventoryStreams.putIfAbsent(
        branchId,
        () => _firestore
            .collection('staff_inventory')
            .where('staffId', isEqualTo: branchId)
            .snapshots(),
      ),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) {
              final data = doc.data();
              return data['isDeleted'] != true;
            })
            .toList();
        // Cached snapshot data is already safe to display.  Waiting for a
        // server refresh must not leave the View all items dialog spinning.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: kPrimary),
            ),
          );
        }
        final rows = docs.expand(_allocationRowsForDocument).where((row) {
          final matchesFilter =
              _allocationFilter == 'All' ||
              (_allocationFilter == 'Bundle' && row.type == 'Bundle') ||
              (_allocationFilter == 'Coffee' && row.type == 'Coffee') ||
              (_allocationFilter == 'Categories' && row.type == 'Category');
          final details =
              '${row.id} ${row.name} ${row.allocated} '
                      '${row.remaining} ${row.price} ${row.type}'
                  .toLowerCase();
          return matchesFilter &&
              (_allocationSearchQuery.isEmpty ||
                  details.contains(_allocationSearchQuery));
        }).toList();
        if (rows.isEmpty)
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No items allocated to this branch yet.'),
          );
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('completed_sales')
              .where('branchId', isEqualTo: branchId)
              .snapshots(),
          builder: (context, salesSnapshot) {
            final selectedDay = _analyticsDate ?? DateTime.now();
            final soldByName = <String, int>{};
            for (final saleDoc in salesSnapshot.data?.docs ?? const []) {
              final sale = saleDoc.data();
              final soldAt = _dateValue(sale['timestamp']);
              if (soldAt.year != selectedDay.year ||
                  soldAt.month != selectedDay.month ||
                  soldAt.day != selectedDay.day) continue;
              for (final rawItem in sale['items'] as List<dynamic>? ?? const []) {
                if (rawItem is! Map) continue;
                final quantity = _parseInt(rawItem['quantity'], fallback: 1);
                // A category sale can use `name: Cookies`, while its actual
                // allocated product is stored as a variant/flavor.
                final keys = [
                  rawItem['name'],
                  rawItem['variant'],
                  rawItem['flavor'],
                  rawItem['productName'],
                  rawItem['itemName'],
                  rawItem['coffeeSize'],
                ].map((value) => value?.toString().trim() ?? '')
                    .where((value) => value.isNotEmpty);
                for (final key in keys) {
                  soldByName[key] = (soldByName[key] ?? 0) + quantity;
                }
              }
            }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBFC),
            border: Border.all(color: kAccent.withOpacity(0.8)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.48,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStatePropertyAll(
                        kPrimary.withOpacity(0.12),
                      ),
                      headingTextStyle: const TextStyle(
                        color: kBannerTop,
                        fontWeight: FontWeight.w900,
                      ),
                      dataTextStyle: const TextStyle(
                        color: Color(0xFF4A2634),
                        fontWeight: FontWeight.w600,
                      ),
                      columnSpacing: 28,
                      horizontalMargin: 18,
                      columns: [
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('Item name')),
                        if (showAllocationDetails) ...[
                          const DataColumn(label: Text('Allocated'), numeric: true),
                          const DataColumn(label: Text('Remaining'), numeric: true),
                        ] else
                          const DataColumn(label: Text('Sold'), numeric: true),
                        DataColumn(label: Text('Price'), numeric: true),
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: rows
                          .map(
                            (row) => DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 95,
                                    child: Text(
                                      row.id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 210,
                                    child: Text(
                                      row.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (showAllocationDetails) ...[
                                  DataCell(Text('${row.allocated}')),
                                  DataCell(Text('${row.remaining}')),
                                ] else
                                  DataCell(
                                    Text('${soldByName[row.name] ?? 0}'),
                                  ),
                                DataCell(
                                  Text('P${row.price.toStringAsFixed(2)}'),
                                ),
                                DataCell(_allocationTypeChip(row.type)),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit / add allocation',
                                        onPressed: () =>
                                            _showEditBranchAllocationDialog(
                                              row,
                                              branchId,
                                            ),
                                        icon: const Icon(Icons.edit_rounded),
                                        color: kDeep,
                                      ),
                                      IconButton(
                                        tooltip: 'Void allocation',
                                        onPressed: () =>
                                            _removeBranchAllocation(row),
                                        icon: const Icon(Icons.cancel_outlined),
                                        color: Colors.deepOrange.shade500,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
          },
        );
      },
    );
  }

  List<_AllocationTableRow> _allocationRowsForDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final type = data['isBundle'] == true
        ? 'Bundle'
        : data['isCoffee'] == true
        ? 'Coffee'
        : 'Category';
    if (data['isBundle'] == true ||
        data['isCoffee'] == true ||
        data['isAddon'] == true) {
      final remaining = data['isBundle'] == true
          ? _availableAssignedBundleCount(data)
          : _parseInt(data['stock']);
      final allocated = _parseInt(
        data['assignedStartingStock'],
        fallback: remaining,
      );
      return [
        _AllocationTableRow(
          documentId: doc.id,
          itemId: null,
          id:
              (data['bundleId'] ??
                      data['productId'] ??
                      data['sourceInventoryId'] ??
                      doc.id)
                  .toString(),
          name: data['name']?.toString() ?? 'Item',
          allocated: allocated,
          remaining: remaining,
          price: _parsePrice(
            data['price'] ?? data['basePrice'] ?? data['priceDelta'],
          ),
          type: data['isAddon'] == true ? 'Add-on' : type,
        ),
      ];
    }
    return (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where(
          (item) =>
              _parseInt(item['stock']) > 0 &&
              !_isExpiredInventoryItem(
                item['expirationDate']?.toString() ?? '',
              ),
        )
        .map((item) {
          final remaining = _parseInt(item['stock']);
          final allocated = _parseInt(
            item['assignedStartingStock'],
            fallback: _parseInt(item['startingStock'], fallback: remaining),
          );
          return _AllocationTableRow(
            documentId: doc.id,
            itemId: item['id']?.toString(),
            id: (item['id'] ?? doc.id).toString(),
            name: item['name']?.toString() ?? 'Item',
            allocated: allocated,
            remaining: remaining,
            price: _parsePrice(item['price']),
            type: type,
          );
        })
        .toList();
  }

  Widget _allocationTypeChip(String type) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: kPrimary.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      type,
      style: const TextStyle(
        color: kDeep,
        fontWeight: FontWeight.w800,
        fontSize: 11,
      ),
    ),
  );

  Future<void> _showEditBranchAllocationDialog(
    _AllocationTableRow row,
    String branchId,
  ) async {
    final nameController = TextEditingController(text: row.name);
    final priceController = TextEditingController(
      text: row.price.toStringAsFixed(2),
    );
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit allocation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Price'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'addStock'),
            icon: const Icon(Icons.add_box_rounded),
            label: const Text('Save & add stock'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final price = _parsePrice(priceController.text);
    nameController.dispose();
    priceController.dispose();
    if (action == null) return;
    if (name.isEmpty) {
      _showSnack('Item name is required', Colors.orange.shade700);
      return;
    }

    final ref = _firestore.collection('staff_inventory').doc(row.documentId);
    final priceField = row.type == 'Coffee'
        ? 'basePrice'
        : row.type == 'Add-on'
        ? 'priceDelta'
        : 'price';
    if (row.itemId == null) {
      await ref.update({
        'name': name,
        priceField: price,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final items = (snapshot.data()?['items'] as List<dynamic>? ?? [])
            .map((item) {
              if (item is! Map) return item;
              final updated = Map<String, dynamic>.from(item);
              if (updated['id']?.toString() != row.itemId) return updated;
              return {...updated, 'name': name, 'price': price};
            })
            .toList();
        transaction.update(ref, {
          'items': items,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    }
    if (!mounted) return;
    _showSnack('Allocation updated', Colors.green.shade600);
    if (action == 'addStock') {
      await _showAssignInventoryDialog(
        branchId,
        'Branch',
        isBranch: true,
      );
    }
  }

  Future<void> _removeBranchAllocation(_AllocationTableRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove allocation?'),
        content: Text('Remove "${row.name}" from this branch?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ref = _firestore.collection('staff_inventory').doc(row.documentId);
    if (row.itemId == null) {
      await ref.update({
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final items = (snapshot.data()?['items'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .where((item) => item['id']?.toString() != row.itemId)
            .toList();
        transaction.update(ref, {
          'items': items,
          'isDeleted': items.isEmpty,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    }
    if (mounted)
      _showSnack('${row.name} removed from branch', Colors.green.shade600);
  }

  Widget _buildBranchAllocationPanel({
    required String branchId,
    required String branchName,
    required TextEditingController controller,
    required List<String> staffIds,
    required bool enabled,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF5F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.payments_rounded, color: kDeep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cash Allocation',
                      style: TextStyle(
                        color: kBannerTop,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      branchName,
                      style: const TextStyle(
                        color: Color(0xFF777777),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: kDeep,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!enabled) ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Assign staff first before adding items or cash drawer.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kAccent.withOpacity(0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current allocation',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        enabled
                            ? '₱${(_currentAllocations[branchId] ?? 0).toStringAsFixed(2)}'
                            : 'Not assigned',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: enabled ? kBannerTop : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore
                      .collection('completed_sales')
                      .where('branchId', isEqualTo: branchId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    // Keep this in sync with the staff drawer: today's
                    // allocation/opening cash plus completed cash receipts.
                    final now = DateTime.now();
                    var cashBalance =
                        (_currentAllocations[branchId] ?? 0).toDouble();
                    for (final doc in snapshot.data?.docs ?? const []) {
                      final data = doc.data();
                      final timestamp = data['timestamp'];
                      final receiptDate = timestamp is Timestamp
                          ? timestamp.toDate()
                          : timestamp is DateTime
                          ? timestamp
                          : DateTime.tryParse(timestamp?.toString() ?? '');
                      if (receiptDate == null ||
                          receiptDate.year != now.year ||
                          receiptDate.month != now.month ||
                          receiptDate.day != now.day ||
                          data['paymentMode']?.toString().toLowerCase() !=
                              'cash') {
                        continue;
                      }
                      final delta = data['cashDrawerDelta'];
                      cashBalance += delta is num
                          ? delta.toDouble()
                          : ((data['paidAmount'] as num?)?.toDouble() ?? 0) -
                              ((data['change'] as num?)?.toDouble() ?? 0);
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kAccent.withOpacity(0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cash Drawer',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            enabled
                                ? '₱${cashBalance.toStringAsFixed(2)}'
                                : 'No drawer',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: enabled ? kPrimary : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Allocated Amount ',
              hintText: '0.00',
              prefixIcon: const Icon(Icons.payments_rounded, color: kDeep),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: kAccent.withOpacity(0.6)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: kAccent.withOpacity(0.6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kPrimary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (!enabled) {
                      _showSnack(
                        'Assign staff to this branch first.',
                        Colors.orange.shade700,
                      );
                      return;
                    }
                    final budgetText = controller.text.trim();
                    if (budgetText.isEmpty) {
                      _showSnack(
                        'Please enter an allocation amount',
                        Colors.orange.shade700,
                      );
                      return;
                    }
                    final budget = double.tryParse(budgetText);
                    if (budget == null || budget < 0) {
                      _showSnack(
                        'Invalid allocation amount',
                        Colors.red.shade600,
                      );
                      return;
                    }
                    _saveBudget(
                      branchId,
                      branchName,
                      budget,
                      isBranch: true,
                      replaceDailyOpening: true,
                    );
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Set Daily Cash'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kBannerTop,
                    side: const BorderSide(color: kBannerTop),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateBranchDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create Branch'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Branch name',
              hintText: 'SM Dagupan',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogContext, name);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final branchRef = _firestore.collection('branches').doc();
      await branchRef.set({
        'name': name,
        'branchCode': _branchCode(branchRef.id),
        'staffIds': <String>[],
        'staffNames': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnack('Branch created', Colors.green.shade600);
    } catch (e) {
      if (mounted) _showSnack('Error creating branch: $e', Colors.red.shade600);
    }
  }

  Future<void> _showEditBranchDialog(
    String branchId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Branch'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Branch name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogContext, name);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == currentName) return;
    try {
      await _firestore.collection('branches').doc(branchId).update({
        'name': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnack('Branch updated', Colors.green.shade600);
    } catch (e) {
      if (mounted) _showSnack('Error updating branch: $e', Colors.red.shade600);
    }
  }

  Future<void> _voidBranch(String branchId, String branchName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Void Branch?'),
          content: Text(
            'Move "$branchName" to Voided branches? You can restore it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Void'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await _firestore.collection('branches').doc(branchId).update({
        'isVoided': true,
        'voidedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      if (_selectedBranchId == branchId) {
        setState(() => _selectedBranchId = null);
      }
      _showSnack('Branch moved to Voided', Colors.orange.shade800);
    } catch (e) {
      if (mounted) _showSnack('Error voiding branch: $e', Colors.red.shade600);
    }
  }

  Future<void> _showVoidedBranchesDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFFFFF8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('branches')
                    .where('isVoided', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: kDeep),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Voided Branches',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: kBannerTop,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (docs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No voided branches.')),
                        )
                      else
                        ...docs.map((doc) {
                          final data = doc.data();
                          final name = data['name']?.toString() ?? 'Branch';
                          final branchCode = data['branchCode']
                              ?.toString()
                              .trim();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.store_mall_directory_rounded,
                                  color: Colors.orange.shade800,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          color: kBannerTop,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        'ID: ${branchCode?.isNotEmpty == true ? branchCode : _branchCode(doc.id)}',
                                        style: const TextStyle(
                                          color: Color(0xFF777777),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _restoreBranch(doc.id, name),
                                  icon: const Icon(
                                    Icons.restore_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('Restore'),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _restoreBranch(String branchId, String branchName) async {
    try {
      await _firestore.collection('branches').doc(branchId).update({
        'isVoided': false,
        'restoredAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _showSnack('$branchName restored', Colors.green.shade600);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error restoring branch: $e', Colors.red.shade600);
      }
    }
  }

  Future<void> _showAssignBranchStaffDialog(
    String branchId,
    String branchName,
  ) async {
    final branchDoc = await _firestore
        .collection('branches')
        .doc(branchId)
        .get();
    final selected =
        ((branchDoc.data()?['staffIds'] as List<dynamic>? ?? [])
                .map((id) => id.toString())
                .where((id) => id.trim().isNotEmpty))
            .toSet();
    final staffSnapshot = await _firestore
        .collection('staff_requests')
        .where('status', isEqualTo: 'accepted')
        .get();
    final staffDocs = staffSnapshot.docs.where((doc) {
      final data = doc.data();
      final role = (data['role'] as String?)?.toLowerCase() ?? '';
      return role != 'admin';
    }).toList();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var showAssigned = true;
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final assignedDocs = staffDocs.where((doc) {
              final data = doc.data();
              final id = (data['uid'] ?? data['userId'] ?? doc.id)
                  .toString()
                  .trim();
              return selected.contains(id);
            }).toList();
            // Keep staff assigned to another branch visible (and blocked) so
            // the admin immediately knows why they cannot be selected here.
            final availableDocs = staffDocs.where((doc) {
              final data = doc.data();
              final id = (data['uid'] ?? data['userId'] ?? doc.id)
                  .toString()
                  .trim();
              return !selected.contains(id);
            }).toList();
            final displayedDocs = (showAssigned ? assignedDocs : availableDocs)
                .where((doc) {
                  final data = doc.data();
                  final fullName =
                      '${data['firstName'] ?? ''} ${data['lastName'] ?? ''} ${data['email'] ?? ''} ${data['staffId'] ?? ''}'
                          .toLowerCase();
                  return fullName.contains(query);
                })
                .toList();
            return Dialog(
              backgroundColor: const Color(0xFFFFF8F3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 620,
                  maxHeight: 650,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: kPrimary.withOpacity(.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.groups_rounded,
                              color: kDeep,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Branch Staff',
                                  style: const TextStyle(
                                    color: kBannerTop,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  branchName,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded, color: kDeep),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _staffCountChip(
                            'Assigned',
                            assignedDocs.length,
                            kPrimary,
                          ),
                          const SizedBox(width: 8),
                          _staffCountChip(
                            'Available',
                            availableDocs.where((doc) {
                              final branchIds =
                                  (doc.data()['branchIds'] as List<dynamic>? ??
                                          [])
                                      .map((id) => id.toString());
                              return !branchIds.any((id) => id != branchId);
                            }).length,
                            const Color(0xFF188C68),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _staffTabButton(
                              'Assigned',
                              showAssigned,
                              () => setDialogState(() => showAssigned = true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _staffTabButton(
                              'Available',
                              !showAssigned,
                              () => setDialogState(() => showAssigned = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (value) => setDialogState(
                          () => query = value.trim().toLowerCase(),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search staff name or staff ID',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: kDeep,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: kAccent),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: kAccent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: displayedDocs.isEmpty
                            ? Center(
                                child: Text(
                                  showAssigned
                                      ? 'No staff assigned to this branch.'
                                      : 'No available staff found.',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : ListView.separated(
                                itemCount: displayedDocs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 7),
                                itemBuilder: (context, index) {
                                  final doc = displayedDocs[index];
                                  final data = doc.data();
                                  final staffId =
                                      (data['uid'] ?? data['userId'] ?? doc.id)
                                          .toString()
                                          .trim();
                                  final firstName =
                                      data['firstName']?.toString().trim() ??
                                      '';
                                  final lastName =
                                      data['lastName']?.toString().trim() ?? '';
                                  final fullName = '$firstName $lastName'
                                      .trim();
                                  final displayName = fullName.isEmpty
                                      ? data['email']?.toString() ?? staffId
                                      : fullName;
                                  final branchIds =
                                      (data['branchIds'] as List<dynamic>? ??
                                              [])
                                          .map((id) => id.toString())
                                          .toSet();
                                  final assignedElsewhere = branchIds.any(
                                    (id) => id != branchId,
                                  );
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: assignedElsewhere
                                          ? Colors.grey.shade100
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: assignedElsewhere
                                            ? Colors.grey.shade300
                                            : kAccent.withOpacity(.65),
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: selected.contains(staffId),
                                      onChanged:
                                          assignedElsewhere &&
                                              !selected.contains(staffId)
                                          ? null
                                          : (value) {
                                              setDialogState(() {
                                                if (value == true) {
                                                  selected.add(staffId);
                                                } else {
                                                  selected.remove(staffId);
                                                }
                                              });
                                            },
                                      title: Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        assignedElsewhere
                                            ? 'Already assigned to another branch — unavailable'
                                            : (data['staffId']?.toString() ??
                                                  staffId),
                                      ),
                                      activeColor: kPrimary,
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () async {
                            final selectedStaffDocs = staffDocs.where((doc) {
                              final data = doc.data();
                              final staffId =
                                  (data['uid'] ?? data['userId'] ?? doc.id)
                                      .toString()
                                      .trim();
                              return selected.contains(staffId);
                            }).toList();
                            final selectedNames = selectedStaffDocs.map((doc) {
                              final data = doc.data();
                              final firstName =
                                  data['firstName']?.toString().trim() ?? '';
                              final lastName =
                                  data['lastName']?.toString().trim() ?? '';
                              final fullName = '$firstName $lastName'.trim();
                              return fullName.isEmpty
                                  ? data['email']?.toString() ?? doc.id
                                  : fullName;
                            }).toList();

                            final batch = _firestore.batch();
                            batch.set(
                              _firestore.collection('branches').doc(branchId),
                              {
                                'staffIds': selected.toList(),
                                'staffNames': selectedNames,
                                'updatedAt': FieldValue.serverTimestamp(),
                              },
                              SetOptions(merge: true),
                            );
                            for (final doc in staffDocs) {
                              final data = doc.data();
                              final staffId =
                                  (data['uid'] ?? data['userId'] ?? doc.id)
                                      .toString()
                                      .trim();
                              batch.set(
                                _firestore
                                    .collection('staff_requests')
                                    .doc(staffId),
                                {
                                  // Only change this branch. Other existing
                                  // branch assignments must be preserved.
                                  'branchIds': selected.contains(staffId)
                                      ? FieldValue.arrayUnion([branchId])
                                      : FieldValue.arrayRemove([branchId]),
                                },
                                SetOptions(merge: true),
                              );
                            }
                            await batch.commit();
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext);
                            if (mounted) {
                              _showSnack(
                                'Branch staff updated',
                                Colors.green.shade600,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _staffCountChip(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withOpacity(.10),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      '$count $label',
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
    ),
  );
  Widget _staffTabButton(String label, bool selected, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? kPrimary : Colors.white,
          foregroundColor: selected ? Colors.white : kDeep,
          side: BorderSide(color: selected ? kPrimary : kAccent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label),
      );

  Widget _buildSelectedBranchHeader() {
    final branchId = _selectedBranchId!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('branches').doc(branchId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name = data?['name']?.toString() ?? 'Branch';
        final code = data?['branchCode']?.toString() ?? _branchCode(branchId);
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kBannerTop, kBannerMid, kBannerBot],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 42, 20, 22),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to branches',
                  onPressed: () => setState(() => _selectedBranchId = null),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.26)),
                  ),
                  child: const Icon(
                    Icons.store_mall_directory_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name Branch',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Branch ID: $code',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Staff',
                  icon: const Icon(Icons.groups_rounded, color: Colors.white),
                  onPressed: () => _showAssignBranchStaffDialog(branchId, name),
                ),
                IconButton(
                  tooltip: 'Reports',
                  icon: const Icon(Icons.assignment_rounded, color: Colors.white),
                  onPressed: () => _showBranchReportDetail(
                    branchId: branchId,
                    branchName: name,
                    staffIds: (data?['staffIds'] as List<dynamic>? ?? []).map((id) => id.toString()).toList(),
                    staffNames: (data?['staffNames'] as List<dynamic>? ?? []).map((name) => name.toString()).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kBannerTop, kBannerMid, kBannerBot],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            top: 30,
            right: 70,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            bottom: -10,
            left: -10,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon container
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resource Allocation',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Allocate & manage branch resources',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── BUDGET SUMMARY ──────────────────────────────────────────────
  Widget _buildBudgetSummary() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('branches').snapshots(),
      builder: (context, branchSnapshot) {
        final branchCount = branchSnapshot.data?.docs.length ?? 0;

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('staff_budget').snapshots(),
          builder: (context, budgetSnapshot) {
            double totalAllocated = 0;
            if (budgetSnapshot.hasData) {
              final branchIds = (branchSnapshot.data?.docs ?? [])
                  .map((doc) => doc.id)
                  .toSet();
              for (var doc in budgetSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final targetType =
                    data['targetType']?.toString().toLowerCase() ?? '';
                final branchId = data['branchId']?.toString() ?? doc.id;
                if (targetType != 'branch' && !branchIds.contains(branchId)) {
                  continue;
                }
                totalAllocated +=
                    (data['allocatedBudget'] as num?)?.toDouble() ?? 0;
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section label
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Budget Overview',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kBannerTop,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _showBudgetHistory,
                          style: TextButton.styleFrom(
                            foregroundColor: kPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: const Text(
                            'View History',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cards row
                  Row(
                    children: [
                      _buildSummaryCard(
                        label: 'Total Allocated',
                        value: '₱${totalAllocated.toStringAsFixed(2)}',
                        icon: Icons.account_balance_wallet_rounded,
                        gradientColors: const [
                          Color(0xFF1A8F7A),
                          Color(0xFF26C9AE),
                        ],
                        iconBg: const Color(0xFF26A69A),
                      ),
                      const SizedBox(width: 12),
                      _buildSummaryCard(
                        label: 'Total Branches',
                        value: branchCount.toString(),
                        icon: Icons.store_mall_directory_rounded,
                        gradientColors: const [
                          Color(0xFF3A4BAA),
                          Color(0xFF6A7FD4),
                        ],
                        iconBg: const Color(0xFF5C6BC0),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required List<Color> gradientColors,
    required Color iconBg,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 19),
                ),
                Icon(
                  Icons.trending_up_rounded,
                  color: Colors.white.withOpacity(0.5),
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.75),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── STAFF BUDGET LIST ───────────────────────────────────────────
  Widget _buildStaffBudgetList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('staff_requests').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(color: kPrimary, strokeWidth: 3),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final staffDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final role = (data['role'] as String?)?.toLowerCase() ?? '';
          final status = (data['status'] as String?)?.toLowerCase() ?? '';
          return role != 'admin' && status == 'accepted';
        }).toList();

        if (staffDocs.isEmpty) return _buildEmptyState();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section label
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Staff Budget Allocation',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kBannerTop,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: kPrimary.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        staffDocs.length == 1
                            ? '1 staff member'
                            : '${staffDocs.length} staff',
                        style: const TextStyle(
                          fontSize: 11,
                          color: kDeep,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: staffDocs.length,
                itemBuilder: (context, index) {
                  final staffDoc = staffDocs[index];
                  final staffData = staffDoc.data() as Map<String, dynamic>;
                  final staffId =
                      (staffData['uid'] ?? staffData['userId'] ?? staffDoc.id)
                          .toString()
                          .trim();
                  if (staffId.isEmpty) return const SizedBox.shrink();
                  final displayStaffId =
                      (staffData['staffId'] as String?)?.trim() ?? staffId;
                  final firstName =
                      (staffData['firstName'] as String?)?.trim() ?? '';
                  final lastName =
                      (staffData['lastName'] as String?)?.trim() ?? '';
                  final fullName = '$firstName $lastName'.trim();
                  final staffName = fullName.isEmpty
                      ? 'Staff Member'
                      : fullName;

                  if (!_budgetControllers.containsKey(staffId)) {
                    _budgetControllers[staffId] = TextEditingController();
                    _firestore
                        .collection('staff_budget')
                        .doc(staffId)
                        .get()
                        .then((doc) {
                          if (doc.exists && mounted) {
                            final budget =
                                (doc.data()?['allocatedBudget'] as num?)
                                    ?.toDouble() ??
                                0;
                            setState(() {
                              _currentAllocations[staffId] = budget;
                            });
                          }
                        });
                  }

                  return _buildStaffBudgetCard(
                    staffId: staffId,
                    displayStaffId: displayStaffId,
                    staffName: staffName,
                    controller: _budgetControllers[staffId]!,
                    index: index,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── STAFF CARD ──────────────────────────────────────────────────
  Widget _buildStaffBudgetCard({
    required String staffId,
    required String displayStaffId,
    required String staffName,
    required TextEditingController controller,
    required int index,
  }) {
    // Generate initials
    final parts = staffName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : staffName.isNotEmpty
        ? staffName[0].toUpperCase()
        : 'S';

    // Cycle avatar bg colors
    final avatarColors = [
      [const Color(0xFFE91E63), const Color(0xFF8B0038)],
      [const Color(0xFF5C6BC0), const Color(0xFF3A4BAA)],
      [const Color(0xFF26A69A), const Color(0xFF1A7A6E)],
      [const Color(0xFFF57C00), const Color(0xFFBF5000)],
    ];
    final colorPair = avatarColors[index % avatarColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Top: staff info ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF5F7),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(color: kAccent.withOpacity(0.4), width: 1),
              ),
            ),
            child: Row(
              children: [
                // Avatar with initials
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colorPair,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colorPair[0].withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staffName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kBannerTop,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: $displayStaffId',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  _showReportDetail(staffId, staffName),
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [kPrimary, kDeep],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimary.withOpacity(0.18),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'View Report',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showAssignInventoryDialog(
                                staffId,
                                staffName,
                              ),
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: kAccent),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_rounded,
                                      size: 15,
                                      color: kDeep,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Assign',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: kDeep,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Staff tag
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F2F5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: kAccent.withOpacity(0.45),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current allocation',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9E9E9E),
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₱${(_currentAllocations[staffId] ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kBannerTop,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: _firestore
                            .collection('staff_cash_drawer')
                            .doc(staffId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          double cashBalance = 0;
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>;
                            cashBalance =
                                (data['balance'] as num?)?.toDouble() ?? 0;
                          }
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE7F1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: kPrimary.withOpacity(0.22),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Cash Drawer',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF9E9E9E),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      elevation: 2,
                                      shadowColor: Colors.black.withOpacity(
                                        0.08,
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () =>
                                            _confirmResetStaffCashDrawer(
                                              staffId,
                                            ),
                                        child: const SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: Center(
                                            child: Icon(
                                              Icons.refresh_rounded,
                                              size: 18,
                                              color: kPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '₱${cashBalance.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: kPrimary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'This is the assigned budget for the staff. The cash drawer displays the current amount of cash they hold',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                    height: 1.4,
                  ),
                ),
                if ((_currentAllocations[staffId] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Saved',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kPrimary.withOpacity(0.85),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _buildAssignedInventorySummary(staffId),
              ],
            ),
          ),

          // ── Bottom: input + button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Input label
                const Text(
                  'Allocated Budget',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9E9E9E),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),

                // Input field
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kBannerTop,
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(10),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          '₱',
                          style: TextStyle(
                            color: kDeep,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAF0F3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: kAccent.withOpacity(0.5),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: kPrimary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Save button
                GestureDetector(
                  onTap: () {
                    final budgetText = controller.text.trim();
                    if (budgetText.isEmpty) {
                      _showSnack(
                        'Please enter a budget amount',
                        Colors.orange.shade700,
                      );
                      return;
                    }
                    try {
                      final budget = double.parse(budgetText);
                      if (budget < 0) {
                        _showSnack(
                          'Budget cannot be negative',
                          Colors.red.shade600,
                        );
                        return;
                      }
                      _saveBudget(staffId, staffName, budget);
                    } catch (_) {
                      _showSnack('Invalid budget amount', Colors.red.shade600);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kBannerTop, kBannerMid, kPrimary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimary.withOpacity(0.40),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Add Cash',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    final budgetText = controller.text.trim();
                    if (budgetText.isEmpty) {
                      _showSnack(
                        'Please enter a budget amount',
                        Colors.orange.shade700,
                      );
                      return;
                    }
                    try {
                      final budget = double.parse(budgetText);
                      if (budget < 0) {
                        _showSnack(
                          'Budget cannot be negative',
                          Colors.red.shade600,
                        );
                        return;
                      }
                      _saveBudget(
                        staffId,
                        staffName,
                        budget,
                        replaceDailyOpening: true,
                      );
                    } catch (_) {
                      _showSnack('Invalid budget amount', Colors.red.shade600);
                    }
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Set Daily Cash'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kBannerTop,
                    side: const BorderSide(color: kBannerTop),
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY STATE ─────────────────────────────────────────────────
  Widget _buildAssignedInventorySummary(String staffId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('staff_inventory')
          .where('staffId', isEqualTo: staffId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        final assignedDocs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data();
          if (data['isDeleted'] == true) return false;
          if (data['isBundle'] == true) {
            return !_hasExpiredAssignedBundleItem(data) &&
                _availableAssignedBundleCount(data) > 0;
          }
          final activeItems = ((data['items'] as List<dynamic>?) ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) {
                final stock = item.containsKey('stock')
                    ? _parseInt(item['stock'])
                    : _parseInt(item['startingStock']);
                return stock > 0 &&
                    !_isExpiredInventoryItem(
                      item['expirationDate']?.toString() ?? '',
                    );
              })
              .toList();
          return data['isCoffee'] == true ||
              data['isAddon'] == true ||
              activeItems.isNotEmpty;
        }).toList();
        final totals = _staffInventoryTotals(assignedDocs);
        final starting = totals['starting'] ?? 0;
        final remaining = totals['remaining'] ?? 0;
        final reduced = totals['reduced'] ?? 0;
        final used = (starting - remaining - reduced).clamp(0, starting);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAccent.withOpacity(0.65), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: kDeep,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assigned Stock',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9E9E9E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reduced > 0
                              ? '$starting given - $remaining remaining - $used used - $reduced reduced'
                              : '$starting given - $remaining remaining - $used used',
                          style: const TextStyle(
                            color: kBannerTop,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (assignedDocs.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...assignedDocs.take(3).map((doc) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _assignedInventoryLabel(doc.data()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kBannerTop.withOpacity(0.82),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }),
                if (assignedDocs.length > 3)
                  Text(
                    '+${assignedDocs.length - 3} more assigned',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final firstDoc = assignedDocs.first.data();
                      _showAssignedInventoryDialog(
                        staffId,
                        firstDoc['staffName']?.toString() ?? 'Staff',
                      );
                    },
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: const Text('View all item'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kDeep,
                      side: BorderSide(color: kAccent.withOpacity(0.9)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 38,
                color: kPrimary.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No staff members found',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Staff will appear here once added',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}
