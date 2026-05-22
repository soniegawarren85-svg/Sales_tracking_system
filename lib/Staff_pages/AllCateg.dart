import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/inventory_service.dart';

class AllCategPage extends StatefulWidget {
  final String? selectedCategoryName;
  final String? selectedSourceInventoryId;
  final bool selectedIsBundle;
  final bool selectedIsCoffee;

  const AllCategPage({
    super.key,
    this.selectedCategoryName,
    this.selectedSourceInventoryId,
    this.selectedIsBundle = false,
    this.selectedIsCoffee = false,
  });

  @override
  State<AllCategPage> createState() => _AllCategPageState();
}

class _AllCategPageState extends State<AllCategPage>
    with TickerProviderStateMixin {
  late AnimationController _headerAnimController;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;
  bool _showCategories = true;
  bool _showCoffee = false;
  List<String> _staffInventoryIds = const [];

  bool get _isFilteredCategory =>
      (widget.selectedCategoryName?.trim().isNotEmpty ?? false) ||
      (widget.selectedSourceInventoryId?.trim().isNotEmpty ?? false);

  bool get _isCoffeeView => widget.selectedIsCoffee;

  @override
  void initState() {
    super.initState();
    _showCoffee = widget.selectedIsCoffee;
    _showCategories = !widget.selectedIsBundle && !widget.selectedIsCoffee;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if ((uid ?? '').isNotEmpty) {
      _staffInventoryIds = const [];
      _loadStaffInventoryIds(uid!);
    }
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFadeAnim = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOut,
    );
    _headerSlideAnim =
        Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
        );
    _headerAnimController.forward();
  }

  Future<void> _loadStaffInventoryIds(String uid) async {
    final ids = <String>{};
    try {
      final doc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get();
      final data = doc.data();
      final publicStaffId = data?['staffId']?.toString().trim() ?? '';
      final branchIds = (data?['branchIds'] as List<dynamic>? ?? [])
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty);
      ids.addAll(branchIds);
      final byUid = await FirebaseFirestore.instance
          .collection('branches')
          .where('staffIds', arrayContains: uid)
          .get();
      ids.addAll(byUid.docs.map((doc) => doc.id));
      if (publicStaffId.isNotEmpty) {
        final byPublicId = await FirebaseFirestore.instance
            .collection('branches')
            .where('staffIds', arrayContains: publicStaffId)
            .get();
        ids.addAll(byPublicId.docs.map((doc) => doc.id));
      }
    } catch (_) {}

    if (mounted) setState(() => _staffInventoryIds = ids.toList());
  }

  Stream<QuerySnapshot> _staffInventoryStream() {
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    final query = FirebaseFirestore.instance.collection('staff_inventory');
    if (ids.isEmpty) {
      return query.where('staffId', isEqualTo: '').snapshots();
    }
    return ids.length == 1
        ? query.where('staffId', isEqualTo: ids.first).snapshots()
        : query.where('staffId', whereIn: ids).snapshots();
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    super.dispose();
  }

  int _stockForItem(Map<String, dynamic> item) {
    final itemName = item['name']?.toString() ?? '';
    final itemVariant = item['variant']?.toString() ?? '';
    final hasStockField = item.containsKey('stock') && item['stock'] != null;
    final stockValue = item['stock'] is num
        ? (item['stock'] as num).toInt()
        : int.tryParse(item['stock']?.toString() ?? '') ?? 0;

    if (hasStockField) return stockValue;

    final startingValue = item['startingStock'] is num
        ? (item['startingStock'] as num).toInt()
        : int.tryParse(item['startingStock']?.toString() ?? '') ?? 0;

    if (startingValue > 0) return startingValue;

    final entry = InventoryService().getEntryForItemToday(itemName);
    if (entry != null) {
      for (final savedItem in entry.safeItems) {
        final savedName = savedItem['name']?.toString() ?? '';
        final savedVariant = savedItem['variant']?.toString() ?? '';
        if (savedName == itemName && savedVariant == itemVariant) {
          return savedItem['quantity'] is int
              ? savedItem['quantity'] as int
              : int.tryParse(savedItem['quantity']?.toString() ?? '') ?? 0;
        }
      }
      final totalStarting =
          entry.safeStartingA + entry.safeStartingB + entry.safeStartingC;
      if (totalStarting > 0) return totalStarting;
    }
    return 0;
  }

  Color _stockColor(int stock) {
    if (stock == 0) return const Color(0xFFE53935);
    if (stock <= 5) return const Color(0xFFF57C00);
    return const Color(0xFF2E7D32);
  }

  double _parsePrice(dynamic value) {
    if (value is num) return value.toDouble();
    final text = value?.toString() ?? '';
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<Map<String, dynamic>> _coffeeItemsFromData(Map<String, dynamic> data) {
    final basePrice = _parsePrice(data['basePrice']);
    final sizes = (data['sizes'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((size) => Map<String, dynamic>.from(size))
        .where((size) => (size['name']?.toString().trim() ?? '').isNotEmpty)
        .toList();
    final coffeeSizes = sizes.isEmpty
        ? [
            {'name': 'Regular', 'priceDelta': 0},
          ]
        : sizes;

    final addonByName = <String, Map<String, dynamic>>{};
    for (final addon
        in (data['addonOptions'] as List<dynamic>? ?? []).whereType<Map>()) {
      final name = addon['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      addonByName.putIfAbsent(name, () => Map<String, dynamic>.from(addon));
    }

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < coffeeSizes.length; i++) {
      final size = coffeeSizes[i];
      final sizeName = size['name']?.toString().trim() ?? 'Regular';
      final sizeDelta = _parsePrice(size['priceDelta']);
      final price = basePrice + sizeDelta;
      items.add({
        'name': sizeName,
        'variant': sizeName,
        'price': price,
        'sizePriceDelta': sizeDelta,
        'addons': addonByName.values.toList(),
        'isCoffee': true,
        'variantSlot': i,
      });
    }
    return items;
  }

  Future<void> _markCoffeeLowStock(Map<String, dynamic> coffee) async {
    final staffDocId = coffee['sourceDocId']?.toString() ?? '';
    final flavor =
        coffee['categoryName']?.toString() ??
        coffee['name']?.toString() ??
        'Coffee flavor';
    if (staffDocId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('staff_inventory')
          .doc(staffDocId)
          .set({
            'isLowStock': true,
            'lowStockMarkedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await FirebaseFirestore.instance.collection('admin_notifications').add({
        'type': 'coffee_low_stock',
        'title': 'Coffee flavor is running low',
        'message': '$flavor is marked as running low.',
        'itemName': flavor,
        'staffInventoryDocId': staffDocId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(_buildSnackBar('$flavor marked as running low'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnackBar('Failed to mark coffee low: $e', isError: true),
      );
    }
  }

  String _bundleInstanceId(String bundleId, int index) {
    final suffix = (index + 1).toString().padLeft(3, '0');
    return bundleId.isEmpty ? 'Bundle-$suffix' : '$bundleId-$suffix';
  }

  List<Map<String, dynamic>> _bundleInstancesFromData(
    Map<String, dynamic> bundleData,
  ) {
    final savedInstances = bundleData['bundleInstances'];
    if (savedInstances is List && savedInstances.isNotEmpty) {
      return savedInstances
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }

    final bundleCount = _parseInt(bundleData['bundleCount']);
    final bundleId = bundleData['bundleId']?.toString() ?? '';
    final items = bundleData['items'] as List<dynamic>? ?? [];

    return List.generate(bundleCount, (index) {
      return {
        'number': index + 1,
        'id': _bundleInstanceId(bundleId, index),
        'status': 'available',
        'items': items.map((item) {
          if (item is! Map<String, dynamic>) return <String, dynamic>{};
          final quantity = _parseInt(item['quantity'], fallback: 1);
          return {
            'name': item['name']?.toString() ?? 'Item',
            'price': item['price']?.toString() ?? '0',
            'quantity': quantity,
            'remaining': quantity,
          };
        }).toList(),
      };
    });
  }

  int _bundleStockForData(Map<String, dynamic> bundleData) {
    final bundleCount = _parseInt(bundleData['bundleCount']);
    if (bundleData.containsKey('bundleCount')) return bundleCount;
    final instances = _bundleInstancesFromData(bundleData);
    final availableInstances = instances.where((instance) {
      final status = instance['status']?.toString() ?? 'available';
      return status == 'available';
    }).length;
    return bundleCount > availableInstances ? bundleCount : availableInstances;
  }

  String _bundleStatusLabel(String status) {
    if (status == 'inCategory') return 'In category';
    if (status == 'sold') return 'Sold';
    if (status == 'reduced') return 'Reduced';
    return 'Available';
  }

  bool _isExpiredItem(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.isBefore(
        DateTime(today.year, today.month, today.day + 1),
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> _showStockAdjustmentDialog({
    required String categoryName,
    required String sourceDocId,
    required Map<String, dynamic> item,
    required int currentStock,
  }) async {
    final qtyController = TextEditingController();
    final commentController = TextEditingController();
    String? selectedReason;
    final reasonOptions = [
      'Damaged',
      'Dropped',
      'Expired',
      'Contaminated',
      'Other',
    ];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC2105C).withOpacity(0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dialog Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.remove_circle_outline_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Reduce Stock',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Dialog Body
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Item info chip row
                            Row(
                              children: [
                                _InfoChip(
                                  icon: Icons.label_outline_rounded,
                                  label: item['name']?.toString() ?? '',
                                  color: const Color(0xFFC2105C),
                                ),
                                if ((item['variant']?.toString() ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _InfoChip(
                                    icon: Icons.tune_rounded,
                                    label: item['variant']?.toString() ?? '',
                                    color: const Color(0xFFAD1457),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCE4EC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 16,
                                    color: Color(0xFFC2105C),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Current Stock: $currentStock',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFC2105C),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _PinkTextField(
                              controller: qtyController,
                              label: 'Quantity to reduce',
                              hint: 'Enter quantity',
                              icon: Icons.remove_circle_outline,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 14),
                            // Styled Dropdown
                            DropdownButtonFormField<String>(
                              value: selectedReason,
                              decoration: InputDecoration(
                                labelText: 'Reason',
                                labelStyle: const TextStyle(
                                  color: Color(0xFFC2105C),
                                ),
                                prefixIcon: const Icon(
                                  Icons.flag_outlined,
                                  color: Color(0xFFC2105C),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFF8BBD0),
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFC2105C),
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFFFF0F5),
                              ),
                              dropdownColor: Colors.white,
                              items: reasonOptions.map((reason) {
                                return DropdownMenuItem<String>(
                                  value: reason,
                                  child: Text(reason),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => selectedReason = value);
                              },
                            ),
                            const SizedBox(height: 14),
                            _PinkTextField(
                              controller: commentController,
                              label: 'Comment (optional)',
                              hint: 'Add a note...',
                              icon: Icons.notes_rounded,
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC2105C),
                                side: const BorderSide(
                                  color: Color(0xFFF8BBD0),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final quantity =
                                    int.tryParse(qtyController.text.trim()) ??
                                    0;
                                final reason = selectedReason?.trim() ?? '';
                                final comment = commentController.text.trim();

                                if (quantity <= 0 || quantity > currentStock) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    _buildSnackBar(
                                      'Enter a valid reduction quantity',
                                      isError: true,
                                    ),
                                  );
                                  return;
                                }
                                if (reason.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    _buildSnackBar(
                                      'Please select a reason',
                                      isError: true,
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  final docRef = FirebaseFirestore.instance
                                      .collection('staff_inventory')
                                      .doc(sourceDocId);
                                  final snapshot = await docRef.get();
                                  final data = snapshot.data();
                                  final items =
                                      (data?['items'] as List?)
                                          ?.cast<Map<String, dynamic>>() ??
                                      [];
                                  final unitPrice = _parsePrice(item['price']);
                                  double reductionAmount = 0.0;
                                  final updatedItems = items.map((entry) {
                                    final entryName =
                                        entry['name']?.toString() ?? '';
                                    final entryVariant =
                                        entry['variant']?.toString() ?? '';
                                    final entryId =
                                        entry['id']?.toString() ?? '';
                                    final itemName =
                                        item['name']?.toString() ?? '';
                                    final itemVariant =
                                        item['variant']?.toString() ?? '';
                                    final itemId = item['id']?.toString() ?? '';
                                    final isMatchingEntry = itemId.isNotEmpty
                                        ? entryId == itemId
                                        : entryName == itemName &&
                                              entryVariant == itemVariant;

                                    if (isMatchingEntry) {
                                      final stockValue = entry['stock'] is num
                                          ? (entry['stock'] as num).toInt()
                                          : int.tryParse(
                                                  entry['stock']?.toString() ??
                                                      '',
                                                ) ??
                                                0;
                                      final startingStockValue =
                                          entry['startingStock'] is num
                                          ? (entry['startingStock'] as num)
                                                .toInt()
                                          : int.tryParse(
                                                  entry['startingStock']
                                                          ?.toString() ??
                                                      '',
                                                ) ??
                                                0;
                                      final actualStock = stockValue > 0
                                          ? stockValue
                                          : startingStockValue;
                                      final newStock = actualStock - quantity;
                                      final reducedStock = newStock < 0
                                          ? 0
                                          : newStock;
                                      final unitPrice = _parsePrice(
                                        entry['price'],
                                      );
                                      reductionAmount = unitPrice * quantity;
                                      final hasStockField = entry.containsKey(
                                        'stock',
                                      );
                                      final currentReduced =
                                          int.tryParse(
                                            entry['reducedQuantity']
                                                    ?.toString() ??
                                                '',
                                          ) ??
                                          0;
                                      return {
                                        ...entry,
                                        'stock': reducedStock,
                                        'reducedQuantity':
                                            currentReduced + quantity,
                                        if (!hasStockField)
                                          'startingStock': reducedStock,
                                      };
                                    }
                                    return entry;
                                  }).toList();

                                  await docRef.update({'items': updatedItems});
                                  final selectedItemId =
                                      item['id']?.toString() ?? '';
                                  InventoryService().recordStockReduction(
                                    itemName: categoryName,
                                    variantName: selectedItemId.isNotEmpty
                                        ? selectedItemId
                                        : item['name']?.toString() ?? '',
                                    quantity: quantity,
                                    sourceInventoryId: sourceDocId,
                                  );
                                  await FirebaseFirestore.instance
                                      .collection('stock_adjustments')
                                      .add({
                                        'userId': FirebaseAuth
                                            .instance
                                            .currentUser
                                            ?.uid,
                                        'staffId': FirebaseAuth
                                            .instance
                                            .currentUser
                                            ?.uid,
                                        'categoryName': categoryName,
                                        'categoryId': sourceDocId,
                                        'itemName': item['name'] ?? '',
                                        'variant': item['variant'] ?? '',
                                        'quantity': quantity,
                                        'unitPrice': unitPrice,
                                        'lossAmount': reductionAmount,
                                        'reason': reason,
                                        'comment': comment,
                                        'createdAt':
                                            FieldValue.serverTimestamp(),
                                      });

                                  final currentUser =
                                      FirebaseAuth.instance.currentUser;
                                  final staffName =
                                      (currentUser?.displayName
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? currentUser!.displayName!
                                      : currentUser?.email?.split('@').first ??
                                            'Staff');
                                  final variantLabel =
                                      (item['variant']?.toString() ?? '')
                                          .isNotEmpty
                                      ? ' (${item['variant']})'
                                      : '';

                                  await FirebaseFirestore.instance
                                      .collection('admin_notifications')
                                      .add({
                                        'title': 'Stock reduced',
                                        'message':
                                            '$staffName reduced $quantity x ${item['name'] ?? ''}$variantLabel from $currentStock to ${currentStock - quantity}. Expected sales decreased by ₱${reductionAmount.toStringAsFixed(2)}.',
                                        'category': 'Stock',
                                        'type': 'stock_adjustment',
                                        'itemName': item['name'] ?? '',
                                        'variant': item['variant'] ?? '',
                                        'quantity': quantity,
                                        'reductionAmount': reductionAmount,
                                        'categoryName': categoryName,
                                        'staffId': currentUser?.uid,
                                        'staffName': staffName,
                                        'isRead': false,
                                        'createdAt':
                                            FieldValue.serverTimestamp(),
                                      });

                                  if (mounted) {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      _buildSnackBar(
                                        'Stock reduced successfully!',
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      _buildSnackBar(
                                        'Failed to reduce stock: $e',
                                        isError: true,
                                      ),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC2105C),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text(
                                'Save',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
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
  }

  SnackBar _buildSnackBar(String message, {bool isError = false}) {
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError
          ? const Color(0xFFB71C1C)
          : const Color(0xFF880E4F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
      content: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _brandCategory(String name) {
    final nameLower = name.toLowerCase();
    if (nameLower.contains('cardboard')) return 'Featured';
    if (nameLower.contains('cake')) return 'Cakes';
    if (nameLower.contains('drink') || nameLower.contains('juice')) {
      return 'Beverages';
    }
    return 'Cupcakes';
  }

  Future<void> _showStockAdjustmentHistory({
    required String categoryName,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC2105C).withOpacity(0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reduction History',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              categoryName,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('stock_adjustments')
                        .where('categoryName', isEqualTo: categoryName)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Error loading history.'),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFC2105C),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      docs.sort((a, b) {
                        final aT =
                            (a.data() as Map<String, dynamic>?)?['createdAt']
                                as Timestamp?;
                        final bT =
                            (b.data() as Map<String, dynamic>?)?['createdAt']
                                as Timestamp?;
                        if (aT == null && bT == null) return 0;
                        if (aT == null) return 1;
                        if (bT == null) return -1;
                        return bT.compareTo(aT);
                      });

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history_toggle_off_rounded,
                                size: 48,
                                color: const Color(0xFFF8BBD0),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No reduction history found.',
                                style: TextStyle(
                                  color: Color(0xFFAD1457),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>?;
                          final quantity = data?['quantity']?.toString() ?? '0';
                          final itemName =
                              data?['itemName']?.toString() ?? 'Unknown';
                          final variant = data?['variant']?.toString() ?? '';
                          final reason =
                              data?['reason']?.toString() ?? 'No reason';
                          final comment = data?['comment']?.toString() ?? '';
                          final timestamp = data?['createdAt'] as Timestamp?;
                          final when = timestamp != null
                              ? DateTime.fromMillisecondsSinceEpoch(
                                  timestamp.seconds * 1000,
                                )
                              : null;
                          final formattedDate = when != null
                              ? '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}'
                              : 'Unknown date';
                          final formattedTime = when != null
                              ? '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:${when.second.toString().padLeft(2, '0')}'
                              : 'Unknown time';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F5),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFF8BBD0),
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
                                    Expanded(
                                      child: Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: Color(0xFFC2105C),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC2105C),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '-$quantity',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Variant: $variant',
                                  style: const TextStyle(
                                    color: Color(0xFFAD1457),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _HistoryDetailRow(
                                  icon: Icons.flag_outlined,
                                  label: reason,
                                ),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _HistoryDetailRow(
                                    icon: Icons.notes_rounded,
                                    label: comment,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 12,
                                      color: Color(0xFFAD1457),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$formattedDate  $formattedTime',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFAD1457),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFCE4EC),
                        foregroundColor: const Color(0xFFC2105C),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBundleItemsDialog(Map<String, dynamic> bundle) async {
    final bundleName = bundle['name']?.toString() ?? 'Bundle';
    final bundlePrice = _parsePrice(bundle['price']);
    final bundleId = bundle['bundleId']?.toString() ?? '';
    final bundleInstances = _bundleInstancesFromData(bundle);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 620),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC2105C).withOpacity(0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 14, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bundleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${bundleInstances.length} bundle${bundleInstances.length == 1 ? '' : 's'} - ₱${bundlePrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: bundleInstances.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'No bundle items available.',
                              style: TextStyle(
                                color: Color(0xFFAD1457),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: bundleInstances.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final instance = bundleInstances[index];
                            final items =
                                instance['items'] as List<dynamic>? ?? [];
                            final status =
                                instance['status']?.toString() ?? 'available';
                            final statusLabel = _bundleStatusLabel(status);
                            final canReduce =
                                status != 'sold' && status != 'reduced';

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0F5),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFF8BBD0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Bundle #${instance['number'] ?? index + 1}',
                                              style: const TextStyle(
                                                color: Color(0xFF4A0020),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Bundle ID: ${instance['id'] ?? _bundleInstanceId(bundleId, index)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFFAD1457),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        alignment: WrapAlignment.end,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: canReduce
                                                ? () async {
                                                    Navigator.pop(context);
                                                    await _showBundleInstanceReductionDialog(
                                                      bundle: bundle,
                                                      instanceIndex: index,
                                                      instance: instance,
                                                    );
                                                  }
                                                : null,
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 14,
                                            ),
                                            label: const Text('Reduce'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFC2105C,
                                              ),
                                              disabledForegroundColor:
                                                  Colors.grey,
                                              side: const BorderSide(
                                                color: Color(0xFFF8BBD0),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              textStyle: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          _ItemTag(
                                            icon: Icons.info_outline_rounded,
                                            label: statusLabel,
                                            bgColor: Colors.white,
                                            textColor: const Color(0xFFC2105C),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (items.isEmpty)
                                    const Text(
                                      'No items in this bundle.',
                                      style: TextStyle(
                                        color: Color(0xFFAD1457),
                                        fontSize: 12,
                                      ),
                                    )
                                  else
                                    ...items.map((item) {
                                      if (item is! Map<String, dynamic>) {
                                        return const SizedBox.shrink();
                                      }
                                      final itemName =
                                          item['name']?.toString() ?? 'Item';
                                      final itemQty = _parseInt(
                                        item['quantity'],
                                        fallback: 1,
                                      );
                                      final remainingQty = _parseInt(
                                        item['remaining'],
                                        fallback: itemQty,
                                      );
                                      final itemPrice = _parsePrice(
                                        item['price'],
                                      );
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$itemName - $remainingQty of $itemQty pcs',
                                                style: const TextStyle(
                                                  color: Color(0xFF4A0020),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '₱${itemPrice.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Color(0xFFC2105C),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
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
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBundleReductionDialog(Map<String, dynamic> bundle) async {
    final qtyController = TextEditingController();
    final commentController = TextEditingController();
    String? selectedReason;
    final reasonOptions = [
      'Damaged',
      'Dropped',
      'Expired',
      'Contaminated',
      'Other',
    ];
    final bundleName = bundle['name']?.toString() ?? 'Bundle';
    final sourceDocId = bundle['sourceDocId']?.toString() ?? '';
    final currentStock = _bundleStockForData(bundle);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Reduce Bundle',
                            style: TextStyle(
                              color: Color(0xFF4A0020),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFFC2105C),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoChip(
                      icon: Icons.inventory_2_rounded,
                      label: '$bundleName - Stock: $currentStock',
                      color: const Color(0xFFC2105C),
                    ),
                    const SizedBox(height: 14),
                    _PinkTextField(
                      controller: qtyController,
                      label: 'Quantity to reduce',
                      hint: 'Enter quantity',
                      icon: Icons.remove_circle_outline,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        prefixIcon: const Icon(
                          Icons.flag_outlined,
                          color: Color(0xFFC2105C),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: reasonOptions
                          .map(
                            (reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(reason),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedReason = value),
                    ),
                    const SizedBox(height: 12),
                    _PinkTextField(
                      controller: commentController,
                      label: 'Comment',
                      hint: 'Optional note',
                      icon: Icons.notes_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final qty = _parseInt(qtyController.text);
                        final reason = selectedReason?.trim() ?? '';
                        if (qty <= 0 || qty > currentStock) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            _buildSnackBar(
                              'Enter a valid reduction quantity',
                              isError: true,
                            ),
                          );
                          return;
                        }
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            _buildSnackBar(
                              'Please select a reason',
                              isError: true,
                            ),
                          );
                          return;
                        }

                        final user = FirebaseAuth.instance.currentUser;
                        final docRef = FirebaseFirestore.instance
                            .collection('staff_inventory')
                            .doc(sourceDocId);
                        await docRef.update({
                          'bundleCount': currentStock - qty,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        await FirebaseFirestore.instance
                            .collection('stock_adjustments')
                            .add({
                              'type': 'bundle_stock_adjustment',
                              'userId': user?.uid,
                              'staffId': user?.uid,
                              'categoryId': sourceDocId,
                              'categoryName': bundleName,
                              'itemName': bundleName,
                              'quantity': qty,
                              'previousStock': currentStock,
                              'newStock': currentStock - qty,
                              'reason': reason,
                              'comment': commentController.text.trim(),
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          _buildSnackBar('Bundle reduced successfully!'),
                        );
                      },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      label: const Text('Reduce Bundle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC2105C),
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

    qtyController.dispose();
    commentController.dispose();
  }

  Future<void> _showBundleInstanceReductionDialog({
    required Map<String, dynamic> bundle,
    required int instanceIndex,
    required Map<String, dynamic> instance,
  }) async {
    final commentController = TextEditingController();
    String? selectedReason;
    final reasonOptions = [
      'Damaged',
      'Dropped',
      'Expired',
      'Contaminated',
      'Other',
    ];
    final bundleName = bundle['name']?.toString() ?? 'Bundle';
    final sourceDocId = bundle['sourceDocId']?.toString() ?? '';
    final currentStock = _bundleStockForData(bundle);
    final instanceId =
        instance['id']?.toString() ??
        _bundleInstanceId(bundle['bundleId']?.toString() ?? '', instanceIndex);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Reduce Bundle #${instance['number'] ?? instanceIndex + 1}',
                            style: const TextStyle(
                              color: Color(0xFF4A0020),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFFC2105C),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoChip(
                      icon: Icons.inventory_2_rounded,
                      label: '$bundleName - $instanceId',
                      color: const Color(0xFFC2105C),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        prefixIcon: const Icon(
                          Icons.flag_outlined,
                          color: Color(0xFFC2105C),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: reasonOptions
                          .map(
                            (reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(reason),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedReason = value),
                    ),
                    const SizedBox(height: 12),
                    _PinkTextField(
                      controller: commentController,
                      label: 'Comment',
                      hint: 'Optional note',
                      icon: Icons.notes_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final reason = selectedReason?.trim() ?? '';
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            _buildSnackBar(
                              'Please select a reason',
                              isError: true,
                            ),
                          );
                          return;
                        }

                        final instances = _bundleInstancesFromData(bundle);
                        if (instanceIndex < 0 ||
                            instanceIndex >= instances.length ||
                            sourceDocId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            _buildSnackBar(
                              'Unable to reduce this bundle',
                              isError: true,
                            ),
                          );
                          return;
                        }
                        instances[instanceIndex] = {
                          ...instances[instanceIndex],
                          'status': 'reduced',
                          'reductionReason': reason,
                          'reductionComment': commentController.text.trim(),
                          'reducedAt': Timestamp.now(),
                        };

                        final user = FirebaseAuth.instance.currentUser;
                        final docRef = FirebaseFirestore.instance
                            .collection('staff_inventory')
                            .doc(sourceDocId);
                        await docRef.update({
                          'bundleInstances': instances,
                          'bundleCount': currentStock > 0
                              ? currentStock - 1
                              : currentStock,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        await FirebaseFirestore.instance
                            .collection('stock_adjustments')
                            .add({
                              'type': 'bundle_instance_adjustment',
                              'userId': user?.uid,
                              'staffId': user?.uid,
                              'categoryId': sourceDocId,
                              'categoryName': bundleName,
                              'itemName': bundleName,
                              'bundleInstanceId': instanceId,
                              'quantity': 1,
                              'previousStock': currentStock,
                              'newStock': currentStock > 0
                                  ? currentStock - 1
                                  : currentStock,
                              'reason': reason,
                              'comment': commentController.text.trim(),
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          _buildSnackBar('Bundle reduced successfully!'),
                        );
                      },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      label: const Text('Reduce Bundle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC2105C),
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

    commentController.dispose();
  }

  Future<void> _showBundleReductionHistory(Map<String, dynamic> bundle) async {
    final sourceDocId = bundle['sourceDocId']?.toString() ?? '';
    final bundleName = bundle['name']?.toString() ?? 'Bundle';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 540),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$bundleName History',
                        style: const TextStyle(
                          color: Color(0xFF4A0020),
                          fontSize: 18,
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
                const SizedBox(height: 10),
                Flexible(
                  child: FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('stock_adjustments')
                        .where('categoryId', isEqualTo: sourceDocId)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFC2105C),
                          ),
                        );
                      }
                      final docs =
                          (snapshot.data?.docs ?? []).where((doc) {
                            final data = doc.data() as Map<String, dynamic>?;
                            return data?['type'] == 'bundle_stock_adjustment';
                          }).toList()..sort((a, b) {
                            final aData = a.data() as Map<String, dynamic>?;
                            final bData = b.data() as Map<String, dynamic>?;
                            final aTime =
                                (aData?['createdAt'] as Timestamp?)?.toDate() ??
                                DateTime.fromMillisecondsSinceEpoch(0);
                            final bTime =
                                (bData?['createdAt'] as Timestamp?)?.toDate() ??
                                DateTime.fromMillisecondsSinceEpoch(0);
                            return bTime.compareTo(aTime);
                          });
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No bundle reductions yet.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F5),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFF8BBD0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${data['quantity']} bundle(s) reduced',
                                  style: const TextStyle(
                                    color: Color(0xFF4A0020),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Reason: ${data['reason'] ?? ''}',
                                  style: const TextStyle(
                                    color: Color(0xFFAD1457),
                                    fontSize: 12,
                                  ),
                                ),
                                if ((data['comment']?.toString() ?? '')
                                    .isNotEmpty)
                                  Text(
                                    'Note: ${data['comment']}',
                                    style: const TextStyle(fontSize: 12),
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

  Widget _buildInventoryToggle({
    required int categoryCount,
    required int bundleCount,
    required int coffeeCount,
  }) {
    Widget option({
      required bool selected,
      required String label,
      required int count,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFC2105C) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFFC2105C)
                    : const Color(0xFFF8BBD0),
                width: 1.4,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFC2105C).withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : const Color(0xFFC2105C),
                ),
                const SizedBox(width: 8),
                Text(
                  '$label ($count)',
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF8B0035),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        children: [
          option(
            selected: _showCategories && !_showCoffee,
            label: 'Categories',
            count: categoryCount,
            icon: Icons.category_rounded,
            onTap: () => setState(() {
              _showCategories = true;
              _showCoffee = false;
            }),
          ),
          const SizedBox(width: 12),
          option(
            selected: !_showCategories && !_showCoffee,
            label: 'Bundle',
            count: bundleCount,
            icon: Icons.inventory_2_rounded,
            onTap: () => setState(() {
              _showCategories = false;
              _showCoffee = false;
            }),
          ),
          const SizedBox(width: 12),
          option(
            selected: _showCoffee,
            label: 'Coffee',
            count: coffeeCount,
            icon: Icons.local_cafe_rounded,
            onTap: () => setState(() {
              _showCategories = false;
              _showCoffee = true;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyInventoryState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: const Color(0xFFC2105C).withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFFAD1457),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBundleList(List<Map<String, dynamic>> bundleDocs) {
    if (bundleDocs.isEmpty) {
      return _buildEmptyInventoryState(
        icon: Icons.inventory_2_outlined,
        message: 'No bundles available.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      itemCount: bundleDocs.length,
      itemBuilder: (context, index) {
        final bundle = bundleDocs[index];
        final bundleName = bundle['name']?.toString() ?? 'Bundle';
        final bundleItems = bundle['items'] as List<dynamic>? ?? [];
        final bundleStock = _bundleStockForData(bundle);
        final stockColor = _stockColor(bundleStock);
        final bundlePrice = _parsePrice(bundle['price']);

        return _AnimatedCategorySection(
          index: index,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFF8BBD0).withOpacity(0.8),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC2105C).withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFC2105C), Color(0xFFD81B6A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Bundle',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              bundleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${bundleItems.length} item${bundleItems.length == 1 ? '' : 's'} per bundle',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _ItemTag(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stock: $bundleStock',
                        bgColor: Colors.white,
                        textColor: stockColor,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ItemTag(
                            icon: Icons.payments_outlined,
                            label: '₱${bundlePrice.toStringAsFixed(2)}',
                            bgColor: const Color(0xFFE8F5E9),
                            textColor: const Color(0xFF2E7D32),
                          ),
                          if ((bundle['bundleId']?.toString() ?? '').isNotEmpty)
                            _ItemTag(
                              icon: Icons.confirmation_number_outlined,
                              label: bundle['bundleId']?.toString() ?? '',
                              bgColor: const Color(0xFFFCE4EC),
                              textColor: const Color(0xFFAD1457),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showBundleItemsDialog(bundle),
                          icon: const Icon(Icons.visibility_rounded, size: 18),
                          label: const Text('View Bundle Items'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC2105C),
                            side: const BorderSide(
                              color: Color(0xFFF8BBD0),
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: bundleStock > 0
                              ? () => _showBundleReductionDialog(bundle)
                              : null,
                          icon: const Icon(
                            Icons.remove_circle_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Reduce'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC2105C),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoffeeCategoryCard(Map<String, dynamic> category, int index) {
    final coffeeName = category['categoryName']?.toString() ?? 'Coffee';
    final coffeeId = category['coffeeId']?.toString() ?? '';
    final items =
        (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return _AnimatedCategorySection(
      index: index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC2105C), Color(0xFFD81B6A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC2105C).withOpacity(0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          coffeeId.isNotEmpty ? 'COFFEE - $coffeeId' : 'COFFEE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        coffeeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${items.length} size${items.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _markCoffeeLowStock(category),
                  icon: const Icon(Icons.warning_amber_rounded, size: 15),
                  label: const Text('Mark Low'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.22),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final item = entry.value;
            final sizeName = item['name']?.toString() ?? 'Regular';
            final price = _parsePrice(item['price']);
            final addons =
                (item['addons'] as List?)?.cast<Map<String, dynamic>>() ?? [];

            return _AnimatedItemCard(
              delay: Duration(milliseconds: 100 + entry.key * 60),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFF8BBD0).withOpacity(0.8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC2105C).withOpacity(0.07),
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
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF48FB1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.local_cafe_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            sizeName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A0A10),
                            ),
                          ),
                        ),
                        _ItemTag(
                          icon: Icons.payments_outlined,
                          label: '₱${price.toStringAsFixed(0)}',
                          bgColor: const Color(0xFFE8F5E9),
                          textColor: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                    if (addons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: addons.map((addon) {
                          final addonName =
                              addon['name']?.toString() ?? 'Add-on';
                          final addonPrice = _parsePrice(addon['priceDelta']);
                          final priceLabel = addonPrice > 0
                              ? ' +₱${addonPrice.toStringAsFixed(0)}'
                              : '';
                          return _ItemTag(
                            icon: Icons.add_circle_outline_rounded,
                            label: '$addonName$priceLabel',
                            bgColor: const Color(0xFFFCE4EC),
                            textColor: const Color(0xFFAD1457),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildCategoryList(List<Map<String, dynamic>> categoryDocs) {
    if (categoryDocs.isEmpty) {
      return _buildEmptyInventoryState(
        icon: Icons.category_outlined,
        message: 'No category items available.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      itemCount: categoryDocs.length,
      itemBuilder: (context, index) {
        final category = categoryDocs[index];
        final categoryName = category['categoryName']?.toString() ?? 'Unknown';
        final items =
            (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (category['isCoffee'] == true) {
          return _buildCoffeeCategoryCard(category, index);
        }
        final categoryLabel = _brandCategory(categoryName);

        return _AnimatedCategorySection(
          index: index,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFC2105C), Color(0xFFD81B6A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC2105C).withOpacity(0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              categoryLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            categoryName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${items.length} item${items.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showStockAdjustmentHistory(
                        categoryName: categoryName,
                      ),
                      icon: const Icon(Icons.history_rounded, size: 15),
                      label: const Text('History'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.22),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final itemStock = _stockForItem(item);
                final stockColor = _stockColor(itemStock);

                return _AnimatedItemCard(
                  delay: Duration(milliseconds: 100 + idx * 60),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFF8BBD0).withOpacity(0.8),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFC2105C).withOpacity(0.07),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 80,
                            margin: const EdgeInsets.only(right: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFC2105C),
                                  const Color(0xFFC2105C).withOpacity(0.2),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name']?.toString() ?? 'Item',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A0A10),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if ((item['variant']?.toString() ?? '')
                                        .isNotEmpty)
                                      _ItemTag(
                                        icon: Icons.tune_rounded,
                                        label:
                                            item['variant']?.toString() ?? '',
                                        bgColor: const Color(0xFFFCE4EC),
                                        textColor: const Color(0xFFAD1457),
                                      ),
                                    _ItemTag(
                                      icon: Icons.payments_outlined,
                                      label: '₱${item['price'] ?? '0'}',
                                      bgColor: const Color(0xFFE8F5E9),
                                      textColor: const Color(0xFF2E7D32),
                                    ),
                                    _ItemTag(
                                      icon: Icons.inventory_2_outlined,
                                      label: 'Stock: $itemStock',
                                      bgColor: stockColor.withOpacity(0.12),
                                      textColor: stockColor,
                                    ),
                                    _ItemTag(
                                      icon: Icons.calendar_today_outlined,
                                      label:
                                          '${item['expirationDate'] ?? '--'}',
                                      bgColor: const Color(0xFFFFF3E0),
                                      textColor: const Color(0xFFE65100),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              _showStockAdjustmentDialog(
                                categoryName: categoryName,
                                sourceDocId:
                                    item['sourceDocId']?.toString() ??
                                    category['categoryId']?.toString() ??
                                    '',
                                item: item,
                                currentStock: itemStock,
                              );
                            },
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 20,
                            ),
                            label: const Text('Reduce'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC2105C),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 18,
                              ),
                              minimumSize: const Size(90, 46),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: const Color(0xFFC2105C),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF8B0035),
                      Color(0xFFC2105C),
                      Color(0xFFE91E8C),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -30,
                      right: -20,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -40,
                      left: -30,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 30,
                      right: 80,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    // Header content
                    Positioned(
                      bottom: 22,
                      left: 20,
                      right: 20,
                      child: FadeTransition(
                        opacity: _headerFadeAnim,
                        child: SlideTransition(
                          position: _headerSlideAnim,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                _isFilteredCategory
                                    ? widget.selectedIsBundle
                                          ? (widget.selectedCategoryName ??
                                                'Selected Bundle')
                                          : _isCoffeeView
                                          ? '${widget.selectedCategoryName ?? 'Selected'} Coffee'
                                          : '${widget.selectedCategoryName ?? 'Selected'} Categories'
                                    : 'All Categories',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isFilteredCategory
                                    ? widget.selectedIsBundle
                                          ? 'Manage this bundle inventory'
                                          : _isCoffeeView
                                          ? 'Manage this coffee flavor'
                                          : 'Manage this category inventory'
                                    : 'Manage your product inventory',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            leadingWidth: 72,
            leading: IconButton(
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              icon: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
        body: StreamBuilder<QuerySnapshot>(
          stream: _staffInventoryStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 56,
                      color: const Color(0xFFC2105C).withOpacity(0.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Error loading items',
                      style: TextStyle(color: Color(0xFFAD1457)),
                    ),
                  ],
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFFC2105C)),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('sales_inventory')
                  .snapshots(),
              builder: (context, rootSnapshot) {
                if (rootSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFC2105C)),
                  );
                }

                final activeRootById = <String, Map<String, dynamic>>{};
                final activeRootByName = <String, Map<String, dynamic>>{};
                for (final rootDoc in rootSnapshot.data?.docs ?? []) {
                  final rootData = rootDoc.data() as Map<String, dynamic>?;
                  if (rootData == null || rootData['isDeleted'] == true) {
                    continue;
                  }
                  activeRootById[rootDoc.id] = rootData;
                  final rootName =
                      rootData['name']?.toString().trim().toLowerCase() ?? '';
                  if (rootName.isNotEmpty)
                    activeRootByName[rootName] = rootData;
                }

                String itemKey(Map<String, dynamic> item) =>
                    '${item['name'] ?? ''}|${item['price'] ?? ''}'
                        .toLowerCase();

                final visibleDocs = <Map<String, dynamic>>[];
                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null || data['isDeleted'] == true) continue;
                  final sourceId = data['sourceInventoryId']?.toString() ?? '';
                  final name =
                      data['name']?.toString().trim().toLowerCase() ?? '';
                  final selectedSourceId =
                      widget.selectedSourceInventoryId?.trim() ?? '';
                  final selectedName =
                      widget.selectedCategoryName?.trim().toLowerCase() ?? '';
                  if (_isFilteredCategory) {
                    final matchesSource =
                        selectedSourceId.isNotEmpty &&
                        (sourceId == selectedSourceId ||
                            doc.id == selectedSourceId);
                    final matchesName =
                        selectedSourceId.isEmpty &&
                        selectedName.isNotEmpty &&
                        name == selectedName;
                    if (!matchesSource && !matchesName) continue;
                  }
                  final isCoffee = data['isCoffee'] == true;
                  final rootData =
                      activeRootById[sourceId] ??
                      activeRootByName[name] ??
                      (isCoffee ? data : null);
                  if (rootData == null) continue;

                  if (isCoffee) {
                    final coffeeItems = _coffeeItemsFromData(data);
                    if (coffeeItems.isEmpty) continue;
                    visibleDocs.add({
                      ...data,
                      'name': data['name'] ?? 'Coffee',
                      'imageUrl': data['imageUrl'],
                      'items': coffeeItems,
                      'sourceDocId': doc.id,
                      'isCoffee': true,
                    });
                    continue;
                  }

                  if (data['isBundle'] == true) {
                    visibleDocs.add({
                      ...data,
                      'name': rootData['name'] ?? data['name'],
                      'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                      'sourceDocId': doc.id,
                    });
                    continue;
                  }

                  final rootKeys = ((rootData['items'] as List<dynamic>?) ?? [])
                      .whereType<Map>()
                      .map((item) => itemKey(Map<String, dynamic>.from(item)))
                      .toSet();
                  final activeItems = ((data['items'] as List<dynamic>?) ?? [])
                      .whereType<Map>()
                      .map((item) => Map<String, dynamic>.from(item))
                      .where((item) {
                        final expirationDate =
                            item['expirationDate']?.toString() ?? '';
                        return !_isExpiredItem(expirationDate) &&
                            (rootKeys.isEmpty ||
                                rootKeys.contains(itemKey(item)));
                      })
                      .toList();
                  if (activeItems.isEmpty) continue;
                  visibleDocs.add({
                    ...data,
                    'name': rootData['name'] ?? data['name'],
                    'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                    'items': activeItems,
                    'sourceDocId': doc.id,
                  });
                }

                final groupedCategories = <String, Map<String, dynamic>>{};
                for (final data in visibleDocs) {
                  if (data['isBundle'] == true) continue;
                  final categoryName =
                      data['name']?.toString() ?? 'Unknown Category';
                  final items =
                      (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
                      [];
                  final itemRecords = items.map((item) {
                    final itemData = Map<String, dynamic>.from(item);
                    itemData['sourceDocId'] = data['sourceDocId'];
                    itemData['categoryName'] = categoryName;
                    return itemData;
                  }).toList();
                  if (itemRecords.isEmpty) continue;
                  final categoryKey =
                      data['sourceInventoryId']?.toString().trim().isNotEmpty ==
                          true
                      ? data['sourceInventoryId'].toString()
                      : data['sourceDocId']?.toString() ?? categoryName;
                  groupedCategories[categoryKey] = {
                    'categoryName': categoryName,
                    'categoryId': data['sourceDocId'],
                    'items': itemRecords,
                    'isCoffee': data['isCoffee'] == true,
                    'sourceDocId': data['sourceDocId'],
                    'coffeeId': data['coffeeId'],
                    'isLowStock': data['isLowStock'] == true,
                  };
                }

                final allCategoryDocs = groupedCategories.values.toList();
                final categoryDocs = allCategoryDocs
                    .where((data) => data['isCoffee'] != true)
                    .toList();
                final coffeeDocs = allCategoryDocs
                    .where((data) => data['isCoffee'] == true)
                    .toList();
                final bundleDocs = visibleDocs
                    .where((data) => data['isBundle'] == true)
                    .toList();

                if (!_isFilteredCategory &&
                    categoryDocs.isEmpty &&
                    (bundleDocs.isNotEmpty || coffeeDocs.isNotEmpty) &&
                    _showCategories) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _showCategories = false;
                      _showCoffee = coffeeDocs.isNotEmpty && bundleDocs.isEmpty;
                    });
                  });
                }

                if (categoryDocs.isEmpty &&
                    bundleDocs.isEmpty &&
                    coffeeDocs.isEmpty) {
                  return _buildEmptyInventoryState(
                    icon: Icons.category_outlined,
                    message: 'No items available.',
                  );
                }

                return Column(
                  children: [
                    if (!_isFilteredCategory)
                      _buildInventoryToggle(
                        categoryCount: categoryDocs.length,
                        bundleCount: bundleDocs.length,
                        coffeeCount: coffeeDocs.length,
                      ),
                    Expanded(
                      child: widget.selectedIsCoffee
                          ? _buildCategoryList(coffeeDocs)
                          : widget.selectedIsBundle
                          ? _buildBundleList(bundleDocs)
                          : _isFilteredCategory
                          ? _buildCategoryList(
                              widget.selectedIsCoffee
                                  ? coffeeDocs
                                  : categoryDocs,
                            )
                          : _showCoffee
                          ? _buildCategoryList(coffeeDocs)
                          : _showCategories
                          ? _buildCategoryList(categoryDocs)
                          : _buildBundleList(bundleDocs),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─── Helper Widgets ──────────────────────────────────────────────────────────

class _AnimatedCategorySection extends StatefulWidget {
  final Widget child;
  final int index;
  const _AnimatedCategorySection({required this.child, required this.index});

  @override
  State<_AnimatedCategorySection> createState() =>
      _AnimatedCategorySectionState();
}

class _AnimatedCategorySectionState extends State<_AnimatedCategorySection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: widget.index * 120), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _AnimatedItemCard extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _AnimatedItemCard({required this.child, required this.delay});

  @override
  State<_AnimatedItemCard> createState() => _AnimatedItemCardState();
}

class _AnimatedItemCardState extends State<_AnimatedItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _ItemTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color textColor;

  const _ItemTag({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HistoryDetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: const Color(0xFFAD1457)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4A0020)),
          ),
        ),
      ],
    );
  }
}

class _PinkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLines;

  const _PinkTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFFC2105C), size: 18),
        labelStyle: const TextStyle(color: Color(0xFFC2105C)),
        hintStyle: TextStyle(
          color: const Color(0xFFAD1457).withOpacity(0.4),
          fontSize: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF8BBD0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFC2105C), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFFFF0F5),
      ),
    );
  }
}
