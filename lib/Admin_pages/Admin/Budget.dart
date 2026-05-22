import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

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

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
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
  final _currentAllocations = <String, double>{};
  final _firestore = FirebaseFirestore.instance;
  String _branchSearchQuery = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
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
    _budgetControllers.clear();
    _currentAllocations.clear();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveBudget(
    String targetId,
    String targetName,
    double budget, {
    bool isBranch = false,
  }) async {
    if (targetId.trim().isEmpty) {
      _showSnack('Missing target ID', Colors.red.shade600);
      return;
    }
    try {
      final now = DateTime.now();
      final budgetRef = _firestore.collection('staff_budget').doc(targetId);
      final existingBudgetSnapshot = await budgetRef.get();
      final previousAllocation = existingBudgetSnapshot.exists
          ? (existingBudgetSnapshot.data()?['allocatedBudget'] as num?)
                    ?.toDouble() ??
                0.0
          : 0.0;
      final newAllocation = previousAllocation + budget;

      // Update current allocation total
      await budgetRef.set({
        'staffId': targetId,
        'staffName': targetName,
        if (isBranch) 'branchId': targetId,
        if (isBranch) 'branchName': targetName,
        'targetType': isBranch ? 'branch' : 'staff',
        'allocatedBudget': newAllocation,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // Add the additional budget amount to the cash drawer balance
      final cashDrawerRef = _firestore
          .collection('staff_cash_drawer')
          .doc(targetId);
      await _firestore.runTransaction((transaction) async {
        final cashDrawerSnapshot = await transaction.get(cashDrawerRef);
        final currentBalance = cashDrawerSnapshot.exists
            ? (cashDrawerSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        transaction.set(cashDrawerRef, {
          'balance': currentBalance + budget,
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
        'type': 'allocation',
      });

      if (!mounted) return;
      setState(() {
        _currentAllocations[targetId] = newAllocation;
        _budgetControllers[targetId]?.clear();
      });
      _showSnack('Budget updated for $targetName', Colors.green.shade600);
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

  int _stockForAssignableItem(Map<String, dynamic> item) {
    return item.containsKey('stock')
        ? _parseInt(item['stock'])
        : _parseInt(item['startingStock']);
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
          if (item is! Map<String, dynamic>) return false;
          final expirationDate = item['expirationDate']?.toString() ?? '';
          return !_isExpiredInventoryItem(expirationDate) &&
              !_isRemovedVariant(item, removedItems) &&
              _stockForAssignableItem(item) > 0;
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

  Widget _buildAssignedInventoryPreview(String staffId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('staff_inventory')
          .where('staffId', isEqualTo: staffId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => doc.data()['isDeleted'] != true)
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
                      final docs = (snapshot.data?.docs ?? [])
                          .where((doc) => doc.data()['isDeleted'] != true)
                          .toList();

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

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: kAccent),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    data['isBundle'] == true
                                        ? Icons.inventory_2_rounded
                                        : Icons.category_rounded,
                                    color: kDeep,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _assignedInventoryLabel(data),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: kBannerTop,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
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
                  maxHeight: MediaQuery.of(context).size.height * 0.82,
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
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
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
                          ]),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: kPrimary,
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text('Error loading inventory'),
                              );
                            }

                            final inventorySnapshot = snapshot.data?[0];
                            final coffeeSnapshot = snapshot.data?[1];
                            final addonSnapshot = snapshot.data?[2];
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
                                            !showCategories && !showCoffee,
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
                                                        _stockForAssignableItem(
                                                          item,
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
    final selected = quantities.entries.where((entry) => entry.value > 0);
    if (selected.isEmpty && coffeeProductIds.isEmpty && addonIds.isEmpty) {
      _showSnack(
        'Select coffee, add-ons, or enter at least one quantity',
        Colors.orange.shade700,
      );
      return;
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
          final stock = rawItem.containsKey('stock')
              ? _parseInt(rawItem['stock'])
              : _parseInt(rawItem['startingStock']);
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
        if (collection == 'admin_notifications' && reportType != 'report')
          continue;
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
        allDocs['${doc.reference.path}:${doc.id}'] = doc;
      }
    }

    for (final staffName in staffNames) {
      final docs = await _loadReportDocs('', staffName);
      for (final doc in docs) {
        allDocs['${doc.reference.path}:${doc.id}'] = doc;
      }
    }

    Future<void> collectBranchReports(Query<Map<String, dynamic>> query) async {
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        allDocs['${doc.reference.path}:${doc.id}'] = doc;
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

  void _showBranchReportDetail({
    required String branchId,
    required String branchName,
    required List<String> staffIds,
    required List<String> staffNames,
  }) {
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
                future: _loadBranchReportDocs(
                  branchId: branchId,
                  staffIds: staffIds,
                  staffNames: staffNames,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: kPrimary),
                    );
                  }

                  final reportDocs = snapshot.data ?? [];
                  if (snapshot.hasError || reportDocs.isEmpty) {
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
                                : '$branchName has no staff reports yet',
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
                            const SizedBox(height: 18),
                            Column(
                              children: reportDocs.map((doc) {
                                final data = doc.data();
                                final staffId =
                                    data['staffId']?.toString() ?? '';
                                final staffName =
                                    data['staffName']?.toString() ?? 'Staff';
                                return _buildReportCard(
                                  doc,
                                  staffId,
                                  staffName,
                                );
                              }).toList(),
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

  Widget _buildReportCard(
    QueryDocumentSnapshot<Map<String, dynamic>> reportDoc,
    String staffId,
    String staffName,
  ) {
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
    final totalSales = data['totalSales'];
    final transactionCount = data['transactionCount'];
    final transactions = data['transactions'] as List<dynamic>?;
    final staffPublicId = data['staffPublicId']?.toString().trim() ?? '';
    final displayStaffId = staffPublicId.isNotEmpty ? staffPublicId : staffId;
    final closingInventory =
        (data['closingInventory'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final reportDay = _reportDayFromData(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
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
                      createdAt.toDate().toLocal().toString().split('.').first,
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
                        '${transactionCount?.toString() ?? '0'}',
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
            const SizedBox(height: 16),
            const Text(
              'Transaction Details',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kBannerTop,
              ),
            ),
            const SizedBox(height: 10),
            ...transactions.map((transaction) {
              final tx = transaction as Map<String, dynamic>;
              final salesId = tx['salesId']?.toString() ?? 'Unknown';
              final transactionTotal = tx['total'] is num
                  ? (tx['total'] as num).toDouble()
                  : double.tryParse(tx['total']?.toString() ?? '') ?? 0.0;

              return FutureBuilder<Map<String, dynamic>>(
                future: _loadTransactionDetails(tx),
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  final items = details == null
                      ? null
                      : (details['items'] as List<Map<String, dynamic>>?) ?? [];
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                item['name']?.toString().isNotEmpty == true
                                ? item['name'].toString()
                                : 'Product';
                            final variant = item['variant']?.toString() ?? '';
                            final category = item['category']?.toString() ?? '';
                            final title = variant.isNotEmpty
                                ? '$itemName • $variant'
                                : itemName;
                            final qty = item['quantity'] is num
                                ? (item['quantity'] as num).toInt()
                                : int.tryParse(
                                        item['quantity']?.toString() ?? '',
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                          }).toList(),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            }).toList(),
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
            }).toList(),
          ],
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _loadRefundDetails(staffId, reportDay),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text(
                  'Loading refund records...',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                );
              }

              if (snapshot.hasError) {
                return const Text(
                  'Unable to load refund records.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
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
                    final salesId = refund['salesId']?.toString() ?? 'Refund';
                    final reason = refund['reason']?.toString() ?? 'No reason';
                    final source = refund['source']?.toString() ?? '';
                    final total = _parseMoney(refund['total']).abs();
                    final delta = _parseMoney(refund['cashDrawerDelta']).abs();
                    final subtotal = _parseMoney(refund['subtotal']).abs();
                    final amount = total > 0
                        ? total
                        : delta > 0
                        ? delta
                        : subtotal;
                    final items = refund['items'] as List<dynamic>? ?? [];
                    final itemCount = items.fold<int>(
                      0,
                      (sum, item) =>
                          item is Map ? sum + _parseQty(item['quantity']) : sum,
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  }).toList(),
                ],
              );
            },
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
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    _buildBudgetSummary(),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedBudgetHeaderDelegate(
                  minHeight: 142,
                  maxHeight: 142,
                  child: _buildPinnedBudgetControls(),
                ),
              ),
              SliverToBoxAdapter(child: _buildBranchManagementSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
          final branchCount = snapshot.data?.docs.length ?? 0;
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
  Widget _buildBranchManagementSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('branches').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          final branches = snapshot.data?.docs ?? [];
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
              else
                ...visibleBranches.map((doc) {
                  final data = doc.data();
                  final name = data['name']?.toString() ?? 'Branch';
                  final staffNames =
                      (data['staffNames'] as List<dynamic>? ?? [])
                          .map((name) => name.toString())
                          .where((name) => name.trim().isNotEmpty)
                          .toList();
                  final staffIds = (data['staffIds'] as List<dynamic>? ?? [])
                      .map((id) => id.toString().trim())
                      .where((id) => id.isNotEmpty)
                      .toList();
                  final hasAssignedStaff = staffIds.isNotEmpty;
                  final branchId = doc.id;
                  if (!_budgetControllers.containsKey(branchId)) {
                    _budgetControllers[branchId] = TextEditingController();
                    _firestore
                        .collection('staff_budget')
                        .doc(branchId)
                        .get()
                        .then((budgetDoc) {
                          if (!budgetDoc.exists || !mounted) return;
                          final budget =
                              (budgetDoc.data()?['allocatedBudget'] as num?)
                                  ?.toDouble() ??
                              0;
                          setState(() {
                            _currentAllocations[branchId] = budget;
                          });
                        });
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kAccent.withOpacity(0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimary.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
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
                                  Text(
                                    staffNames.isEmpty
                                        ? 'No staff assigned'
                                        : staffNames.join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
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
                              tooltip: 'Delete branch',
                              onPressed: () => _deleteBranch(branchId, name),
                              icon: const Icon(Icons.delete_outline_rounded),
                              color: Colors.red,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _showAssignBranchStaffDialog(
                                  branchId,
                                  name,
                                ),
                                icon: const Icon(Icons.group_add_rounded),
                                label: const Text('Staff'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kDeep,
                                  side: BorderSide(color: kAccent),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: hasAssignedStaff
                                    ? () => _showAssignInventoryDialog(
                                        branchId,
                                        name,
                                        isBranch: true,
                                      )
                                    : null,
                                icon: const Icon(Icons.inventory_2_rounded),
                                label: const Text('Items'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: hasAssignedStaff
                                ? () => _showBranchReportDetail(
                                    branchId: branchId,
                                    branchName: name,
                                    staffIds: staffIds,
                                    staffNames: staffNames,
                                  )
                                : null,
                            icon: const Icon(Icons.assignment_rounded),
                            label: const Text('View Report'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kDeep,
                              side: BorderSide(color: kAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildAssignedInventorySummary(branchId),
                        const SizedBox(height: 12),
                        _buildBranchAllocationPanel(
                          branchId: branchId,
                          branchName: name,
                          controller: _budgetControllers[branchId]!,
                          enabled: hasAssignedStaff,
                        ),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBranchAllocationPanel({
    required String branchId,
    required String branchName,
    required TextEditingController controller,
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
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('staff_cash_drawer')
                      .doc(branchId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    double cashBalance = 0;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      cashBalance = (data['balance'] as num?)?.toDouble() ?? 0;
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
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
                  _showSnack('Invalid allocation amount', Colors.red.shade600);
                  return;
                }
                _saveBudget(branchId, branchName, budget, isBranch: true);
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send Allocation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBannerTop,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
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
      await _firestore.collection('branches').add({
        'name': name,
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

  Future<void> _deleteBranch(String branchId, String branchName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Branch?'),
          content: Text(
            'Delete "$branchName"? This removes the branch from staff assignments.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      final staffSnapshot = await _firestore
          .collection('staff_requests')
          .where('branchIds', arrayContains: branchId)
          .get();
      final inventorySnapshot = await _firestore
          .collection('staff_inventory')
          .where('staffId', isEqualTo: branchId)
          .get();
      final batch = _firestore.batch();
      for (final staffDoc in staffSnapshot.docs) {
        batch.update(staffDoc.reference, {
          'branchIds': FieldValue.arrayRemove([branchId]),
        });
      }
      for (final inventoryDoc in inventorySnapshot.docs) {
        batch.delete(inventoryDoc.reference);
      }
      batch.delete(_firestore.collection('branches').doc(branchId));
      batch.delete(_firestore.collection('staff_budget').doc(branchId));
      batch.delete(_firestore.collection('staff_cash_drawer').doc(branchId));
      await batch.commit();
      if (!mounted) return;
      _budgetControllers.remove(branchId)?.dispose();
      setState(() => _currentAllocations.remove(branchId));
      _showSnack('Branch deleted', Colors.green.shade600);
    } catch (e) {
      if (mounted) _showSnack('Error deleting branch: $e', Colors.red.shade600);
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Assign Staff to $branchName'),
              content: SizedBox(
                width: double.maxFinite,
                child: staffDocs.isEmpty
                    ? const Text('No accepted staff available.')
                    : ListView(
                        shrinkWrap: true,
                        children: staffDocs.map((doc) {
                          final data = doc.data();
                          final staffId =
                              (data['uid'] ?? data['userId'] ?? doc.id)
                                  .toString()
                                  .trim();
                          final firstName =
                              data['firstName']?.toString().trim() ?? '';
                          final lastName =
                              data['lastName']?.toString().trim() ?? '';
                          final fullName = '$firstName $lastName'.trim();
                          final displayName = fullName.isEmpty
                              ? data['email']?.toString() ?? staffId
                              : fullName;
                          return CheckboxListTile(
                            value: selected.contains(staffId),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selected.add(staffId);
                                } else {
                                  selected.remove(staffId);
                                }
                              });
                            },
                            title: Text(displayName),
                            subtitle: Text(
                              data['staffId']?.toString() ?? staffId,
                            ),
                            activeColor: kPrimary,
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final selectedStaffDocs = staffDocs.where((doc) {
                      final data = doc.data();
                      final staffId = (data['uid'] ?? data['userId'] ?? doc.id)
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
                      final staffId = (data['uid'] ?? data['userId'] ?? doc.id)
                          .toString()
                          .trim();
                      batch.set(
                        _firestore.collection('staff_requests').doc(staffId),
                        {
                          'branchIds': selected.contains(staffId)
                              ? FieldValue.arrayUnion([branchId])
                              : FieldValue.arrayRemove([branchId]),
                        },
                        SetOptions(merge: true),
                      );
                    }
                    await batch.commit();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) {
                      _showSnack('Branch staff updated', Colors.green.shade600);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
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
                          'Save Allocation',
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

        final totals = _staffInventoryTotals(snapshot.data?.docs ?? []);
        final starting = totals['starting'] ?? 0;
        final remaining = totals['remaining'] ?? 0;
        final reduced = totals['reduced'] ?? 0;
        final used = (starting - remaining - reduced).clamp(0, starting);
        final assignedDocs = (snapshot.data?.docs ?? [])
            .where((doc) => doc.data()['isDeleted'] != true)
            .toList();

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
                          'Assigned Starting Stock',
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
