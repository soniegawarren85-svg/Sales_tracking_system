import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/inventory_service.dart';
import '../widgets/top_notification.dart';

class AllCategPage extends StatefulWidget {
  final String? selectedCategoryName;
  final String? selectedSourceInventoryId;
  final bool selectedIsBundle;
  final bool selectedIsCoffee;
  final bool embedded;

  const AllCategPage({
    super.key,
    this.selectedCategoryName,
    this.selectedSourceInventoryId,
    this.selectedIsBundle = false,
    this.selectedIsCoffee = false,
    this.embedded = false,
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
  bool _showAddons = false;
  bool _showAllCategoryItems = false;
  String _tableSearchQuery = '';
  String? _selectedTableCategoryKey;
  List<String> _staffInventoryIds = const [];
  // Keep both subscriptions stable while the user searches or switches tabs.
  // Recreating them from build() temporarily put StreamBuilder back into its
  // waiting state, which replaced the search field with the loading layout.
  Stream<QuerySnapshot>? _staffInventoryStreamCache;
  late final Stream<QuerySnapshot> _rootInventoryStream;

  bool get _isFilteredCategory =>
      (widget.selectedCategoryName?.trim().isNotEmpty ?? false) ||
      (widget.selectedSourceInventoryId?.trim().isNotEmpty ?? false);

  bool get _isCoffeeView => widget.selectedIsCoffee;

  @override
  void initState() {
    super.initState();
    _showCoffee = widget.selectedIsCoffee;
    _showCategories = !widget.selectedIsBundle && !widget.selectedIsCoffee;
    _rootInventoryStream = FirebaseFirestore.instance
        .collection('sales_inventory')
        .snapshots();
    _initStaffIdentity();
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

  Future<void> _initStaffIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final uid =
        FirebaseAuth.instance.currentUser?.uid ??
        prefs.getString('lastStaffDocId') ??
        prefs.getString('lastUserId');
    if ((uid ?? '').isEmpty) return;
    _staffInventoryIds = const [];
    await _loadStaffInventoryIds(uid!);
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

    if (mounted) {
      setState(() {
        _staffInventoryIds = ids.toList();
        _staffInventoryStreamCache = null;
      });
    }
  }

  Stream<QuerySnapshot> _staffInventoryStream() {
    if (_staffInventoryStreamCache != null) {
      return _staffInventoryStreamCache!;
    }
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    final query = FirebaseFirestore.instance.collection('staff_inventory');
    if (ids.isEmpty) {
      return _staffInventoryStreamCache = query
          .where('staffId', isEqualTo: '')
          .snapshots();
    }
    return _staffInventoryStreamCache = ids.length == 1
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

  Widget _buildInventoryImage(
    String? src, {
    IconData fallbackIcon = Icons.cake_rounded,
  }) {
    final image = src?.trim() ?? '';
    if (image.isEmpty) return _imageFallback(fallbackIcon);
    if (image.startsWith('data:image/')) {
      final commaIndex = image.indexOf(',');
      if (commaIndex != -1) {
        try {
          return Image.memory(
            base64Decode(image.substring(commaIndex + 1)),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _imageFallback(fallbackIcon),
          );
        } catch (_) {
          return _imageFallback(fallbackIcon);
        }
      }
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(
        image,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _imageFallback(fallbackIcon),
      );
    }
    return Image.asset(
      image,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _imageFallback(fallbackIcon),
    );
  }

  Widget _imageFallback(IconData icon) => Container(
    color: const Color(0xFFFFF0E4),
    child: Icon(icon, color: const Color(0xFFC2105C), size: 30),
  );

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<Map<String, dynamic>> _coffeeItemsFromData(
    Map<String, dynamic> data, {
    Map<String, dynamic>? rootData,
  }) {
    final basePrice = _parsePrice(data['basePrice'] ?? rootData?['basePrice']);
    final sizes =
        ((data['sizes'] as List<dynamic>?) ??
                (rootData?['sizes'] as List<dynamic>?) ??
                [])
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
    for (final source in [data, if (rootData != null) rootData]) {
      for (final addon
          in (source['addonOptions'] as List<dynamic>? ?? [])
              .whereType<Map>()) {
        final name = addon['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        addonByName.putIfAbsent(name, () => Map<String, dynamic>.from(addon));
      }
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
    final instances = _bundleInstancesFromData(bundleData);
    final availableInstances = instances.where((instance) {
      final status =
          instance['status']?.toString().trim().toLowerCase() ?? 'available';
      return status == 'available';
    }).length;
    return instances.isNotEmpty
        ? availableInstances
        : _parseInt(bundleData['bundleCount']);
  }

  String _bundleExpirationDate(Map<String, dynamic> bundleData) {
    final dates = <String>[];
    void collectItems(dynamic rawItems) {
      if (rawItems is! List) return;
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final date = raw['expirationDate']?.toString().trim() ?? '';
        if (date.isNotEmpty) dates.add(date);
      }
    }

    collectItems(bundleData['items']);
    for (final instance in _bundleInstancesFromData(bundleData)) {
      collectItems(instance['items']);
    }
    if (dates.isEmpty) return '--';
    dates.sort((a, b) {
      final first = DateTime.tryParse(a);
      final second = DateTime.tryParse(b);
      if (first == null || second == null) return a.compareTo(b);
      return first.compareTo(second);
    });
    return dates.first;
  }

  bool _hasExpiredBundleItem(Map<String, dynamic> bundleData) {
    final rawItems = bundleData['items'] as List<dynamic>? ?? [];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final expirationDate = item['expirationDate']?.toString() ?? '';
      if (_isExpiredItem(expirationDate)) return true;
    }
    for (final instance in _bundleInstancesFromData(bundleData)) {
      final items = instance['items'] as List<dynamic>? ?? [];
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final expirationDate = item['expirationDate']?.toString() ?? '';
        if (_isExpiredItem(expirationDate)) return true;
      }
    }
    return false;
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
    bool isSaving = false;
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
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
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
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
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
                            const Expanded(
                              child: Text(
                                'Reduce Stock',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              color: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                      // Dialog Body
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Item info chip row
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _InfoChip(
                                    icon: Icons.label_outline_rounded,
                                    label: item['name']?.toString() ?? '',
                                    color: const Color(0xFFC2105C),
                                  ),
                                  if ((item['variant']?.toString() ?? '')
                                      .isNotEmpty)
                                    _InfoChip(
                                      icon: Icons.tune_rounded,
                                      label: item['variant']?.toString() ?? '',
                                      color: const Color(0xFFAD1457),
                                    ),
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
                              DropdownButtonFormField<String>(
                                initialValue: selectedReason,
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
                              if (selectedReason == 'Other') ...[
                                const SizedBox(height: 14),
                                _PinkTextField(
                                  controller: commentController,
                                  label: 'Comment',
                                  hint: 'Add a note...',
                                  icon: Icons.notes_rounded,
                                  maxLines: 3,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 190,
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final quantity =
                                          int.tryParse(
                                            qtyController.text.trim(),
                                          ) ??
                                          0;
                                      final reason =
                                          selectedReason?.trim() ?? '';
                                      final comment = selectedReason == 'Other'
                                          ? commentController.text.trim()
                                          : '';

                                      if (quantity <= 0 ||
                                          quantity > currentStock) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          _buildSnackBar(
                                            'Enter a valid reduction quantity',
                                            isError: true,
                                          ),
                                        );
                                        return;
                                      }
                                      if (reason.isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          _buildSnackBar(
                                            'Please select a reason',
                                            isError: true,
                                          ),
                                        );
                                        return;
                                      }

                                      setState(() => isSaving = true);
                                      try {
                                        final docRef = FirebaseFirestore
                                            .instance
                                            .collection('staff_inventory')
                                            .doc(sourceDocId);
                                        final snapshot = await docRef.get();
                                        final data = snapshot.data();
                                        final items =
                                            (data?['items'] as List?)
                                                ?.cast<
                                                  Map<String, dynamic>
                                                >() ??
                                            [];
                                        final unitPrice = _parsePrice(
                                          item['price'],
                                        );
                                        double reductionAmount = 0.0;
                                        final updatedItems = items.map((entry) {
                                          final entryName =
                                              entry['name']?.toString() ?? '';
                                          final entryVariant =
                                              entry['variant']?.toString() ??
                                              '';
                                          final entryId =
                                              entry['id']?.toString() ?? '';
                                          final itemName =
                                              item['name']?.toString() ?? '';
                                          final itemVariant =
                                              item['variant']?.toString() ?? '';
                                          final itemId =
                                              item['id']?.toString() ?? '';
                                          final isMatchingEntry =
                                              itemId.isNotEmpty
                                              ? entryId == itemId
                                              : entryName == itemName &&
                                                    entryVariant == itemVariant;

                                          if (isMatchingEntry) {
                                            final stockValue =
                                                entry['stock'] is num
                                                ? (entry['stock'] as num)
                                                      .toInt()
                                                : int.tryParse(
                                                        entry['stock']
                                                                ?.toString() ??
                                                            '',
                                                      ) ??
                                                      0;
                                            final startingStockValue =
                                                entry['startingStock'] is num
                                                ? (entry['startingStock']
                                                          as num)
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
                                            final newStock =
                                                actualStock - quantity;
                                            final reducedStock = newStock < 0
                                                ? 0
                                                : newStock;
                                            final unitPrice = _parsePrice(
                                              entry['price'],
                                            );
                                            reductionAmount =
                                                unitPrice * quantity;
                                            final hasStockField = entry
                                                .containsKey('stock');
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

                                        await docRef.update({
                                          'items': updatedItems,
                                        });
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
                                              'itemId':
                                                  item['id']?.toString() ??
                                                  item['itemId']?.toString() ??
                                                  item['variantId']
                                                      ?.toString() ??
                                                  '',
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
                                            : currentUser?.email
                                                      ?.split('@')
                                                      .first ??
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
                                              'reductionAmount':
                                                  reductionAmount,
                                              'categoryName': categoryName,
                                              'staffId': currentUser?.uid,
                                              'staffName': staffName,
                                              'isRead': false,
                                              'createdAt':
                                                  FieldValue.serverTimestamp(),
                                            });

                                        if (mounted) {
                                          Navigator.of(context).pop();
                                          showTopNotification(
                                            context,
                                            'Stock reduced successfully!',
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          setState(() => isSaving = false);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
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
                                  vertical: 12,
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Reduce',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
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

  String _monthName(int month) {
    const months = [
      '',
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
    return months[month.clamp(1, 12)];
  }

  Future<void> _showStockAdjustmentHistory({
    required String categoryName,
    String? categoryId,
    Map<String, String> itemIds = const {},
  }) async {
    var historySearch = '';
    // Default to today; choose a different day from the calendar to view
    // older records.
    DateTime? historyDate = DateTime.now();
    var selectedHistoryCategory = categoryName;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
              child: Container(
                width: double.infinity,
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
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
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
                                  'Categories History',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (value) => setDialogState(
                                () =>
                                    historySearch = value.trim().toLowerCase(),
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Search item, ID, price, reason, date',
                                prefixIcon: const Icon(Icons.search_rounded),
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFFFFF0F5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: historyDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setDialogState(() => historyDate = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_month_rounded),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: selectedHistoryCategory.isEmpty,
                              onSelected: (_) => setDialogState(
                                () => selectedHistoryCategory = '',
                              ),
                            ),
                            ChoiceChip(
                              label: Text(categoryName),
                              selected: selectedHistoryCategory == categoryName,
                              onSelected: (_) => setDialogState(
                                () => selectedHistoryCategory = categoryName,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Content
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('stock_adjustments')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Error loading history.'),
                            );
                          }
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFC2105C),
                              ),
                            );
                          }

                          final docs = (snapshot.data?.docs ?? []).where((doc) {
                            final data = doc.data() as Map<String, dynamic>?;
                            // Historical adjustments were saved with several
                            // category schemas.  The selected date must never
                            // hide a real reduction merely due to that old
                            // category metadata; the dialog is a history of
                            // all category reductions for the staff/day.
                            final timestamp = data?['createdAt'] as Timestamp?;
                            if (historyDate != null && timestamp != null) {
                              final date = timestamp.toDate().toLocal();
                              final startOfDay = DateTime(
                                historyDate!.year,
                                historyDate!.month,
                                historyDate!.day,
                              );
                              final endOfDay = startOfDay
                                  .add(const Duration(days: 1))
                                  .subtract(const Duration(microseconds: 1));
                              if (date.isBefore(startOfDay) ||
                                  date.isAfter(endOfDay)) {
                                return false;
                              }
                            }
                            if (historySearch.isEmpty) return true;
                            final createdAtDate = timestamp?.toDate().toLocal();
                            final formattedDate = createdAtDate == null
                                ? ''
                                : '${createdAtDate.year.toString().padLeft(4, '0')}-${createdAtDate.month.toString().padLeft(2, '0')}-${createdAtDate.day.toString().padLeft(2, '0')} ${createdAtDate.hour.toString().padLeft(2, '0')}:${createdAtDate.minute.toString().padLeft(2, '0')}:${createdAtDate.second.toString().padLeft(2, '0')}';
                            return [
                              data?['itemName']?.toString() ?? '',
                              data?['itemId']?.toString() ?? '',
                              data?['unitPrice']?.toString() ?? '',
                              data?['reason']?.toString() ?? '',
                              formattedDate,
                              createdAtDate == null
                                  ? ''
                                  : '${createdAtDate.day.toString().padLeft(2, '0')}/${createdAtDate.month.toString().padLeft(2, '0')}/${createdAtDate.year}',
                              createdAtDate == null
                                  ? ''
                                  : '${createdAtDate.month}/${createdAtDate.day}/${createdAtDate.year}',
                              createdAtDate == null
                                  ? ''
                                  : '${createdAtDate.day} ${_monthName(createdAtDate.month)} ${createdAtDate.year}',
                              createdAtDate == null
                                  ? ''
                                  : '${_monthName(createdAtDate.month)} ${createdAtDate.day}, ${createdAtDate.year}',
                            ].join(' ').toLowerCase().contains(historySearch);
                          }).toList();
                          docs.sort((a, b) {
                            final aT =
                                (a.data()
                                        as Map<String, dynamic>?)?['createdAt']
                                    as Timestamp?;
                            final bT =
                                (b.data()
                                        as Map<String, dynamic>?)?['createdAt']
                                    as Timestamp?;
                            if (aT == null && bT == null) return 0;
                            if (aT == null) return 1;
                            if (bT == null) return -1;
                            return bT.compareTo(aT);
                          });

                          if (docs.isEmpty) {
                            return _buildLegacyCategoryReductions(
                              categoryName: categoryName,
                              categoryId: categoryId,
                              selectedDate: historyDate,
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data =
                                  docs[index].data() as Map<String, dynamic>?;
                              final quantity =
                                  data?['quantity']?.toString() ?? '0';
                              final itemName =
                                  data?['itemName']?.toString() ?? 'Unknown';
                              final historyVariant =
                                  data?['variant']?.toString().toLowerCase() ??
                                  '';
                              final historyItemKey =
                                  '${itemName.toLowerCase()}|$historyVariant';
                              final itemId =
                                  data?['itemId']
                                          ?.toString()
                                          .trim()
                                          .isNotEmpty ==
                                      true
                                  ? data!['itemId'].toString()
                                  : itemIds[historyItemKey] ?? '';
                              final unitPrice = _parsePrice(data?['unitPrice']);
                              final reason =
                                  data?['reason']?.toString() ?? 'No reason';
                              final comment =
                                  data?['comment']?.toString() ?? '';
                              final timestamp =
                                  data?['createdAt'] as Timestamp?;
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3CD),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: const Color(0xFFFFD166),
                                        ),
                                      ),
                                      child: Text(
                                        categoryName,
                                        style: const TextStyle(
                                          color: Color(0xFF9A6700),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                itemName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: Color(0xFFC2105C),
                                                ),
                                              ),
                                              if (itemId.isNotEmpty)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFE8F5E9,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFF81C784,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'ID: $itemId',
                                                    style: const TextStyle(
                                                      color: Color(0xFF2E7D32),
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFC2105C),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
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
                                      'Price: PHP ${unitPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Color(0xFFAD1457),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Older app versions only persisted reductions in `inventory_reports`.
  /// Keep those records visible without modifying the original data.
  Widget _buildLegacyCategoryReductions({
    required String categoryName,
    String? categoryId,
    required DateTime? selectedDate,
  }) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('inventory_reports').get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFC2105C)),
          );
        }
        final target = selectedDate == null
            ? null
            : DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final entries = <Map<String, dynamic>>[];
        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data() as Map<String, dynamic>? ?? const {};
          final rawDate = data['timestamp'];
          final date = rawDate is Timestamp
              ? rawDate.toDate().toLocal()
              : DateTime.tryParse(rawDate?.toString() ?? '');
          if (date == null ||
              (target != null &&
                  (date.year != target.year ||
                      date.month != target.month ||
                      date.day != target.day))) {
            continue;
          }
          // Legacy reports used several different fields for the category
          // (and some did not save one at all).  Do not discard a valid
          // dated reduction just because that old category metadata differs.
          for (final raw in data['items'] as List<dynamic>? ?? const []) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final quantity = _parseInt(item['reducedQuantity']);
            if (quantity <= 0) continue;
            entries.add({
              'name': item['name']?.toString() ?? 'Item',
              'variant': item['variant']?.toString() ?? '',
              'quantity': quantity,
              'price': _parsePrice(item['price']),
              'date': date,
            });
          }
        }
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'No reduction history found.',
              style: TextStyle(color: Color(0xFFAD1457)),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final date = entry['date'] as DateTime;
            final variant = entry['variant'] as String;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF8BBD0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(
                      '${entry['name']}${variant.isEmpty ? '' : ' ($variant)'}',
                      style: const TextStyle(
                        color: Color(0xFFC2105C), fontWeight: FontWeight.w800),
                    )),
                    Text('-${entry['quantity']}', style: const TextStyle(
                      color: Color(0xFFC2105C), fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Price: PHP ${(entry['price'] as double).toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  const Text('Reason: Stock reduction'),
                  const SizedBox(height: 4),
                  Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCoffeeVoidDialog(Map<String, dynamic> category) async {
    final coffeeName = category['categoryName']?.toString() ?? 'Coffee';
    final sourceDocId = category['sourceDocId']?.toString() ?? '';
    final items =
        (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final quantityController = TextEditingController();
    final commentController = TextEditingController();
    String? selectedSize;
    String? selectedReason;
    bool isSaving = false;
    final reasons = ['Damaged', 'Dropped', 'Expired', 'Contaminated', 'Other'];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final selectedItem = items.firstWhere(
            (item) => item['name']?.toString() == selectedSize,
            orElse: () => items.isNotEmpty ? items.first : <String, dynamic>{},
          );
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.remove_circle_outline_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Void Coffee Item',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
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
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoChip(
                          icon: Icons.local_cafe_rounded,
                          label: coffeeName,
                          color: const Color(0xFFC2105C),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSize,
                          decoration: InputDecoration(
                            labelText: 'Size',
                            prefixIcon: const Icon(
                              Icons.straighten_rounded,
                              color: Color(0xFFC2105C),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          items: items.map((item) {
                            final size = item['name']?.toString() ?? 'Size';
                            return DropdownMenuItem(
                              value: size,
                              child: Text(size),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => selectedSize = value),
                        ),
                        const SizedBox(height: 12),
                        _PinkTextField(
                          controller: quantityController,
                          label: 'Quantity to void',
                          hint: 'Enter quantity',
                          icon: Icons.remove_circle_outline,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedReason,
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
                          items: reasons
                              .map(
                                (reason) => DropdownMenuItem(
                                  value: reason,
                                  child: Text(reason),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => selectedReason = value),
                        ),
                        if (selectedReason == 'Other') ...[
                          const SizedBox(height: 12),
                          _PinkTextField(
                            controller: commentController,
                            label: 'Comment',
                            hint: 'Optional note',
                            icon: Icons.notes_rounded,
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 190,
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final quantity = _parseInt(
                                        quantityController.text,
                                      );
                                      final reason =
                                          selectedReason?.trim() ?? '';
                                      if (selectedSize == null ||
                                          selectedSize!.trim().isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          _buildSnackBar(
                                            'Please select a coffee size first',
                                            isError: true,
                                          ),
                                        );
                                        return;
                                      }
                                      if (quantity <= 0) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          _buildSnackBar(
                                            'Please enter a quantity to void',
                                            isError: true,
                                          ),
                                        );
                                        return;
                                      }
                                      if (reason.isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          _buildSnackBar(
                                            'Please select a reason',
                                            isError: true,
                                          ),
                                        );
                                        return;
                                      }
                                      setState(() => isSaving = true);
                                      try {
                                        if (sourceDocId.trim().isEmpty) {
                                          throw StateError(
                                            'Coffee inventory record was not found.',
                                          );
                                        }
                                        final docRef = FirebaseFirestore
                                            .instance
                                            .collection('staff_inventory')
                                            .doc(sourceDocId);
                                        final snapshot = await docRef.get();
                                        if (!snapshot.exists) {
                                          throw StateError(
                                            'Coffee inventory record was not found.',
                                          );
                                        }
                                        final snapshotData = snapshot.data()!;
                                        final inventoryField =
                                            snapshotData['items'] is List
                                            ? 'items'
                                            : 'sizes';
                                        final rawInventoryItems =
                                            (snapshotData[inventoryField]
                                                as List?) ??
                                            [];
                                        final storedItems = rawInventoryItems
                                            .whereType<Map>()
                                            .map(
                                              (item) =>
                                                  Map<String, dynamic>.from(
                                                    item,
                                                  ),
                                            )
                                            .toList();
                                        final normalizedSize = selectedSize!
                                            .trim()
                                            .toLowerCase();
                                        var matched = false;
                                        final updatedItems = storedItems.map((
                                          entry,
                                        ) {
                                          final entryName =
                                              entry['name']
                                                  ?.toString()
                                                  .trim() ??
                                              '';
                                          final entryVariant =
                                              entry['variant']
                                                  ?.toString()
                                                  .trim() ??
                                              '';
                                          final entrySize =
                                              entry['size']
                                                  ?.toString()
                                                  .trim() ??
                                              '';
                                          if (entryName.toLowerCase() !=
                                                  normalizedSize &&
                                              entryVariant.toLowerCase() !=
                                                  normalizedSize &&
                                              entrySize.toLowerCase() !=
                                                  normalizedSize) {
                                            return entry;
                                          }
                                          matched = true;
                                          final hasStockField = entry
                                              .containsKey('stock');
                                          final hasStartingStockField = entry
                                              .containsKey('startingStock');
                                          final hasAssignedStockField = entry
                                              .containsKey(
                                                'assignedStartingStock',
                                              );
                                          final current = _parseInt(
                                            hasStockField
                                                ? entry['stock']
                                                : hasStartingStockField
                                                ? entry['startingStock']
                                                : hasAssignedStockField
                                                ? entry['assignedStartingStock']
                                                : quantity,
                                          );
                                          if (quantity > current) {
                                            throw StateError(
                                              'Not enough stock for $selectedSize.',
                                            );
                                          }
                                          return {
                                            ...entry,
                                            'stock': current - quantity,
                                          };
                                        }).toList();
                                        if (!matched) {
                                          throw StateError(
                                            'Selected coffee size was not found in inventory.',
                                          );
                                        }

                                        final batch = FirebaseFirestore.instance
                                            .batch();
                                        batch.update(docRef, {
                                          inventoryField: updatedItems,
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                        final historyRef = FirebaseFirestore
                                            .instance
                                            .collection('stock_adjustments')
                                            .doc();
                                        batch.set(historyRef, {
                                          'type': 'coffee_void',
                                          'categoryId': sourceDocId,
                                          'categoryName': coffeeName,
                                          'coffeeId':
                                              category['coffeeId']
                                                  ?.toString() ??
                                              '',
                                          'itemName': coffeeName,
                                          'variant': selectedSize,
                                          'quantity': quantity,
                                          'unitPrice': _parsePrice(
                                            selectedItem['price'],
                                          ),
                                          'reason': reason,
                                          'comment': selectedReason == 'Other'
                                              ? commentController.text.trim()
                                              : '',
                                          'userId': FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid,
                                          'staffId': FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid,
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                        await batch.commit().timeout(
                                          const Duration(seconds: 15),
                                          onTimeout: () => throw TimeoutException(
                                            'Saving took too long. Please check your connection and try again.',
                                          ),
                                        );
                                        if (!mounted) return;
                                        Navigator.pop(context);
                                        showTopNotification(
                                          context,
                                          'Coffee item voided successfully!',
                                        );
                                      } catch (error) {
                                        if (mounted) {
                                          setState(() => isSaving = false);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            _buildSnackBar(
                                              'Failed to void coffee item: $error',
                                              isError: true,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC2105C),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Proceed Void'),
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
      ),
    );
    quantityController.dispose();
    commentController.dispose();
  }

  Future<void> _showCoffeeVoidHistory(Map<String, dynamic> category) async {
    final sourceDocId = category['sourceDocId']?.toString() ?? '';
    final coffeeName = category['categoryName']?.toString() ?? 'Coffee';
    var historySearch = '';
    DateTime? historyDate = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    color: const Color(0xFFC2105C),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Coffee History',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (value) => setDialogState(
                              () => historySearch = value.trim().toLowerCase(),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search coffee, ID, price, reason, date',
                              prefixIcon: const Icon(Icons.search_rounded),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFFFF0F5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: historyDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => historyDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month_rounded),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: historySearch.isEmpty,
                            onSelected: (_) =>
                                setDialogState(() => historySearch = ''),
                          ),
                          ChoiceChip(
                            label: Text(coffeeName),
                            selected: historySearch == coffeeName.toLowerCase(),
                            onSelected: (_) => setDialogState(
                              () => historySearch = coffeeName.toLowerCase(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('stock_adjustments')
                          .where('categoryId', isEqualTo: sourceDocId)
                          .get(),
                      builder: (context, snapshot) {
                        final docs =
                            (snapshot.data?.docs ?? [])
                                .where(
                                  (doc) =>
                                      (doc.data()
                                          as Map<String, dynamic>?)?['type'] ==
                                      'coffee_void',
                                )
                                .where((doc) {
                                  final data = doc.data() as Map<String, dynamic>?;
                                  final timestamp = data?['createdAt'] as Timestamp?;
                                  if (historyDate != null && timestamp != null) {
                                    final date = timestamp.toDate().toLocal();
                                    final startOfDay = DateTime(
                                      historyDate!.year,
                                      historyDate!.month,
                                      historyDate!.day,
                                    );
                                    final endOfDay = startOfDay
                                        .add(const Duration(days: 1))
                                        .subtract(const Duration(microseconds: 1));
                                    if (date.isBefore(startOfDay) ||
                                        date.isAfter(endOfDay)) {
                                      return false;
                                    }
                                  }
                                  if (historySearch.isEmpty) return true;
                                  final createdAtDate = timestamp?.toDate().toLocal();
                                  final formattedDate = createdAtDate == null
                                      ? ''
                                      : '${createdAtDate.year.toString().padLeft(4, '0')}-${createdAtDate.month.toString().padLeft(2, '0')}-${createdAtDate.day.toString().padLeft(2, '0')} ${createdAtDate.hour.toString().padLeft(2, '0')}:${createdAtDate.minute.toString().padLeft(2, '0')}:${createdAtDate.second.toString().padLeft(2, '0')}';
                                  final searchText = [
                                    data?['itemName']?.toString() ?? '',
                                    data?['coffeeId']?.toString() ?? '',
                                    data?['variant']?.toString() ?? '',
                                    data?['unitPrice']?.toString() ?? '',
                                    data?['reason']?.toString() ?? '',
                                    data?['comment']?.toString() ?? '',
                                    data?['categoryName']?.toString() ?? '',
                                    formattedDate,
                                    createdAtDate == null
                                        ? ''
                                        : '${createdAtDate.day.toString().padLeft(2, '0')}/${createdAtDate.month.toString().padLeft(2, '0')}/${createdAtDate.year}',
                                    createdAtDate == null
                                        ? ''
                                        : '${createdAtDate.month}/${createdAtDate.day}/${createdAtDate.year}',
                                    createdAtDate == null
                                        ? ''
                                        : '${createdAtDate.day} ${_monthName(createdAtDate.month)} ${createdAtDate.year}',
                                    createdAtDate == null
                                        ? ''
                                        : '${_monthName(createdAtDate.month)} ${createdAtDate.day}, ${createdAtDate.year}',
                                  ].join(' ').toLowerCase();
                                  return searchText.contains(historySearch);
                                })
                                .toList()
                              ..sort((a, b) {
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
                        if (snapshot.connectionState == ConnectionState.waiting)
                          return const Center(child: CircularProgressIndicator());
                        if (docs.isEmpty)
                          return const Center(
                            child: Text(
                              'No voided coffee items yet.',
                              style: TextStyle(color: Color(0xFFAD1457)),
                            ),
                          );
                        return ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data = docs[index].data() as Map<String, dynamic>;
                            final quantity = data['quantity']?.toString() ?? '0';
                            final variant = data['variant']?.toString() ?? '';
                            final itemName =
                                data['itemName']?.toString() ?? coffeeName;
                            final coffeeId =
                                data['coffeeId']?.toString() ??
                                category['coffeeId']?.toString() ??
                                '';
                            final reason = data['reason']?.toString() ?? '';
                            final comment = data['comment']?.toString() ?? '';
                            final timestamp = data['createdAt'] as Timestamp?;
                            final when = timestamp?.toDate();
                            final dateLabel = when == null
                                ? 'Unknown date'
                                : '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:${when.second.toString().padLeft(2, '0')}';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0F5),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFF8BBD0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3CD),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFFFD166),
                                      ),
                                    ),
                                    child: const Text(
                                      'Coffee',
                                      style: TextStyle(
                                        color: Color(0xFF9A6700),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              itemName,
                                              style: const TextStyle(
                                                color: Color(0xFFC2105C),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            if (coffeeId.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE8F5E9),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(0xFF81C784),
                                                  ),
                                                ),
                                                child: Text(
                                                  'ID: $coffeeId',
                                                  style: const TextStyle(
                                                    color: Color(0xFF2E7D32),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (variant.isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFCE4EC),
                                            borderRadius: BorderRadius.circular(9),
                                            border: Border.all(
                                              color: const Color(0xFFF48FB1),
                                            ),
                                          ),
                                          child: Text(
                                            variant,
                                            style: const TextStyle(
                                              color: Color(0xFFAD1457),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
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
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Price: PHP ${_parsePrice(data['unitPrice']).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFFAD1457),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
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
                                  _HistoryDetailRow(
                                    icon: Icons.calendar_today_outlined,
                                    label: dateLabel,
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
      ),
    );
  }

  Future<void> _showBundleItemsDialog(Map<String, dynamic> bundle) async {
    final bundleName = bundle['name']?.toString() ?? 'Bundle';
    final bundlePrice = _parsePrice(bundle['price']);
    final bundleId = bundle['bundleId']?.toString() ?? '';
    final bundleInstances = _bundleInstancesFromData(bundle);
    final availableBundleInstances = bundleInstances.where((instance) {
      final status =
          instance['status']?.toString().trim().toLowerCase() ?? 'available';
      return status == 'available';
    }).toList();
    var bundleSearch = '';
    var selectedBundleFilter = '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final normalizedBundleSearch = bundleSearch.trim().toLowerCase();
            final filteredBundleInstances = availableBundleInstances.where((instance) {
              final index = availableBundleInstances.indexOf(instance);
              final instanceId =
                  instance['id']?.toString() ??
                  _bundleInstanceId(bundleId, index);
              final itemNames = (instance['items'] as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .map((item) => item['name']?.toString() ?? '')
                  .where((name) => name.isNotEmpty)
                  .join(' ');
              final haystack = [
                bundleName,
                bundleId,
                instanceId,
                bundlePrice.toStringAsFixed(2),
                itemNames,
              ].join(' ').toLowerCase();

              if (selectedBundleFilter.isNotEmpty &&
                  selectedBundleFilter != bundleName) {
                return false;
              }

              if (normalizedBundleSearch.isEmpty) {
                return true;
              }

              return haystack.contains(normalizedBundleSearch);
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
                child: Container(
                  width: double.infinity,
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
                              child: Text(
                                'All Bundle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: TextField(
                          onChanged: (value) => setDialogState(
                            () => bundleSearch = value.trim().toLowerCase(),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search bundle, ID, price, items',
                            prefixIcon: const Icon(Icons.search_rounded),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFFFF0F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('All'),
                                selected: selectedBundleFilter.isEmpty,
                                onSelected: (_) => setDialogState(
                                  () => selectedBundleFilter = '',
                                ),
                              ),
                              ChoiceChip(
                                label: Text(bundleName),
                                selected: selectedBundleFilter == bundleName,
                                onSelected: (_) => setDialogState(
                                  () => selectedBundleFilter = bundleName,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Flexible(
                        child: filteredBundleInstances.isEmpty
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
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  16,
                                ),
                                itemCount: filteredBundleInstances.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final instance = filteredBundleInstances[index];
                                  final items =
                                      instance['items'] as List<dynamic>? ?? [];
                                  final instanceId =
                                      instance['id']?.toString() ??
                                      _bundleInstanceId(bundleId, index);

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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
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
                                                          instanceId,
                                                          style: const TextStyle(
                                                            color: Color(
                                                              0xFF4A0020,
                                                            ),
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Copy bundle ID',
                                                        visualDensity:
                                                            VisualDensity.compact,
                                                        onPressed: () async {
                                                          await Clipboard.setData(
                                                            ClipboardData(
                                                              text: instanceId,
                                                            ),
                                                          );
                                                          if (!context.mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            _buildSnackBar(
                                                              'Bundle ID copied',
                                                            ),
                                                          );
                                                        },
                                                        icon: const Icon(
                                                          Icons.copy_rounded,
                                                          size: 17,
                                                        ),
                                                        color: const Color(
                                                          0xFFC2105C,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Bundle price: ₱${bundlePrice.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      color: Color(0xFFAD1457),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _ItemTag(
                                              icon: Icons.check_circle_rounded,
                                              label: 'Available',
                                              bgColor: const Color(
                                                0xFFE8F5E9,
                                              ),
                                              textColor: const Color(
                                                0xFF2E7D32,
                                              ),
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
                                                item['name']?.toString() ??
                                                    'Item';
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      itemName,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF4A0020,
                                                        ),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
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
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _showBundleReductionDialog(Map<String, dynamic> bundle) async {
    final bundleIdController = TextEditingController();
    final commentController = TextEditingController();
    final selectedBundleIds = <String>[];
    String? selectedReason;
    String? validationMessage;
    bool isSaving = false;
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
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFC2105C),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.remove_circle_outline_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Reduce Bundle',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                              color: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      _InfoChip(
                        icon: Icons.inventory_2_rounded,
                        label: '$bundleName - Bundle stock: $currentStock',
                        color: const Color(0xFFC2105C),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _PinkTextField(
                              controller: bundleIdController,
                              label: 'Bundle ID',
                              hint: 'e.g. 13000 113-001',
                              icon: Icons.confirmation_number_outlined,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Add bundle ID',
                            onPressed: () {
                              final enteredId = bundleIdController.text.trim();
                              final instances = _bundleInstancesFromData(
                                bundle,
                              );
                              final matchingIndex = instances.indexWhere((
                                instance,
                              ) {
                                final index = instances.indexOf(instance);
                                final instanceId =
                                    instance['id']?.toString().trim() ??
                                    _bundleInstanceId(
                                      bundle['bundleId']?.toString() ?? '',
                                      index,
                                    );
                                return instanceId == enteredId;
                              });
                              final status = matchingIndex < 0
                                  ? ''
                                  : instances[matchingIndex]['status']
                                            ?.toString()
                                            .trim()
                                            .toLowerCase() ??
                                        'available';
                              if (enteredId.isEmpty ||
                                  matchingIndex < 0 ||
                                  status != 'available') {
                                setDialogState(() {
                                  validationMessage =
                                      'Invalid bundle ID number.';
                                });
                                return;
                              }
                              if (selectedBundleIds.contains(enteredId)) {
                                setDialogState(() {
                                  validationMessage =
                                      'Bundle ID already added.';
                                });
                                return;
                              }
                              setDialogState(() {
                                selectedBundleIds.add(enteredId);
                                bundleIdController.clear();
                                validationMessage = null;
                              });
                            },
                            icon: const Icon(Icons.add_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFC2105C),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      if (selectedBundleIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: selectedBundleIds.map((id) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                  label: Text(id),
                                  deleteIcon: const Icon(Icons.close, size: 15),
                                  onDeleted: () => setDialogState(
                                    () => selectedBundleIds.remove(id),
                                  ),
                                  backgroundColor: const Color(0xFFE8F5E9),
                                  side: const BorderSide(
                                    color: Color(0xFF81C784),
                                  ),
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      if (validationMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          validationMessage!,
                          style: const TextStyle(
                            color: Color(0xFFC62828),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedReason,
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
                      if (selectedReason == 'Other') ...[
                        const SizedBox(height: 12),
                        _PinkTextField(
                          controller: commentController,
                          label: 'Comment',
                          hint: 'Optional note',
                          icon: Icons.notes_rounded,
                          maxLines: 2,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final reason = selectedReason?.trim() ?? '';
                                  final instances = _bundleInstancesFromData(
                                    bundle,
                                  );
                                  if (selectedBundleIds.isEmpty) {
                                    setDialogState(() {
                                      validationMessage =
                                          'Invalid Bundle ID number.';
                                    });
                                    return;
                                  }
                                  if (reason.isEmpty) {
                                    setDialogState(
                                      () => validationMessage =
                                          'Please select a reason.',
                                    );
                                    return;
                                  }

                                  setDialogState(() {
                                    isSaving = true;
                                    validationMessage = null;
                                  });

                                  try {
                                    for (final selectedId
                                        in selectedBundleIds) {
                                      final instanceIndex = instances
                                          .indexWhere((instance) {
                                            final index = instances.indexOf(
                                              instance,
                                            );
                                            final instanceId =
                                                instance['id']
                                                    ?.toString()
                                                    .trim() ??
                                                _bundleInstanceId(
                                                  bundle['bundleId']
                                                          ?.toString() ??
                                                      '',
                                                  index,
                                                );
                                            return instanceId == selectedId;
                                          });
                                      if (instanceIndex < 0) {
                                        throw StateError(
                                          'One selected bundle ID is no longer available.',
                                        );
                                      }
                                      final instance = instances[instanceIndex];
                                      instances[instanceIndex] = {
                                        ...instance,
                                        'status': 'reduced',
                                        'reductionReason': reason,
                                        'reductionComment':
                                            selectedReason == 'Other'
                                            ? commentController.text.trim()
                                            : '',
                                        'reducedAt': Timestamp.now(),
                                      };
                                    }

                                    final user =
                                        FirebaseAuth.instance.currentUser;
                                    final docRef = FirebaseFirestore.instance
                                        .collection('staff_inventory')
                                        .doc(sourceDocId);
                                    final batch = FirebaseFirestore.instance
                                        .batch();
                                    batch.update(docRef, {
                                      'bundleInstances': instances,
                                      'bundleCount':
                                          currentStock -
                                          selectedBundleIds.length,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    });
                                    final historyRef = FirebaseFirestore
                                        .instance
                                        .collection('stock_adjustments')
                                        .doc();
                                    batch.set(historyRef, {
                                      'type': 'bundle_stock_adjustment',
                                      'userId': user?.uid,
                                      'staffId': user?.uid,
                                      'categoryId': sourceDocId,
                                      'categoryName': bundleName,
                                      'itemName': bundleName,
                                      'bundlePrice': _parsePrice(
                                        bundle['price'],
                                      ),
                                      'bundleInstanceIds': selectedBundleIds,
                                      'quantity': selectedBundleIds.length,
                                      'previousStock': currentStock,
                                      'newStock':
                                          currentStock -
                                          selectedBundleIds.length,
                                      'reason': reason,
                                      'comment': selectedReason == 'Other'
                                          ? commentController.text.trim()
                                          : '',
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });
                                    await batch.commit();
                                  } catch (error) {
                                    if (context.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                        validationMessage =
                                            'Failed to reduce bundle: $error';
                                      });
                                    }
                                    return;
                                  }

                                  if (!mounted) return;
                                  Navigator.pop(context);
                                  showTopNotification(
                                    context,
                                    '${selectedBundleIds.length} bundle(s) reduced successfully!',
                                  );
                                },
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          label: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Reduce Bundle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC2105C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(190, 42),
                            maximumSize: const Size(210, 42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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
    );

    bundleIdController.dispose();
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
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
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
                            'Reduce Bundle $instanceId',
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
                      initialValue: selectedReason,
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
                    if (selectedReason == 'Other') ...[
                      const SizedBox(height: 12),
                      _PinkTextField(
                        controller: commentController,
                        label: 'Comment',
                        hint: 'Optional note',
                        icon: Icons.notes_rounded,
                        maxLines: 2,
                      ),
                    ],
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
                          'reductionComment': selectedReason == 'Other'
                              ? commentController.text.trim()
                              : '',
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
                              'comment': selectedReason == 'Other'
                                  ? commentController.text.trim()
                                  : '',
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                        if (!mounted) return;
                        Navigator.pop(context);
                        showTopNotification(
                          context,
                          'Bundle reduced successfully!',
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
    final bundleItemNames = (bundle['items'] as List?)
            ?.whereType<Map>()
            .map((item) => item['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .join(' ') ??
        '';
    var historySearch = '';
    DateTime? historyDate = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bundle History',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (value) => setDialogState(
                              () => historySearch = value.trim().toLowerCase(),
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Search bundle, ID, price, reason, date',
                              prefixIcon: const Icon(Icons.search_rounded),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFFFF0F5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: historyDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => historyDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month_rounded),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: historySearch.isEmpty,
                            onSelected: (_) =>
                                setDialogState(() => historySearch = ''),
                          ),
                          ChoiceChip(
                            label: Text(bundleName),
                            selected: historySearch == bundleName.toLowerCase(),
                            onSelected: (_) => setDialogState(
                              () => historySearch = bundleName.toLowerCase(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('stock_adjustments')
                          .where('categoryId', isEqualTo: sourceDocId)
                          .get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFC2105C),
                            ),
                          );
                        }
                        final docs =
                            (snapshot.data?.docs ?? []).where((doc) {
                              final data = doc.data() as Map<String, dynamic>?;
                              if (data?['type'] != 'bundle_stock_adjustment') {
                                return false;
                              }
                              final timestamp =
                                  data?['createdAt'] as Timestamp?;
                              if (historyDate != null && timestamp != null) {
                                final date = timestamp.toDate().toLocal();
                                final startOfDay = DateTime(
                                  historyDate!.year,
                                  historyDate!.month,
                                  historyDate!.day,
                                );
                                final endOfDay = startOfDay
                                    .add(const Duration(days: 1))
                                    .subtract(const Duration(microseconds: 1));
                                if (date.isBefore(startOfDay) ||
                                    date.isAfter(endOfDay)) {
                                  return false;
                                }
                              }
                              if (historySearch.isEmpty) return true;
                              final createdAtDate = timestamp?.toDate().toLocal();
                              final formattedDate = createdAtDate == null
                                  ? ''
                                  : '${createdAtDate.year.toString().padLeft(4, '0')}-${createdAtDate.month.toString().padLeft(2, '0')}-${createdAtDate.day.toString().padLeft(2, '0')} ${createdAtDate.hour.toString().padLeft(2, '0')}:${createdAtDate.minute.toString().padLeft(2, '0')}:${createdAtDate.second.toString().padLeft(2, '0')}';
                              return [
                                data?['categoryName']?.toString() ?? '',
                                data?['bundleInstanceId']?.toString() ?? '',
                                (data?['bundleInstanceIds'] as List?)?.join(
                                      ' ',
                                    ) ??
                                    '',
                                data?['bundlePrice']?.toString() ?? '',
                                data?['reason']?.toString() ?? '',
                                formattedDate,
                                createdAtDate == null
                                    ? ''
                                    : '${createdAtDate.day.toString().padLeft(2, '0')}/${createdAtDate.month.toString().padLeft(2, '0')}/${createdAtDate.year}',
                                createdAtDate == null
                                    ? ''
                                    : '${createdAtDate.month}/${createdAtDate.day}/${createdAtDate.year}',
                                createdAtDate == null
                                    ? ''
                                    : '${createdAtDate.day} ${_monthName(createdAtDate.month)} ${createdAtDate.year}',
                                createdAtDate == null
                                    ? ''
                                    : '${_monthName(createdAtDate.month)} ${createdAtDate.day}, ${createdAtDate.year}',
                              ].join(' ').toLowerCase().contains(historySearch);
                            }).toList()..sort((a, b) {
                              final aData = a.data() as Map<String, dynamic>?;
                              final bData = b.data() as Map<String, dynamic>?;
                              final aTime =
                                  (aData?['createdAt'] as Timestamp?)
                                      ?.toDate() ??
                                  DateTime.fromMillisecondsSinceEpoch(0);
                              final bTime =
                                  (bData?['createdAt'] as Timestamp?)
                                      ?.toDate() ??
                                  DateTime.fromMillisecondsSinceEpoch(0);
                              return bTime.compareTo(aTime);
                            });
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text('No bundle reductions yet.'),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data =
                                docs[index].data() as Map<String, dynamic>;
                            final timestamp = data['createdAt'] as Timestamp?;
                            final reducedOn = timestamp?.toDate();
                            final reducedOnLabel = reducedOn == null
                                ? 'Unknown date'
                                : '${reducedOn.year.toString().padLeft(4, '0')}-${reducedOn.month.toString().padLeft(2, '0')}-${reducedOn.day.toString().padLeft(2, '0')} ${reducedOn.hour.toString().padLeft(2, '0')}:${reducedOn.minute.toString().padLeft(2, '0')}';
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3CD),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFFFD166),
                                      ),
                                    ),
                                    child: Text(
                                      bundleName,
                                      style: const TextStyle(
                                        color: Color(0xFF9A6700),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if ((data['bundleInstanceIds'] is List &&
                                          (data['bundleInstanceIds'] as List)
                                              .isNotEmpty) ||
                                      (data['bundleInstanceId']?.toString() ??
                                              '')
                                          .isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Text(
                                          'Bundle ID:',
                                          style: TextStyle(
                                            color: Color(0xFF4A0020),
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                ...((data['bundleInstanceIds']
                                                            is List)
                                                        ? (data['bundleInstanceIds']
                                                              as List)
                                                        : [data['bundleInstanceId']])
                                                    .where((id) => id != null)
                                                    .map(
                                                      (id) => Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              right: 6,
                                                            ),
                                                        child: Chip(
                                                          label: Text(
                                                            id.toString(),
                                                          ),
                                                          backgroundColor:
                                                              const Color(
                                                                0xFFE8F5E9,
                                                              ),
                                                          labelStyle:
                                                              const TextStyle(
                                                                color: Color(
                                                                  0xFF2E7D32,
                                                                ),
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFC2105C),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          child: const Text(
                                            '-1',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    'Bundle price: PHP ${_parsePrice(data['bundlePrice'] ?? bundle['price']).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFFAD1457),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Reason: ${data['reason'] ?? ''}',
                                    style: const TextStyle(
                                      color: Color(0xFFAD1457),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Reduced on: $reducedOnLabel',
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
      ),
    );
  }

  Widget _buildInventoryToggle({
    required int categoryCount,
    required int bundleCount,
    required int coffeeCount,
    required int addonCount,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
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
                Flexible(
                  child: Text(
                    '$label ($count)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF8B0035),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
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
            selected: _showCategories && !_showCoffee && !_showAddons,
            label: 'Categories',
            count: categoryCount,
            icon: Icons.grid_view_rounded,
            onTap: () => setState(() {
              _showCategories = true;
              _showCoffee = false;
              _showAddons = false;
              _selectedTableCategoryKey = null;
            }),
          ),
          const SizedBox(width: 8),
          option(
            selected: !_showCategories && !_showCoffee && !_showAddons,
            label: 'Bundle',
            count: bundleCount,
            icon: Icons.inventory_2_rounded,
            onTap: () => setState(() {
              _showCategories = false;
              _showCoffee = false;
              _showAddons = false;
              _selectedTableCategoryKey = null;
            }),
          ),
          const SizedBox(width: 8),
          option(
            selected: _showCoffee,
            label: 'Coffee',
            count: coffeeCount,
            icon: Icons.local_cafe_rounded,
            onTap: () => setState(() {
              _showCategories = false;
              _showCoffee = true;
              _showAddons = false;
              _selectedTableCategoryKey = null;
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

  Widget _buildInventoryLoadingState() {
    Widget bar(double width) => Container(
      width: width,
      height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFFF8BBD0),
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      itemBuilder: (_, index) => Container(
        height: 112,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF8BBD0)),
        ),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4EE),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [bar(150), const SizedBox(height: 12), bar(95)],
            ),
          ],
        ),
      ),
    );
  }

  DataColumn _tableColumn(String label) {
    return DataColumn(
      label: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8B0035),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  DataCell _tableCell(
    String value, {
    double width = 120,
    FontWeight weight = FontWeight.w700,
    Color color = const Color(0xFF1A0A10),
  }) {
    return DataCell(
      SizedBox(
        width: width,
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: weight, color: color),
        ),
      ),
    );
  }

  Widget _tableBlock({
    required String title,
    required List<DataColumn> columns,
    required List<DataRow> rows,
    String? subtitle,
    VoidCallback? onView,
    VoidCallback? onAddons,
    VoidCallback? onHistory,
    bool compact = false,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF8BBD0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC2105C).withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8B0035),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if ((subtitle ?? '').isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFF8B0035).withOpacity(0.62),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onView != null)
                  IconButton(
                    tooltip: 'View bundle items',
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_rounded),
                    color: const Color(0xFFC2105C),
                  ),
                if (onAddons != null)
                  TextButton.icon(
                    onPressed: onAddons,
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                    ),
                    label: const Text('View add-ons'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC2105C),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (onHistory != null)
                  IconButton(
                    tooltip: 'History',
                    onPressed: onHistory,
                    icon: const Icon(Icons.history_rounded),
                    color: const Color(0xFFC2105C),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    const Color(0xFFC2105C).withOpacity(0.08),
                  ),
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 70,
                  columnSpacing: compact ? 10 : 22,
                  horizontalMargin: compact ? 10 : 18,
                  columns: columns,
                  rows: rows,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayItemId(Map<String, dynamic> item, {String? fallback}) {
    for (final key in ['id', 'itemId', 'variantId', 'sourceItemId']) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    final safeFallback = fallback?.trim() ?? '';
    return safeFallback.isNotEmpty ? safeFallback : '--';
  }

  Widget _tableReduceButton({
    required bool enabled,
    required VoidCallback onPressed,
    String label = 'Reduce',
  }) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
      label: Text(enabled ? label : 'Unavailable'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFC2105C),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildBundleList(List<Map<String, dynamic>> bundleDocs) {
    if (bundleDocs.isEmpty) {
      return _buildEmptyInventoryState(
        icon: Icons.inventory_2_outlined,
        message: 'No bundles found.',
      );
    }

    final availableBundleCount = bundleDocs.length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _tableBlock(
          title: 'Bundles',
          subtitle: 'Available bundles: $availableBundleCount',
          onView: bundleDocs.length == 1
              ? () => _showBundleItemsDialog(bundleDocs.first)
              : null,
          onHistory: bundleDocs.length == 1
              ? () => _showBundleReductionHistory(bundleDocs.first)
              : null,
          columns: [
            _tableColumn('ID'),
            _tableColumn('Bundle Name'),
            _tableColumn('Price'),
            _tableColumn('Stock'),
            _tableColumn('Expire date'),
            _tableColumn('Action'),
          ],
          rows: bundleDocs.map((bundle) {
            final bundleName = bundle['name']?.toString() ?? 'Bundle';
            final bundleStock = _bundleStockForData(bundle);
            final bundlePrice = _parsePrice(bundle['price']);
            final bundleId = bundle['bundleId']?.toString().trim() ?? '';
            final bundleExpirationDate = _bundleExpirationDate(bundle);

            return DataRow(
              cells: [
                _tableCell(
                  bundleId.isNotEmpty
                      ? bundleId
                      : bundle['sourceDocId']?.toString() ?? '--',
                  width: 160,
                  color: const Color(0xFFC2105C),
                ),
                _tableCell(bundleName, width: 180, weight: FontWeight.w900),
                _tableCell(
                  'PHP ${bundlePrice.toStringAsFixed(2)}',
                  width: 100,
                  color: const Color(0xFF2E7D32),
                ),
                _tableCell(
                  '$bundleStock',
                  width: 70,
                  color: _stockColor(bundleStock),
                ),
                _tableCell(bundleExpirationDate, width: 120),
                DataCell(
                  _tableReduceButton(
                    enabled: bundleStock > 0,
                    onPressed: () => _showBundleReductionDialog(bundle),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCoffeeCategoryCard(Map<String, dynamic> category, int index) {
    final coffeeName = category['categoryName']?.toString() ?? 'Coffee';
    final coffeeId = category['coffeeId']?.toString() ?? '';
    final items =
        (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final addonByName = <String, Map<String, dynamic>>{};
    for (final rawAddon in (category['addonOptions'] as List?) ?? const []) {
      if (rawAddon is! Map) continue;
      final addon = Map<String, dynamic>.from(rawAddon);
      final addonName = addon['name']?.toString().trim().toLowerCase() ?? '';
      if (addonName.isNotEmpty) {
        addonByName.putIfAbsent(addonName, () => addon);
      }
    }
    final addonDocs = addonByName.values.toList();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('completed_sales').snapshots(),
      builder: (context, salesSnapshot) {
        var totalSoldFromReceipts = 0;
        for (final saleDoc in salesSnapshot.data?.docs ?? const []) {
          final sale = saleDoc.data();
          final type = sale['type']?.toString().toLowerCase() ?? 'sale';
          final status = sale['status']?.toString().toLowerCase() ?? '';
          final sign = (type == 'refund' || status == 'refund') ? -1 : 1;
          for (final raw in sale['items'] as List<dynamic>? ?? const []) {
            if (raw is! Map) continue;
            final sold = Map<String, dynamic>.from(raw);
            if (sold['isCoffee'] != true) continue;
            final soldCoffeeId = sold['coffeeId']?.toString().trim() ?? '';
            final soldName = sold['name']?.toString().trim().toLowerCase() ?? '';
            final matchesCoffee = coffeeId.isNotEmpty
                ? soldCoffeeId == coffeeId
                : soldName == coffeeName.trim().toLowerCase();
            if (matchesCoffee) {
              totalSoldFromReceipts += sign * _parseInt(sold['quantity'], fallback: 1);
            }
          }
        }
        return _AnimatedCategorySection(
      index: index,
      child: _tableBlock(
        title: 'Coffee',
        subtitle: 'Available Coffee Items: 1',
        onAddons: addonDocs.isEmpty
            ? null
            : () => _showCoffeeAddonsDialog(addonDocs, category),
        onHistory: () => _showCoffeeVoidHistory(category),
        compact: true,
        columns: [
          _tableColumn('ID'),
          _tableColumn('Coffee Name'),
          _tableColumn('Small'),
          _tableColumn('Medium'),
          _tableColumn('Large'),
          _tableColumn('Total Sold'),
          _tableColumn('Action'),
        ],
        rows: [
          if (items.isNotEmpty)
            (() {
              Map<String, dynamic>? itemForSize(String size) {
                final normalizedSize = size.toLowerCase();
                for (final item in items) {
                  final name =
                      item['name']?.toString().trim().toLowerCase() ?? '';
                  if (name.startsWith(normalizedSize)) return item;
                }
                return null;
              }

              String priceForSize(String size) {
                final item = itemForSize(size);
                return item == null
                    ? '--'
                    : 'PHP ${_parsePrice(item['price']).toStringAsFixed(2)}';
              }

              final totalSold = totalSoldFromReceipts < 0
                  ? 0
                  : totalSoldFromReceipts;

              return DataRow(
                cells: [
                  _tableCell(
                    coffeeId.isNotEmpty ? coffeeId : '--',
                    width: 105,
                    color: const Color(0xFFC2105C),
                  ),
                  _tableCell(coffeeName, width: 145, weight: FontWeight.w900),
                  _tableCell(
                    priceForSize('small'),
                    width: 88,
                    color: const Color(0xFF2E7D32),
                  ),
                  _tableCell(
                    priceForSize('medium'),
                    width: 88,
                    color: const Color(0xFF2E7D32),
                  ),
                  _tableCell(
                    priceForSize('large'),
                    width: 88,
                    color: const Color(0xFF2E7D32),
                  ),
                  _tableCell(
                    '$totalSold',
                    width: 75,
                    color: const Color(0xFF2E7D32),
                  ),
                  DataCell(
                    _tableReduceButton(
                      enabled: true,
                      label: 'Void',
                      onPressed: () => _showCoffeeVoidDialog(category),
                    ),
                  ),
                ],
              );
            })(),
        ],
      ),
        );
      },
    );
  }

  /*
  Widget _buildBundleListOld(List<Map<String, dynamic>> bundleDocs) {
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
        final bundleImage = bundle['imageUrl']?.toString();

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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: _buildInventoryImage(
                            bundleImage,
                            fallbackIcon: Icons.inventory_2_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
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
                      Row(
                        children: [
                          Expanded(
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
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
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
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
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
    final coffeeImage = category['imageUrl']?.toString();
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: _buildInventoryImage(
                              item['imageUrl']?.toString() ?? coffeeImage,
                              fallbackIcon: Icons.local_cafe_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              itemName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                                color: Color(0xFFC2105C),
                                              ),
                                            ),
                                            if ((categoryId ?? '').isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE8F5E9),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFF81C784,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  'ID: $categoryId',
                                                  style: const TextStyle(
                                                    color: Color(0xFF2E7D32),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                          ],
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

  */

  Future<void> _showCoffeeAddonsDialog(
    List<Map<String, dynamic>> addonDocs,
    Map<String, dynamic> category,
  ) async {
    var searchQuery = '';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFC2105C), Color(0xFFE91E8C)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add_circle_outline_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Coffee Add-ons',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      onChanged: (value) => setDialogState(
                        () => searchQuery = value.trim().toLowerCase(),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search add-ons',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFFC2105C),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFFFF0F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFF8BBD0),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final filteredAddons = addonDocs.where((addon) {
                          if (searchQuery.isEmpty) return true;
                          return [
                            _displayItemId(addon),
                            addon['name']?.toString() ?? '',
                            addon['status']?.toString() ?? '',
                          ].join(' ').toLowerCase().contains(searchQuery);
                        }).toList();
                        if (filteredAddons.isEmpty) {
                          return const Center(
                            child: Text(
                              'No add-ons found.',
                              style: TextStyle(color: Color(0xFFAD1457)),
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(1.1),
                              1: FlexColumnWidth(1.5),
                              2: FlexColumnWidth(1.0),
                              3: FlexColumnWidth(0.9),
                            },
                            border: TableBorder(
                              horizontalInside: BorderSide(
                                color: Color(0xFFF8BBD0),
                              ),
                            ),
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFC2105C,
                                  ).withOpacity(0.08),
                                ),
                                children: const [
                                  _AddonHeaderCell('ID'),
                                  _AddonHeaderCell('Add-on'),
                                  _AddonHeaderCell('Status'),
                                  _AddonHeaderCell('Price'),
                                ],
                              ),
                              ...filteredAddons.map((addon) {
                                final addonId = _displayItemId(addon);
                                final addonName =
                                    addon['name']?.toString() ?? 'Add-on';
                                final status =
                                    addon['status']?.toString() ??
                                    (addon['isAvailable'] == false
                                        ? 'Unavailable'
                                        : 'Available');
                                final price = _parsePrice(
                                  addon['priceDelta'] ?? addon['price'],
                                );
                                return TableRow(
                                  children: [
                                    _AddonCell(
                                      addonId,
                                      color: const Color(0xFF2E7D32),
                                    ),
                                    _AddonCell(
                                      addonName,
                                      weight: FontWeight.w800,
                                    ),
                                    _AddonCell(
                                      status,
                                      color: status.toLowerCase() == 'available'
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFC62828),
                                    ),
                                    _AddonCell(
                                      'PHP ${price.toStringAsFixed(2)}',
                                      color: const Color(0xFF2E7D32),
                                    ),
                                  ],
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
      ),
    );
  }

  Future<void> _showAddonVoidNotice(
    Map<String, dynamic> addon,
    Map<String, dynamic> category,
  ) async {
    final addonName = addon['name']?.toString() ?? 'Add-on';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void add-on?'),
        content: Text('Record $addonName as voided?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC2105C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('stock_adjustments').add({
        'type': 'addon_void',
        'categoryId': category['sourceDocId']?.toString() ?? '',
        'categoryName': category['categoryName']?.toString() ?? 'Coffee',
        'itemId': _displayItemId(addon),
        'itemName': addonName,
        'quantity': 1,
        'unitPrice': _parsePrice(addon['priceDelta'] ?? addon['price']),
        'reason': 'Voided',
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showTopNotification(context, '$addonName voided successfully!');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnackBar('Failed to void add-on: $error', isError: true),
      );
    }
  }

  Widget _buildAddonList(List<Map<String, dynamic>> addonDocs) {
    if (addonDocs.isEmpty) {
      return _buildEmptyInventoryState(
        icon: Icons.add_circle_outline_rounded,
        message: 'No add-ons assigned.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      itemCount: addonDocs.length,
      itemBuilder: (context, index) {
        final addon = addonDocs[index];
        final name = addon['name']?.toString() ?? 'Add-on';
        final price = _parsePrice(addon['priceDelta']);
        return _AnimatedItemCard(
          delay: Duration(milliseconds: 100 + index * 60),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFF8BBD0).withOpacity(0.8),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFFC2105C),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A0A10),
                    ),
                  ),
                ),
                _ItemTag(
                  icon: Icons.payments_outlined,
                  label: '+₱${price.toStringAsFixed(0)}',
                  bgColor: const Color(0xFFFCE4EC),
                  textColor: const Color(0xFFAD1457),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTable(Map<String, dynamic> category, int index) {
    final categoryName = category['categoryName']?.toString() ?? 'Unknown';
    final items =
        (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return _AnimatedCategorySection(
      index: index,
      child: _tableBlock(
        title: categoryName,
        subtitle: 'Available items: ${items.length}',
        onHistory: () => _showStockAdjustmentHistory(
          categoryName: categoryName,
          categoryId:
              category['categoryId']?.toString() ??
              (items.isNotEmpty
                  ? items.first['sourceDocId']?.toString()
                  : null),
          itemIds: {
            for (final item in items)
              '${item['name']?.toString().toLowerCase() ?? ''}|${item['variant']?.toString().toLowerCase() ?? ''}':
                  _displayItemId(item),
          },
        ),
        columns: [
          _tableColumn('ID'),
          _tableColumn('Items Name'),
          _tableColumn('Price'),
          _tableColumn('Stock'),
          _tableColumn('Expire date'),
          _tableColumn('Action'),
        ],
        rows: items.map((item) {
          final itemStock = _stockForItem(item);
          return DataRow(
            cells: [
              _tableCell(
                _displayItemId(
                  item,
                  fallback:
                      item['sourceDocId']?.toString() ??
                      category['categoryId']?.toString(),
                ),
                width: 140,
                color: const Color(0xFFC2105C),
              ),
              _tableCell(
                item['name']?.toString() ?? 'Item',
                width: 180,
                weight: FontWeight.w900,
              ),
              _tableCell(
                'PHP ${_parsePrice(item['price']).toStringAsFixed(2)}',
                width: 100,
                color: const Color(0xFF2E7D32),
              ),
              _tableCell(
                '$itemStock',
                width: 70,
                color: _stockColor(itemStock),
              ),
              _tableCell(
                item['expirationDate']?.toString().trim().isNotEmpty == true
                    ? item['expirationDate'].toString()
                    : '--',
                width: 120,
              ),
              DataCell(
                _tableReduceButton(
                  enabled: itemStock > 0,
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
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryList(
    List<Map<String, dynamic>> categoryDocs, {
    String emptyMessage = 'No items found.',
  }) {
    if (categoryDocs.isEmpty) {
      return _buildEmptyInventoryState(
        icon: Icons.category_outlined,
        message: emptyMessage,
      );
    }

    if (!_isFilteredCategory &&
        categoryDocs.every((category) => category['isCoffee'] != true)) {
      final selectedKey =
          _selectedTableCategoryKey ??
          (categoryDocs.isNotEmpty
              ? (categoryDocs.first['categoryId']?.toString() ??
                    categoryDocs.first['categoryName']?.toString() ??
                    '')
              : '');
      final selectedCategory = categoryDocs.firstWhere((category) {
        final key =
            category['categoryId']?.toString() ??
            category['categoryName']?.toString() ??
            '';
        return key == selectedKey;
      }, orElse: () => categoryDocs.first);

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
        children: [
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categoryDocs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final selected = _showAllCategoryItems;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() {
                        _showAllCategoryItems = true;
                        _selectedTableCategoryKey = '__all__';
                      }),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        constraints: const BoxConstraints(minWidth: 88),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFC2105C)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFC2105C)
                                : const Color(0xFFF8BBD0),
                            width: 1.3,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apps_rounded,
                              size: 16,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFFC2105C),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'All',
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF8B0035),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final category = categoryDocs[index - 1];
                final categoryName =
                    category['categoryName']?.toString() ?? 'Unknown';
                final categoryKey =
                    category['categoryId']?.toString() ?? categoryName;
                final selected =
                    !_showAllCategoryItems &&
                    categoryKey ==
                        (selectedCategory['categoryId']?.toString() ??
                            selectedCategory['categoryName']?.toString() ??
                            '');
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() {
                      _showAllCategoryItems = false;
                      _selectedTableCategoryKey = categoryKey;
                    }),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      constraints: const BoxConstraints(minWidth: 128),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFC2105C)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFC2105C)
                              : const Color(0xFFF8BBD0),
                          width: 1.3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFC2105C,
                            ).withOpacity(selected ? 0.16 : 0.06),
                            blurRadius: selected ? 14 : 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.category_rounded,
                            size: 16,
                            color: selected
                                ? Colors.white
                                : const Color(0xFFC2105C),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              categoryName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF8B0035),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          if (_showAllCategoryItems)
            ...categoryDocs.asMap().entries.map(
              (entry) => _buildCategoryTable(entry.value, entry.key),
            )
          else
            _buildCategoryTable(selectedCategory, 0),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      itemCount: categoryDocs.length,
      itemBuilder: (context, index) {
        final category = categoryDocs[index];
        if (category['isCoffee'] == true) {
          return _buildCoffeeCategoryCard(category, index);
        }
        final categoryName = category['categoryName']?.toString() ?? 'Unknown';
        final categoryId = category['categoryId']?.toString() ?? '';
        final categoryImage = category['imageUrl']?.toString();
        final items =
            (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final categoryLabel = _brandCategory(categoryName);
        return _buildCategoryTable(category, index);

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
                          if (categoryId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ID: $categoryId',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showStockAdjustmentHistory(
                        categoryName: categoryName,
                        categoryId: categoryId,
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
                final itemImage = item['imageUrl']?.toString() ?? categoryImage;

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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 76,
                              height: 76,
                              child: _buildInventoryImage(itemImage),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                                    if ((item['id']?.toString() ?? '')
                                        .isNotEmpty)
                                      _ItemTag(
                                        icon:
                                            Icons.confirmation_number_outlined,
                                        label: 'ID: ${item['id']}',
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
                            onPressed: itemStock > 0
                                ? () {
                                    _showStockAdjustmentDialog(
                                      categoryName: categoryName,
                                      sourceDocId:
                                          item['sourceDocId']?.toString() ??
                                          category['categoryId']?.toString() ??
                                          '',
                                      item: item,
                                      currentStock: itemStock,
                                    );
                                  }
                                : null,
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 20,
                            ),
                            label: Text(
                              itemStock > 0 ? 'Reduce' : 'Unavailable',
                            ),
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
            automaticallyImplyLeading: false,
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
                                    : 'Inventory',
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
            leadingWidth: widget.embedded ? 0 : 72,
            leading: widget.embedded
                ? null
                : IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      minHeight: 56,
                    ),
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
              return _buildInventoryLoadingState();
            }

            final docs = snapshot.data?.docs ?? [];
            return StreamBuilder<QuerySnapshot>(
              stream: _rootInventoryStream,
              builder: (context, rootSnapshot) {
                if (rootSnapshot.connectionState == ConnectionState.waiting) {
                  return _buildInventoryLoadingState();
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
                  if (rootName.isNotEmpty) {
                    activeRootByName[rootName] = rootData;
                  }
                }

                String itemKey(Map<String, dynamic> item) =>
                    '${item['name'] ?? ''}|${item['price'] ?? ''}'
                        .toLowerCase();

                final visibleDocs = <Map<String, dynamic>>[];
                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null || data['isDeleted'] == true) continue;
                  if (data['isAddon'] == true) {
                    visibleDocs.add({...data, 'sourceDocId': doc.id});
                    continue;
                  }
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
                    final coffeeItems = _coffeeItemsFromData(
                      data,
                      rootData: rootData,
                    );
                    if (coffeeItems.isEmpty) continue;
                    visibleDocs.add({
                      ...data,
                      'name': data['name'] ?? 'Coffee',
                      'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                      'items': coffeeItems,
                      'addonOptions': coffeeItems
                          .expand(
                            (item) => item['addons'] as List<dynamic>? ?? [],
                          )
                          .whereType<Map>()
                          .map((addon) => Map<String, dynamic>.from(addon))
                          .toList(),
                      'sourceDocId': doc.id,
                      'isCoffee': true,
                    });
                    continue;
                  }

                  if (data['isBundle'] == true) {
                    if (rootData['isBundle'] != true) continue;
                    if (_hasExpiredBundleItem(rootData)) continue;
                    if (_hasExpiredBundleItem(data)) continue;
                    if (_bundleStockForData(data) <= 0) continue;
                    visibleDocs.add({
                      ...data,
                      'name': rootData['name'] ?? data['name'],
                      'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                      'sourceDocId': doc.id,
                    });
                    continue;
                  }

                  final rootItems =
                      ((rootData['items'] as List<dynamic>?) ?? [])
                          .whereType<Map>()
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();
                  final rootKeys = rootItems.map(itemKey).toSet();
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
                  if (data['isBundle'] == true || data['isAddon'] == true) {
                    continue;
                  }
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
                    'categoryId':
                        data['sourceInventoryId']
                                ?.toString()
                                .trim()
                                .isNotEmpty ==
                            true
                        ? data['sourceInventoryId']
                        : data['sourceDocId'],
                    'imageUrl': data['imageUrl'],
                    'items': itemRecords,
                    'addonOptions': data['addonOptions'] ?? const [],
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
                final addonByName = <String, Map<String, dynamic>>{};
                for (final data in visibleDocs) {
                  if (data['isAddon'] == true) {
                    final name = data['name']?.toString().trim() ?? '';
                    if (name.isEmpty) continue;
                    addonByName.putIfAbsent(name, () => data);
                    continue;
                  }
                  for (final addon
                      in (data['addonOptions'] as List<dynamic>? ?? [])
                          .whereType<Map>()) {
                    final name = addon['name']?.toString().trim() ?? '';
                    if (name.isEmpty) continue;
                    addonByName.putIfAbsent(name, () {
                      final addonData = Map<String, dynamic>.from(addon);
                      addonData['isAddon'] = true;
                      addonData['sourceDocId'] = data['sourceDocId'];
                      return addonData;
                    });
                  }
                }
                final addonDocs = addonByName.values.toList();

                bool matchesVisibleFields(Map<String, dynamic> data) {
                  final query = _tableSearchQuery.trim().toLowerCase();
                  if (query.isEmpty) return true;
                  final visibleValues = <String>[
                    data['id']?.toString() ?? '',
                    data['itemId']?.toString() ?? '',
                    data['variantId']?.toString() ?? '',
                    data['coffeeId']?.toString() ?? '',
                    data['name']?.toString() ?? '',
                    data['price']?.toString() ?? '',
                    data['stock']?.toString() ?? '',
                    data['startingStock']?.toString() ?? '',
                    data['expirationDate']?.toString() ?? '',
                    data['expiryDate']?.toString() ?? '',
                  ].join(' ').toLowerCase();
                  return visibleValues.contains(query);
                }

                List<Map<String, dynamic>> searchedCategoryData(
                  List<Map<String, dynamic>> docs,
                ) {
                  final query = _tableSearchQuery.trim().toLowerCase();
                  if (query.isEmpty) return docs;
                  return docs
                      .map((data) {
                        final categoryMatches = matchesVisibleFields({
                          'id': data['categoryId'],
                          'name': data['categoryName'],
                          'coffeeId': data['coffeeId'],
                        });
                        final items =
                            (data['items'] as List?)
                                ?.whereType<Map>()
                                .map((item) => Map<String, dynamic>.from(item))
                                .toList() ??
                            [];
                        final matchingItems = items
                            .where(matchesVisibleFields)
                            .toList();
                        if (categoryMatches) return data;
                        if (matchingItems.isEmpty) return null;
                        return {...data, 'items': matchingItems};
                      })
                      .whereType<Map<String, dynamic>>()
                      .toList();
                }

                bool matchesSearch(Map<String, dynamic> data) {
                  if (matchesVisibleFields(data)) return true;
                  final nestedItems = (data['items'] as List?) ?? [];
                  return nestedItems.whereType<Map>().any(
                    (item) =>
                        matchesVisibleFields(Map<String, dynamic>.from(item)),
                  );
                }

                final searchedCategoryDocs = searchedCategoryData(categoryDocs);
                final searchedCoffeeDocs = searchedCategoryData(coffeeDocs);
                final searchedBundleDocs = bundleDocs
                    .where(matchesSearch)
                    .toList();
                final searchedAddonDocs = addonDocs
                    .where(matchesSearch)
                    .toList();

                if (!_isFilteredCategory &&
                    categoryDocs.isEmpty &&
                    (bundleDocs.isNotEmpty ||
                        coffeeDocs.isNotEmpty ||
                        addonDocs.isNotEmpty) &&
                    _showCategories) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _showCategories = false;
                      _showCoffee = coffeeDocs.isNotEmpty && bundleDocs.isEmpty;
                      _showAddons = false;
                    });
                  });
                }

                if (categoryDocs.isEmpty &&
                    bundleDocs.isEmpty &&
                    coffeeDocs.isEmpty &&
                    addonDocs.isEmpty) {
                  return _buildEmptyInventoryState(
                    icon: Icons.category_outlined,
                    message: 'No items found.',
                  );
                }

                return Column(
                  children: [
                    if (!_isFilteredCategory)
                      _buildInventoryToggle(
                        categoryCount: categoryDocs.length,
                        bundleCount: bundleDocs.length,
                        coffeeCount: coffeeDocs.length,
                        addonCount: addonDocs.length,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _tableSearchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFFC2105C),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFF48FB1),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: widget.selectedIsCoffee
                          ? _buildCategoryList(
                              searchedCoffeeDocs,
                              emptyMessage: 'No coffee items found.',
                            )
                          : widget.selectedIsBundle
                          ? _buildBundleList(searchedBundleDocs)
                          : _isFilteredCategory
                          ? _buildCategoryList(
                              widget.selectedIsCoffee
                                  ? searchedCoffeeDocs
                                  : searchedCategoryDocs,
                              emptyMessage: widget.selectedIsCoffee
                                  ? 'No coffee items found.'
                                  : 'No items found.',
                            )
                          : _showCoffee
                          ? _buildCategoryList(
                              searchedCoffeeDocs,
                              emptyMessage: 'No coffee items found.',
                            )
                          : _showCategories
                          ? _buildCategoryList(
                              searchedCategoryDocs,
                              emptyMessage: 'No items found.',
                            )
                          : _buildBundleList(searchedBundleDocs),
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

class _AddonHeaderCell extends StatelessWidget {
  final String label;

  const _AddonHeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8B0035),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AddonCell extends StatelessWidget {
  final String value;
  final Color color;
  final FontWeight weight;

  const _AddonCell(
    this.value, {
    this.color = const Color(0xFF1A0A10),
    this.weight = FontWeight.w600,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 12, fontWeight: weight),
      ),
    );
  }
}

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
    return widget.child;
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
    return widget.child;
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
