import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory.dart';
import '../services/inventory_service.dart';

// ─── Theme Constants ─────────────────────────────────────────────────────────
class _AppColors {
  static const primary = Color(0xFFC2105C);
  static const primaryDark = Color(0xFF8B0035);
  static const primaryLight = Color(0xFFE91E8C);
  static const accent = Color(0xFFFF6E9D);
  static const bg = Color(0xFFFFF0F6);
  static const cardBg = Color(0xFFFFF4F8);
  static const border = Color(0xFFF8BBD0);
  static const textMid = Color(0xFF7A1F5C);
  static const textSoft = Color(0xFF8B496B);
  static const divider = Color(0xFFF1CDE0);
}

const double _staffBottomNavReserve = 24;

class _OrderConfirmationResult {
  final double totalDue;
  final double paidAmount;
  final double change;
  final String salesId;
  final String discountProofId;

  const _OrderConfirmationResult({
    required this.totalDue,
    required this.paidAmount,
    required this.change,
    required this.salesId,
    required this.discountProofId,
  });
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

class DailyStockPage extends StatefulWidget {
  const DailyStockPage({super.key});

  @override
  State<DailyStockPage> createState() => _DailyStockPageState();
}

class _DailyStockPageState extends State<DailyStockPage>
    with TickerProviderStateMixin {
  List<Inventory> entries = [];
  late TextEditingController _budgetRequestController;
  late TextEditingController _orderSearchController;
  late final Stream<QuerySnapshot> _rootSalesInventoryStream;
  Stream<QuerySnapshot>? _staffInventoryStreamCache;
  StreamSubscription? _pendingOrdersSubscription;
  Map<String, int> _cart = {};
  final Map<String, Map<String, dynamic>> _cartItemLookup = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  List<String> _staffInventoryIds = const [];
  bool _seniorDiscount = false;
  bool _pwdDiscount = false;
  bool _showBundleView = false;
  bool _showCoffeeView = false;
  bool _showCartReview = false;
  bool _cashierToolsCollapsed = false;
  String? _selectedGroupName;
  String _orderSearchQuery = '';
  List<Map<String, dynamic>> _latestOrderItems = const [];
  double _approvedBudget = 0.0;
  double _cashDrawer = 0.0;
  bool _hasPendingOrders = false;
  int _pendingOrderCount = 0;
  String? _currentUserId;
  String _staffPublicId = '';
  String _staffDisplayName = 'Staff';
  bool _autoReportCheckStarted = false;
  Timer? _dailyReportTimer;
  StreamSubscription? _budgetSubscription;
  StreamSubscription? _cashDrawerSubscription;

  // ─── Animation Controllers ──────────────────────────────────────────────
  late AnimationController _headerAnimCtrl;
  late AnimationController _budgetCardAnimCtrl;
  late AnimationController _pulseAnimCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _budgetCardFade;
  late Animation<Offset> _budgetCardSlide;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _budgetRequestController = TextEditingController();
    _orderSearchController = TextEditingController();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _staffInventoryIds = const [];
    _rootSalesInventoryStream = FirebaseFirestore.instance
        .collection('sales_inventory')
        .snapshots();
    if (_currentUserId != null) {
      _loadCashierToolsPreference(_currentUserId!);
      _loadStaffInventoryIds(_currentUserId!);
      _subscribeToPendingOrders(_currentUserId!);
    }
    InventoryService().initialize().then((_) {
      if (!mounted) return;
      setState(() {
        entries = InventoryService().currentUserEntries;
      });
    });
    entries = InventoryService().currentUserEntries;
    InventoryService().addListener(_onInventoryChanged);

    // Setup animations
    _headerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _budgetCardAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _headerFade = CurvedAnimation(
      parent: _headerAnimCtrl,
      curve: Curves.easeOut,
    );
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.25), end: Offset.zero).animate(
          CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOutCubic),
        );

    _budgetCardFade = CurvedAnimation(
      parent: _budgetCardAnimCtrl,
      curve: Curves.easeOut,
    );
    _budgetCardSlide =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _budgetCardAnimCtrl,
            curve: Curves.easeOutCubic,
          ),
        );

    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _pulseAnimCtrl, curve: Curves.easeInOut));

    _headerAnimCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _budgetCardAnimCtrl.forward();
    });
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
      final firstName = data?['firstName']?.toString().trim() ?? '';
      final lastName = data?['lastName']?.toString().trim() ?? '';
      final fullName = data?['fullName']?.toString().trim() ?? '';
      final name = data?['name']?.toString().trim() ?? '';
      _staffPublicId = publicStaffId;
      _staffDisplayName = [
        firstName,
        lastName,
      ].where((part) => part.isNotEmpty).join(' ').trim();
      if (_staffDisplayName.isEmpty) {
        _staffDisplayName = fullName.isNotEmpty
            ? fullName
            : (name.isNotEmpty ? name : 'Staff');
      }
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

    if (!mounted) return;
    setState(() {
      _staffInventoryIds = ids.toList();
      _staffInventoryStreamCache = null;
    });
    _subscribeToStaffBudget(uid);
    _subscribeToCashDrawer(uid);
    _runAutomaticDailyReportCheck(uid);
    _scheduleNextDailyReportCheck();
  }

  Future<void> _loadCashierToolsPreference(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cashierToolsCollapsed =
          prefs.getBool('daily_stock_tools_collapsed_$uid') ?? false;
    });
  }

  Future<void> _setCashierToolsCollapsed(bool collapsed) async {
    setState(() => _cashierToolsCollapsed = collapsed);
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('daily_stock_tools_collapsed_$uid', collapsed);
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
    if (ids.isEmpty) {
      _staffInventoryStreamCache = FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('staffId', isEqualTo: '')
          .snapshots();
      return _staffInventoryStreamCache!;
    }
    final query = FirebaseFirestore.instance.collection('staff_inventory');
    _staffInventoryStreamCache = ids.length == 1
        ? query.where('staffId', isEqualTo: ids.first).snapshots()
        : query.where('staffId', whereIn: ids).snapshots();
    return _staffInventoryStreamCache!;
  }

  @override
  void dispose() {
    InventoryService().removeListener(_onInventoryChanged);
    _budgetSubscription?.cancel();
    _cashDrawerSubscription?.cancel();
    _pendingOrdersSubscription?.cancel();
    _dailyReportTimer?.cancel();
    _budgetRequestController.dispose();
    _orderSearchController.dispose();
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    _qtyControllers.clear();
    _headerAnimCtrl.dispose();
    _budgetCardAnimCtrl.dispose();
    _pulseAnimCtrl.dispose();
    super.dispose();
  }

  void _onInventoryChanged() {
    if (mounted) {
      setState(() {
        entries = InventoryService().currentUserEntries;
      });
    }
  }

  void _subscribeToStaffBudget(String _) {
    _budgetSubscription?.cancel();
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _approvedBudget = 0.0);
      return;
    }

    _budgetSubscription = FirebaseFirestore.instance
        .collection('staff_budget')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .listen(
          (snapshot) {
            double totalBudget = 0.0;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              totalBudget +=
                  (data['allocatedBudget'] as num?)?.toDouble() ?? 0.0;
            }
            if (mounted) setState(() => _approvedBudget = totalBudget);
          },
          onError: (_) {
            if (mounted) setState(() => _approvedBudget = 0.0);
          },
        );
  }

  void _subscribeToCashDrawer(String _) async {
    _cashDrawerSubscription?.cancel();
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _cashDrawer = 0.0);
      return;
    }

    _cashDrawerSubscription = FirebaseFirestore.instance
        .collection('staff_cash_drawer')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .listen(
          (snapshot) {
            double totalDrawer = 0.0;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              totalDrawer += (data['balance'] as num?)?.toDouble() ?? 0.0;
            }
            if (mounted) setState(() => _cashDrawer = totalDrawer);
          },
          onError: (_) {
            if (mounted) setState(() => _cashDrawer = 0.0);
          },
        );
  }

  void _subscribeToPendingOrders(String uid) {
    _pendingOrdersSubscription?.cancel();
    _pendingOrdersSubscription = FirebaseFirestore.instance
        .collection('pending_orders')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _pendingOrderCount = snapshot.docs.length;
              _hasPendingOrders = _pendingOrderCount > 0;
            });
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _pendingOrderCount = 0;
                _hasPendingOrders = false;
              });
            }
          },
        );
  }

  int get _cartItemCount => _cart.values.fold(0, (sum, qty) => sum + qty);

  int get _validCartItemCount {
    final validKeys = _knownOrderItems(_latestOrderItems).map(_cartKey).toSet();
    if (validKeys.isEmpty) return 0;
    return _cart.entries
        .where((entry) => validKeys.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
  }

  List<MapEntry<String, int>> _validCartEntries(
    List<Map<String, dynamic>> orderItems,
  ) {
    final knownItems = _knownOrderItems(orderItems);
    return _cart.entries
        .where((entry) => knownItems.any((item) => _cartKey(item) == entry.key))
        .toList();
  }

  bool _cartHasValidItems(List<Map<String, dynamic>> orderItems) {
    return _validCartEntries(orderItems).isNotEmpty;
  }

  String _drawerIdForOrder(List<Map<String, dynamic>> orderItems) {
    for (final entry in _validCartEntries(orderItems)) {
      final item = _knownOrderItems(orderItems).firstWhere(
        (element) => _cartKey(element) == entry.key,
        orElse: () => {},
      );
      final ownerId = item['inventoryOwnerId']?.toString().trim() ?? '';
      if (ownerId.isNotEmpty) return ownerId;
    }

    return _staffInventoryIds.isNotEmpty ? _staffInventoryIds.first : '';
  }

  String _activeDrawerId() {
    final fromCart = _drawerIdForOrder(_latestOrderItems);
    if (fromCart.isNotEmpty) return fromCart;
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    if (ids.isNotEmpty) return ids.first;
    return _currentUserId?.trim() ?? '';
  }

  double _cartTotal(List<Map<String, dynamic>> orderItems) {
    final knownItems = _knownOrderItems(orderItems);
    double total = 0;
    for (var entry in _cart.entries) {
      final item = knownItems.firstWhere(
        (e) => _cartKey(e) == entry.key,
        orElse: () => {},
      );
      if (item.isNotEmpty) {
        total += entry.value * _parsePrice(item['price']);
      }
    }
    return total;
  }

  double _discountedTotal(List<Map<String, dynamic>> orderItems) {
    final total = _cartTotal(orderItems);
    return (_seniorDiscount || _pwdDiscount) ? total * 0.8 : total;
  }

  double _discountValue(List<Map<String, dynamic>> orderItems) {
    final total = _cartTotal(orderItems);
    return (_seniorDiscount || _pwdDiscount) ? total * 0.2 : 0;
  }

  String get _discountLabel {
    if (_seniorDiscount) return 'Senior discount (20%)';
    if (_pwdDiscount) return 'PWD discount (20%)';
    return '';
  }

  bool _isItemLocked(String name) {
    final current = InventoryService().getAnyEntryForItemToday(name);
    return current != null &&
        (current.safeRemainingA +
                current.safeRemainingB +
                current.safeRemainingC) >
            0;
  }

  String _cartKey(Map<String, dynamic> item) {
    final source = item['sourceInventoryId']?.toString() ?? '';
    final itemId = item['itemId']?.toString() ?? item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final variant = item['variant']?.toString() ?? '';
    if (itemId.isNotEmpty) {
      if (source.isNotEmpty && itemId.startsWith('$source|')) {
        return itemId;
      }
      return source.isEmpty ? itemId : '$source|$itemId';
    }
    final display = variant.isEmpty ? name : '$name|$variant';
    return source.isEmpty ? display : '$source|$display';
  }

  String _displayName(String key) {
    final parts = key.split('|');
    if (parts.length >= 3) {
      final sizePart = parts.firstWhere(
        (part) => part.startsWith('size:'),
        orElse: () => '',
      );
      if (sizePart.isNotEmpty) {
        final size = sizePart.substring(5);
        final addonPart = parts.firstWhere(
          (part) => part.startsWith('addon:'),
          orElse: () => '',
        );
        final addon = addonPart.isNotEmpty
            ? addonPart.substring(6).replaceAll('_', ' ')
            : '';
        if (addon.isNotEmpty && addon != 'none') {
          return '$size + $addon';
        }
        return size;
      }
      return parts[2].isNotEmpty ? '${parts[1]} (${parts[2]})' : parts[1];
    }
    if (parts.length == 2) {
      return parts[1].isNotEmpty ? parts[1] : parts[0];
    }
    return key;
  }

  String _formatCartEntryName(
    String entryKey,
    List<Map<String, dynamic>> orderItems,
  ) {
    final item = _knownOrderItems(orderItems).firstWhere(
      (element) => _cartKey(element) == entryKey,
      orElse: () => <String, dynamic>{},
    );
    return item.isNotEmpty ? _itemDisplayLabel(item) : _displayName(entryKey);
  }

  List<Map<String, dynamic>> _knownOrderItems(
    List<Map<String, dynamic>> orderItems,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final item in _cartItemLookup.values) {
      byKey[_cartKey(item)] = item;
    }
    for (final item in orderItems) {
      byKey[_cartKey(item)] = item;
    }
    return byKey.values.toList();
  }

  void _rememberOrderItems(List<Map<String, dynamic>> orderItems) {
    for (final item in orderItems) {
      _cartItemLookup[_cartKey(item)] = item;
    }
  }

  String _groupKeyForItem(Map<String, dynamic> item) {
    final savedKey = item['groupKey']?.toString() ?? '';
    if (savedKey.isNotEmpty) return savedKey;
    final source = item['sourceInventoryId']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Item';
    return source.isEmpty ? name : '$source|$name';
  }

  String _groupLabel(
    String groupKey,
    List<MapEntry<int, Map<String, dynamic>>>? variants,
  ) {
    if (variants != null && variants.isNotEmpty) {
      return variants.first.value['name']?.toString() ?? groupKey;
    }
    final parts = groupKey.split('|');
    return parts.isEmpty ? groupKey : parts.last;
  }

  int _stockForItem(Map<String, dynamic> item, int index) {
    final itemName = item['name']?.toString() ?? '';
    final itemVariant = item['variant']?.toString() ?? '';

    // Always prioritize Firebase real-time stock first, including zero.
    final hasStockField = item.containsKey('stock') && item['stock'] != null;
    final stockValue = item['stock'] is num
        ? (item['stock'] as num).toInt()
        : int.tryParse(item['stock']?.toString() ?? '') ?? 0;
    if (hasStockField) return stockValue;

    // Fallback to startingStock only when the stock field is missing.
    final startingStock = item['startingStock'] is num
        ? (item['startingStock'] as num).toInt()
        : int.tryParse(item['startingStock']?.toString() ?? '') ?? 0;
    if (startingStock > 0) return startingStock;

    // Last resort: check InventoryService for initial quantities
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
      switch (index) {
        case 0:
          return entry.safeStartingA;
        case 1:
          return entry.safeStartingB;
        case 2:
          return entry.safeStartingC;
      }
    }
    return item['startingStock'] is num
        ? (item['startingStock'] as num).toInt()
        : int.tryParse(item['startingStock']?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _orderItemsFromDocs(
    List<Map<String, dynamic>> docs,
  ) {
    if (docs.isEmpty) return [];
    final Map<String, Map<String, dynamic>> itemMap = {};
    for (final data in docs) {
      if (data == null || data['isDeleted'] == true) continue;
      final name = data['name']?.toString() ?? 'Item';
      final rawSourceId = data['sourceInventoryId']?.toString() ?? '';
      final sourceId = rawSourceId.isNotEmpty
          ? rawSourceId
          : data['staffDocId']?.toString() ?? '';
      final isBundle = data['isBundle'] == true;

      if (isBundle) {
        final int bundleStock = data['bundleCount'] is num
            ? (data['bundleCount'] as num).toInt()
            : int.tryParse(data['bundleCount']?.toString() ?? '') ?? 0;
        if (bundleStock <= 0) continue;

        final groupKey = sourceId.isEmpty ? name : '$sourceId|$name';
        final key = groupKey;
        if (itemMap.containsKey(key)) continue;

        itemMap[key] = {
          'name': name,
          'groupKey': groupKey,
          'sourceInventoryId': sourceId,
          'staffInventoryDocId': data['staffDocId']?.toString() ?? '',
          'inventoryOwnerId': data['staffId']?.toString() ?? '',
          'variant': '',
          'price': _parsePrice(data['price']),
          'flavor': data['name']?.toString() ?? 'Bundle',
          'stock': bundleStock,
          'startingStock': bundleStock,
          'imageUrl': data['imageUrl']?.toString() ?? '',
          'categoryImageUrl': data['imageUrl']?.toString() ?? '',
          'isBundle': true,
          'bundleId': data['bundleId']?.toString() ?? '',
          'variantSlot': 0,
        };
        continue;
      }

      final itemList = data['items'] as List<dynamic>? ?? [];
      for (final itemData in itemList) {
        if (itemData is Map<String, dynamic>) {
          final fallbackVariantSlot = itemList.indexOf(itemData);
          final savedVariantSlot = itemData['variantSlot'] is num
              ? (itemData['variantSlot'] as num).toInt()
              : fallbackVariantSlot;
          final expirationDate = itemData['expirationDate']?.toString() ?? '';
          if (_isExpiredItem(expirationDate)) continue;

          final variantName = itemData['name']?.toString() ?? '';
          final variantId = itemData['id']?.toString() ?? '';
          final groupKey = sourceId.isEmpty ? name : '$sourceId|$name';
          final key = [
            if (sourceId.isNotEmpty) sourceId,
            if (variantId.isNotEmpty) variantId else name,
            if (variantId.isEmpty && variantName.isNotEmpty) variantName,
          ].join('|');
          if (itemMap.containsKey(key)) continue;
          final int stockValue = itemData['stock'] is num
              ? (itemData['stock'] as num).toInt()
              : int.tryParse(itemData['stock']?.toString() ?? '') ?? 0;
          final int startingStockValue = itemData['startingStock'] is num
              ? (itemData['startingStock'] as num).toInt()
              : int.tryParse(itemData['startingStock']?.toString() ?? '') ?? 0;
          final hasStockField =
              itemData.containsKey('stock') && itemData['stock'] != null;
          final int effectiveStock = hasStockField
              ? stockValue
              : startingStockValue;
          if (effectiveStock <= 0) continue;
          itemMap[key] = {
            'name': name,
            'groupKey': groupKey,
            'sourceInventoryId': sourceId,
            'staffInventoryDocId': data['staffDocId']?.toString() ?? '',
            'inventoryOwnerId': data['staffId']?.toString() ?? '',
            'itemId': variantId,
            'variant': variantName,
            'price': _parsePrice(itemData['price']),
            'flavor': itemData['flavor']?.toString() ?? variantName,
            'stock': effectiveStock,
            'startingStock': startingStockValue,
            'imageUrl':
                itemData['imageUrl']?.toString() ??
                data['imageUrl']?.toString() ??
                '',
            'categoryImageUrl': data['imageUrl']?.toString() ?? '',
            'reducedQuantity': _parseInt(itemData['reducedQuantity']),
            'variantSlot': savedVariantSlot,
            'isCoffee':
                itemData['isCoffee'] == true || data['isCoffee'] == true,
            'coffeeSize': itemData['coffeeSize']?.toString() ?? '',
            'coffeeId':
                itemData['coffeeId']?.toString() ??
                data['coffeeId']?.toString() ??
                '',
            'basePrice': _parsePrice(itemData['basePrice']),
            'sizePriceDelta': _parsePrice(itemData['sizePriceDelta']),
            'addonName': itemData['addonName']?.toString() ?? '',
            'addonPriceDelta': _parsePrice(itemData['addonPriceDelta']),
          };
        }
      }
    }
    return itemMap.values.toList();
  }

  Map<String, List<MapEntry<int, Map<String, dynamic>>>> _groupOrderItemsByName(
    List<Map<String, dynamic>> orderItems,
  ) {
    final groups = <String, List<MapEntry<int, Map<String, dynamic>>>>{};
    for (final entry in orderItems.asMap().entries) {
      final groupKey = _groupKeyForItem(entry.value);
      groups.putIfAbsent(groupKey, () => []).add(entry);
    }
    return groups;
  }

  double _parsePrice(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    }
    return 0;
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
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

  TextEditingController _qtyControllerFor(String key, int qty) {
    return _qtyControllers.putIfAbsent(
      key,
      () => TextEditingController(text: qty > 0 ? qty.toString() : ''),
    );
  }

  void _syncQtyController(String key, int qty) {
    final controller = _qtyControllerFor(key, qty);
    final text = qty > 0 ? qty.toString() : '';
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setItemQuantity(String key, String value, int maxStock) {
    if (value.isEmpty) {
      return;
    }
    final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final upperLimit = max(maxStock, 1);
    final clamped = parsed < 1
        ? 1
        : (parsed > upperLimit ? upperLimit : parsed);
    setState(() {
      _cart[key] = clamped;
    });
    if (clamped != parsed) {
      _syncQtyController(key, clamped);
    }
  }

  void _addItem(String key) => setState(() {
    _cart[key] = (_cart[key] ?? 0) + 1;
    _syncQtyController(key, _cart[key]!);
  });

  void _addSingleItemToTicket(Map<String, dynamic> item, int maxStock) {
    final key = _cartKey(item);
    final current = _cart[key] ?? 0;
    if (current >= maxStock) {
      _showStyledSnackBar('No more stock available', isError: true);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _cartItemLookup[key] = item;
      _cart[key] = current + 1;
      _syncQtyController(key, _cart[key]!);
    });
  }

  void _removeItem(String key) {
    if (!_cart.containsKey(key)) return;
    final current = _cart[key]!;
    if (current <= 1) {
      _syncQtyController(key, 1);
      return;
    } else {
      _cart[key] = current - 1;
    }
    _syncQtyController(key, _cart[key]!);
    setState(() {});
  }

  void _deleteCartItem(String key) {
    if (!_cart.containsKey(key)) return;
    setState(() {
      _cart.remove(key);
      _syncQtyController(key, 0);
    });
  }

  void _addCoffeeSelection(Map<String, dynamic> item, int quantity) {
    if (quantity <= 0) return;
    final key = _cartKey(item);
    setState(() {
      _cartItemLookup[key] = item;
      _cart[key] = (_cart[key] ?? 0) + quantity;
      _syncQtyController(key, _cart[key]!);
    });
  }

  Future<void> _showCoffeeCustomizeDialog({
    required String flavorName,
    required String coffeeId,
    required List<Map<String, dynamic>> variants,
  }) async {
    if (variants.isEmpty) return;

    final sizeGroups = <String, List<Map<String, dynamic>>>{};
    for (final variant in variants) {
      final sizeName =
          variant['coffeeSize']?.toString() ??
          variant['variant']?.toString() ??
          'Regular';
      sizeGroups.putIfAbsent(sizeName, () => []).add(variant);
    }

    String selectedSize = sizeGroups.keys.first;
    String selectedAddon = '';
    String selectedSugar = '50%';
    int quantity = 1;

    Map<String, dynamic> selectedItem() {
      final sizeVariants = sizeGroups[selectedSize] ?? variants;
      final baseVariant = sizeVariants.firstWhere(
        (variant) => (variant['addonName']?.toString() ?? '').isEmpty,
        orElse: () => sizeVariants.first,
      );
      final selected = selectedAddon.isEmpty
          ? baseVariant
          : sizeVariants.firstWhere(
              (variant) =>
                  (variant['addonName']?.toString() ?? '') == selectedAddon,
              orElse: () => baseVariant,
            );
      final baseId = selected['id']?.toString() ?? '';
      final sugarSlug = selectedSugar.replaceAll('%', 'pct');
      return {
        ...selected,
        'id': baseId.isEmpty ? 'sugar:$sugarSlug' : '$baseId|sugar:$sugarSlug',
        'sugarLevel': selectedSugar,
        'variant': [
          selected['variant']?.toString() ?? selectedSize,
          'Sugar $selectedSugar',
        ].where((part) => part.trim().isNotEmpty).join(' - '),
      };
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeSizeVariants = sizeGroups[selectedSize] ?? variants;
            final chosen = selectedItem();
            final totalPrice = _parsePrice(chosen['price']) * quantity;
            final addonOptions = activeSizeVariants
                .map((variant) => variant['addonName']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _AppColors.primary.withOpacity(0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 22, 18, 18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_AppColors.primary, _AppColors.primaryLight],
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
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.local_cafe_rounded,
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
                                  flavorName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (coffeeId.isNotEmpty)
                                  Text(
                                    coffeeId,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MiniTag(
                                label: 'Size: $selectedSize',
                                bgColor: _AppColors.primary.withOpacity(0.10),
                                textColor: _AppColors.primary,
                              ),
                              _MiniTag(
                                label:
                                    'Base ₱${_parsePrice(chosen['basePrice']).toStringAsFixed(0)}',
                                bgColor: const Color(0xFFE8F5E9),
                                textColor: const Color(0xFF2E7D32),
                              ),
                              if (_parsePrice(chosen['sizePriceDelta']) > 0)
                                _MiniTag(
                                  label:
                                      '+₱${_parsePrice(chosen['sizePriceDelta']).toStringAsFixed(0)} size',
                                  bgColor: const Color(0xFFFFF3E0),
                                  textColor: const Color(0xFFE65100),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Size',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _AppColors.textMid,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sizeGroups.keys.map((sizeName) {
                              final isSelected = selectedSize == sizeName;
                              return ChoiceChip(
                                selected: isSelected,
                                onSelected: (_) => setDialogState(() {
                                  selectedSize = sizeName;
                                  selectedAddon = '';
                                }),
                                label: Text(sizeName),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : _AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                                selectedColor: _AppColors.primary,
                                backgroundColor: _AppColors.cardBg,
                                side: BorderSide(
                                  color: isSelected
                                      ? _AppColors.primary
                                      : _AppColors.border,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                          if (addonOptions.isNotEmpty) ...[
                            const Text(
                              'Add-ons',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _AppColors.textMid,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...addonOptions.map((addonName) {
                                  final addonVariant = activeSizeVariants
                                      .firstWhere(
                                        (variant) =>
                                            (variant['addonName']?.toString() ??
                                                '') ==
                                            addonName,
                                        orElse: () => activeSizeVariants.first,
                                      );
                                  final addonPrice = _parsePrice(
                                    addonVariant['addonPriceDelta'],
                                  );
                                  final isSelected = selectedAddon == addonName;
                                  return ChoiceChip(
                                    selected: isSelected,
                                    onSelected: (_) => setDialogState(
                                      () => selectedAddon = isSelected
                                          ? ''
                                          : addonName,
                                    ),
                                    label: Text(
                                      addonPrice > 0
                                          ? '$addonName (+₱${addonPrice.toStringAsFixed(0)})'
                                          : addonName,
                                    ),
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : _AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    selectedColor: _AppColors.primary,
                                    backgroundColor: _AppColors.cardBg,
                                    side: BorderSide(
                                      color: isSelected
                                          ? _AppColors.primary
                                          : _AppColors.border,
                                    ),
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 18),
                          ],
                          const Text(
                            'Sugar Level',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _AppColors.textMid,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['0%', '25%', '50%', '75%', '100%'].map((
                              sugar,
                            ) {
                              final isSelected = selectedSugar == sugar;
                              return ChoiceChip(
                                selected: isSelected,
                                onSelected: (_) =>
                                    setDialogState(() => selectedSugar = sugar),
                                label: Text(sugar),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : _AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                                selectedColor: _AppColors.primary,
                                backgroundColor: _AppColors.cardBg,
                                side: BorderSide(
                                  color: isSelected
                                      ? _AppColors.primary
                                      : _AppColors.border,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Text(
                                'Quantity',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _AppColors.textMid,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: _AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _StepperButton(
                                      icon: Icons.remove_rounded,
                                      onPressed: quantity > 1
                                          ? () => setDialogState(
                                              () => quantity -= 1,
                                            )
                                          : null,
                                    ),
                                    SizedBox(
                                      width: 48,
                                      child: Center(
                                        child: Text(
                                          '$quantity',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: _AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _StepperButton(
                                      icon: Icons.add_rounded,
                                      onPressed: () =>
                                          setDialogState(() => quantity += 1),
                                      isAdd: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected: ${chosen['variant'] ?? selectedSize}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _AppColors.textSoft,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₱${totalPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: _AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _AppColors.primary,
                                side: const BorderSide(
                                  color: _AppColors.border,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final chosenItem = selectedItem();
                                _addCoffeeSelection(chosenItem, quantity);
                                Navigator.of(dialogContext).pop();
                                _showStyledSnackBar(
                                  '$quantity x ${chosenItem['name']} added to cart',
                                );
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Done'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
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

  Future<void> _showBundleItemsDialog(String bundleName) async {
    try {
      final ids = _staffInventoryIds
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .take(10)
          .toList();
      if (ids.isEmpty) {
        _showStyledSnackBar('Bundle not found', isError: true);
        return;
      }

      var bundleQuery = FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('name', isEqualTo: bundleName)
          .where('isBundle', isEqualTo: true);
      bundleQuery = ids.length == 1
          ? bundleQuery.where('staffId', isEqualTo: ids.first)
          : bundleQuery.where('staffId', whereIn: ids);
      final querySnapshot = await bundleQuery.get();

      if (querySnapshot.docs.isEmpty) {
        _showStyledSnackBar('Bundle not found', isError: true);
        return;
      }

      final bundleDoc = querySnapshot.docs.first;
      final bundleData = bundleDoc.data();
      final bundleItems = bundleData['items'] as List<dynamic>? ?? [];
      final bundleInstances = _bundleInstancesFromData(bundleData);
      final availableBundleCount = bundleInstances
          .where(
            (instance) =>
                instance['status']?.toString().toLowerCase() == 'available',
          )
          .length;
      final bundleCount = bundleInstances.isNotEmpty
          ? availableBundleCount
          : (bundleData['bundleCount'] is num
                ? (bundleData['bundleCount'] as num).toInt()
                : int.tryParse(bundleData['bundleCount']?.toString() ?? '') ??
                      0);

      if (!mounted) return;

      final Map<String, double> itemPrices = {};
      var nonBundleQuery = FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('isBundle', isEqualTo: false);
      nonBundleQuery = ids.length == 1
          ? nonBundleQuery.where('staffId', isEqualTo: ids.first)
          : nonBundleQuery.where('staffId', whereIn: ids);
      final nonBundleSnapshot = await nonBundleQuery.get();

      for (final item in bundleItems) {
        if (item is Map<String, dynamic>) {
          final itemName = item['name']?.toString() ?? '';
          if (itemName.isEmpty) continue;

          final priceFromBundle = _parsePrice(item['price']);
          if (priceFromBundle > 0) {
            itemPrices[itemName] = priceFromBundle;
            continue;
          }

          double foundPrice = 0.0;
          for (final doc in nonBundleSnapshot.docs) {
            final data = doc.data();
            final itemsList = data['items'] as List<dynamic>? ?? [];
            for (final variant in itemsList) {
              if (variant is Map<String, dynamic>) {
                final variantName = variant['name']?.toString() ?? '';
                if (variantName == itemName) {
                  foundPrice = _parsePrice(variant['price']);
                  break;
                }
              }
            }
            if (foundPrice > 0) break;
          }
          itemPrices[itemName] = foundPrice;
        }
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _AppColors.primary.withOpacity(0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _AppColors.primaryDark,
                              _AppColors.primary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bundleName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    bundleInstances.isNotEmpty
                                        ? '$bundleCount available bundle(s)'
                                        : '$bundleCount bundle(s)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _showBundleReportDialog(
                                bundleName: bundleName,
                                bundleItems: bundleItems,
                                itemPrices: itemPrices,
                                bundleData: bundleData,
                              ),
                              icon: const Icon(
                                Icons.bar_chart_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                'View Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 0),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      if (bundleItems.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 32,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'No items in this bundle',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showBundleItemsDialog(bundleName);
                                  },
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Refill bundle',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _AppColors.primary,
                                    side: BorderSide(
                                      color: _AppColors.primary.withOpacity(
                                        0.25,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    minimumSize: const Size(0, 0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Flexible(
                          fit: FlexFit.loose,
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            itemCount: bundleItems.length,
                            itemBuilder: (context, index) {
                              final item = bundleItems[index];
                              final itemName = item is Map<String, dynamic>
                                  ? item['name']?.toString() ?? 'Item'
                                  : item.toString();
                              final itemQuantityPerBundle =
                                  item is Map<String, dynamic>
                                  ? item['quantity'] is num
                                        ? (item['quantity'] as num).toInt()
                                        : int.tryParse(
                                                item['quantity']?.toString() ??
                                                    '',
                                              ) ??
                                              1
                                  : 1;
                              final totalItemQuantity =
                                  itemQuantityPerBundle * bundleCount;
                              final remainingItemQuantity = totalItemQuantity;
                              final itemPrice = itemPrices[itemName] ?? 0.0;
                              final totalPrice =
                                  itemPrice * remainingItemQuantity;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: _AppColors.primary.withOpacity(0.12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                itemName,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '₱${itemPrice.toStringAsFixed(2)} per pc',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: _AppColors.textSoft,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '$itemQuantityPerBundle pcs per bundle · $bundleCount bundles',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: _AppColors.textSoft,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _AppColors.primary
                                                .withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            '×$remainingItemQuantity',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'Total ₱${totalPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 15,
                              ),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
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
        },
      );
    } catch (e) {
      _showStyledSnackBar('Error loading bundle items: $e', isError: true);
    }
  }

  void _showBundleReportDialog({
    required String bundleName,
    required List<dynamic> bundleItems,
    required Map<String, double> itemPrices,
    required Map<String, dynamic> bundleData,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final bundleInstances = _bundleInstancesFromData(bundleData);
        final availableBundleCount = bundleInstances
            .where(
              (bundle) =>
                  bundle['status']?.toString().toLowerCase() == 'available',
            )
            .length;
        final totalRemaining = bundleInstances.fold<int>(0, (sum, bundle) {
          final items = bundle['items'] as List<dynamic>? ?? [];
          return sum +
              items.fold<int>(0, (itemSum, item) {
                if (item is! Map<String, dynamic>) return itemSum;
                return itemSum +
                    _parseInt(
                      item['remaining'],
                      fallback: _parseInt(item['quantity']),
                    );
              });
        });
        final totalValue = bundleInstances.fold<double>(0.0, (sum, bundle) {
          final items = bundle['items'] as List<dynamic>? ?? [];
          return sum +
              items.fold<double>(0.0, (itemSum, item) {
                if (item is! Map<String, dynamic>) return itemSum;
                final itemName = item['name']?.toString() ?? '';
                final itemPrice =
                    itemPrices[itemName] ?? _parsePrice(item['price']);
                final remaining = _parseInt(
                  item['remaining'],
                  fallback: _parseInt(item['quantity']),
                );
                return itemSum + (itemPrice * remaining);
              });
        });

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _AppColors.primary.withOpacity(0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$bundleName Report',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$availableBundleCount bundle(s) · $totalRemaining tracked pcs',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _AppColors.textSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: _AppColors.textSoft,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (bundleInstances.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No bundle report available',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: min(360, bundleInstances.length * 132.0),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: bundleInstances.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final bundle = bundleInstances[index];
                        final instanceItems =
                            bundle['items'] as List<dynamic>? ?? [];
                        final status =
                            bundle['status']?.toString() ?? 'available';
                        final statusLabel = status == 'inCategory'
                            ? 'In category'
                            : status == 'sold'
                            ? 'Sold'
                            : 'Available';

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _AppColors.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _AppColors.border),
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
                                          'Bundle #${bundle['number'] ?? index + 1}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Bundle ID: ${bundle['id'] ?? _bundleInstanceId(bundleData['bundleId']?.toString() ?? '', index)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _AppColors.textSoft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _MiniTag(
                                    label: statusLabel,
                                    bgColor: Colors.white,
                                    textColor: _AppColors.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ...instanceItems.map((item) {
                                if (item is! Map<String, dynamic>) {
                                  return const SizedBox.shrink();
                                }
                                final itemName =
                                    item['name']?.toString() ?? 'Item';
                                final originalQty = _parseInt(
                                  item['quantity'],
                                  fallback: 1,
                                );
                                final remainingQty = _parseInt(
                                  item['remaining'],
                                  fallback: originalQty,
                                );
                                final refundedQty = _parseInt(item['refunded']);
                                final itemPrice =
                                    itemPrices[itemName] ??
                                    _parsePrice(item['price']);
                                final lineTotal = itemPrice * remainingQty;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          refundedQty > 0
                                              ? '$itemName · refunded $refundedQty · $remainingQty of $originalQty left'
                                              : '$itemName · $remainingQty of $originalQty left',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Text(
                                        '₱${lineTotal.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
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
                if (bundleInstances.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Bundle total value',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '₱${totalValue.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Close report',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showSellBundleItemDialog({
    required DocumentReference<Map<String, dynamic>> bundleRef,
    required String itemName,
    required int maxQuantity,
    required double itemPrice,
    required int quantityPerBundle,
  }) async {
    final quantityController = TextEditingController();
    int selectedQuantity = 0;

    final remainingQuantity = maxQuantity;

    final transferred = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            selectedQuantity = int.tryParse(quantityController.text) ?? 0;
            final currentRemaining = max(0, remainingQuantity);
            final stepSize = max(1, quantityPerBundle);
            final selectedTotal = itemPrice * selectedQuantity;
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _AppColors.primary.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sell item',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _AppColors.textSoft,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                itemName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _AppColors.textMid,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: _AppColors.textSoft,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Available from bundle: $currentRemaining pcs',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _AppColors.textSoft,
                      ),
                    ),
                    if (quantityPerBundle > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Use increments of $quantityPerBundle pcs so bundle stock stays correct.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _AppColors.textSoft,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepperButton(
                          icon: Icons.remove_rounded,
                          onPressed: selectedQuantity > 0
                              ? () {
                                  final next = max(
                                    0,
                                    selectedQuantity - stepSize,
                                  );
                                  quantityController.text = next.toString();
                                  setDialogState(() {});
                                }
                              : null,
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: quantityController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (value) {
                              final parsed = int.tryParse(value) ?? 0;
                              final clamped = parsed < 0
                                  ? 0
                                  : min(currentRemaining, parsed);
                              if (parsed != clamped) {
                                quantityController.text = clamped.toString();
                              }
                              setDialogState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        _StepperButton(
                          icon: Icons.add_rounded,
                          onPressed: selectedQuantity < currentRemaining
                              ? () {
                                  final next = min(
                                    currentRemaining,
                                    selectedQuantity + stepSize,
                                  );
                                  quantityController.text = next.toString();
                                  setDialogState(() {});
                                }
                              : null,
                          isAdd: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Selected: ${quantityController.text} pcs',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _AppColors.textSoft,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Price per piece',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _AppColors.textSoft,
                          ),
                        ),
                        Text(
                          '₱${itemPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Subtotal',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '₱${selectedTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _AppColors.primary,
                              side: BorderSide(
                                color: _AppColors.primary.withOpacity(0.25),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                              final qty =
                                  int.tryParse(quantityController.text) ?? 0;
                              if (qty <= 0) {
                                _showStyledSnackBar(
                                  'Enter a valid quantity',
                                  isError: true,
                                );
                                return;
                              }
                              if (qty > currentRemaining) {
                                _showStyledSnackBar(
                                  'Quantity cannot exceed $currentRemaining',
                                  isError: true,
                                );
                                return;
                              }
                              if (quantityPerBundle > 1 &&
                                  qty % quantityPerBundle != 0) {
                                _showStyledSnackBar(
                                  'Quantity must be by $quantityPerBundle pcs',
                                  isError: true,
                                );
                                return;
                              }

                              final transferred =
                                  await _transferBundleItemToStock(
                                    bundleRef: bundleRef,
                                    itemName: itemName,
                                    quantity: qty,
                                    quantityPerBundle: quantityPerBundle,
                                  );
                              if (transferred && context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Confirm',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return transferred ?? false;
  }

  Future<bool> _transferBundleItemToStock({
    required DocumentReference<Map<String, dynamic>> bundleRef,
    required String itemName,
    required int quantity,
    required int quantityPerBundle,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final inventorySnapshot = await firestore
          .collection('staff_inventory')
          .where('staffId', isEqualTo: _currentUserId)
          .get();

      DocumentReference<Map<String, dynamic>>? stockDocRef;
      var stockItemIndex = -1;

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        if (data['isBundle'] == true || data['isDeleted'] == true) continue;

        final itemsList = data['items'] as List<dynamic>? ?? [];
        for (var i = 0; i < itemsList.length; i++) {
          final itemData = itemsList[i];
          if (itemData is! Map<String, dynamic>) continue;

          final savedName = itemData['name']?.toString() ?? '';
          final savedVariant = itemData['variant']?.toString() ?? '';
          final parentName = data['name']?.toString() ?? '';
          final matchesItem =
              savedName == itemName ||
              savedVariant == itemName ||
              (parentName == itemName &&
                  (savedName.isEmpty || savedName == itemName));

          if (matchesItem) {
            stockDocRef = doc.reference;
            stockItemIndex = i;
            break;
          }
        }

        if (stockDocRef != null) break;
      }

      if (stockDocRef == null || stockItemIndex < 0) {
        _showStyledSnackBar(
          'No matching stock item found for $itemName',
          isError: true,
        );
        return false;
      }

      final matchedStockDocRef = stockDocRef;
      await firestore.runTransaction((transaction) async {
        final bundleSnapshot = await transaction.get(bundleRef);
        final stockSnapshot = await transaction.get(matchedStockDocRef);
        final bundleData = bundleSnapshot.data();
        final stockData = stockSnapshot.data();

        if (bundleData == null) {
          throw Exception('Bundle no longer exists');
        }
        if (stockData == null) {
          throw Exception('Stock item no longer exists');
        }

        final currentBundleCount = _parseInt(bundleData['bundleCount']);
        final bundlesToDeduct = max(1, quantity ~/ max(1, quantityPerBundle));

        if (bundlesToDeduct > currentBundleCount) {
          throw Exception('Not enough bundle stock available');
        }

        final bundleInstances = _bundleInstancesFromData(bundleData);
        var bundlesMarked = 0;
        final updatedBundleInstances = bundleInstances.map((instance) {
          if (bundlesMarked >= bundlesToDeduct) return instance;
          final status = instance['status']?.toString() ?? 'available';
          if (status != 'available') return instance;

          bundlesMarked++;
          return {
            ...instance,
            'status': 'inCategory',
            'movedItemName': itemName,
            'movedAt': Timestamp.now(),
          };
        }).toList();

        if (bundlesMarked < bundlesToDeduct) {
          throw Exception('Not enough available bundle instances');
        }

        final itemsList = stockData['items'] as List<dynamic>? ?? [];
        if (stockItemIndex >= itemsList.length) {
          throw Exception('Stock item changed. Please try again.');
        }

        final updatedItems = itemsList.asMap().entries.map((entry) {
          final itemData = entry.value;
          if (entry.key != stockItemIndex ||
              itemData is! Map<String, dynamic>) {
            return itemData;
          }

          final currentStock = itemData.containsKey('stock')
              ? _parseInt(itemData['stock'])
              : _parseInt(itemData['startingStock']);

          return {...itemData, 'stock': currentStock + quantity};
        }).toList();

        transaction.update(matchedStockDocRef, {
          'items': updatedItems,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(bundleRef, {
          'bundleCount': currentBundleCount - bundlesToDeduct,
          'bundleInstances': updatedBundleInstances,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      _showStyledSnackBar('$quantity x $itemName added to stock');

      await InventoryService().initialize();
      if (mounted) {
        setState(() {
          final oldBundleCartKey = _cartKey({'name': itemName, 'variant': ''});
          _cart.remove(oldBundleCartKey);
          _qtyControllers.remove(oldBundleCartKey)?.dispose();
          entries = InventoryService().currentUserEntries;
        });
      }
      return true;
    } catch (e) {
      _showStyledSnackBar('Error updating stock: $e', isError: true);
      return false;
    }
  }

  Future<void> _consumeBundleTrackedStock({
    required String itemName,
    required int quantity,
  }) async {
    if (quantity <= 0) return;

    var remainingToConsume = quantity;
    final snapshot = await FirebaseFirestore.instance
        .collection('staff_inventory')
        .where('staffId', isEqualTo: _currentUserId)
        .where('isBundle', isEqualTo: true)
        .get();
    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final aTime =
            (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bTime =
            (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });

    for (final doc in docs) {
      if (remainingToConsume <= 0) break;

      final data = doc.data();
      if (data['isDeleted'] == true) continue;

      final instances = _bundleInstancesFromData(data);
      var changed = false;

      final updatedInstances = instances.map((instance) {
        if (remainingToConsume <= 0) return instance;
        final status = instance['status']?.toString() ?? 'available';
        if (status != 'inCategory') return instance;

        final items = instance['items'] as List<dynamic>? ?? [];
        var consumedFromInstance = false;
        final updatedItems = items.map((item) {
          if (remainingToConsume <= 0 || item is! Map<String, dynamic>) {
            return item;
          }

          final savedName = item['name']?.toString() ?? '';
          if (savedName != itemName) return item;

          final originalQty = _parseInt(item['quantity'], fallback: 1);
          final currentRemaining = _parseInt(
            item['remaining'],
            fallback: originalQty,
          );
          if (currentRemaining <= 0) return item;

          final consumed = min(currentRemaining, remainingToConsume);
          remainingToConsume -= consumed;
          changed = true;
          consumedFromInstance = true;

          return {...item, 'remaining': currentRemaining - consumed};
        }).toList();

        if (!consumedFromInstance) return instance;

        final hasRemaining = updatedItems.any((item) {
          if (item is! Map<String, dynamic>) return false;
          return _parseInt(
                item['remaining'],
                fallback: _parseInt(item['quantity']),
              ) >
              0;
        });

        return {
          ...instance,
          'items': updatedItems,
          'status': hasRemaining ? 'inCategory' : 'sold',
        };
      }).toList();

      if (changed) {
        await doc.reference.update({
          'bundleInstances': updatedInstances,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  void _submitBudgetRequest() async {
    final requestText = _budgetRequestController.text.trim();
    if (requestText.isEmpty) {
      _showStyledSnackBar('Enter an amount to request', isError: true);
      return;
    }
    final amount = double.tryParse(requestText);
    if (amount == null || amount <= 0) {
      _showStyledSnackBar('Enter a valid budget amount', isError: true);
      return;
    }
    if (amount > _cashDrawer) {
      _showStyledSnackBar(
        'Cannot request more than available (₱${_cashDrawer.toStringAsFixed(2)})',
        isError: true,
      );
      return;
    }
    try {
      final drawerId = _activeDrawerId();
      if (drawerId.isNotEmpty) {
        // Deduct from cash drawer
        final newBalance = _cashDrawer - amount;
        await FirebaseFirestore.instance
            .collection('staff_cash_drawer')
            .doc(drawerId)
            .set({
              'balance': newBalance,
              'updatedAt': DateTime.now(),
              'staffId': drawerId,
              'handledByStaffId': _currentUserId,
            }, SetOptions(merge: true));
      }
      _showStyledSnackBar('Deducted ₱${amount.toStringAsFixed(2)} from drawer');
      _budgetRequestController.clear();
    } catch (e) {
      _showStyledSnackBar('Error processing request: $e', isError: true);
    }
  }

  void _showStyledSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xFFB71C1C)
            : _AppColors.primaryDark,
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
      ),
    );
  }

  void _openBudgetRequestDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
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
                  color: _AppColors.primary.withOpacity(0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dialog header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_AppColors.primaryDark, _AppColors.primary],
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
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Budget Request',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.cardBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_balance_rounded,
                              size: 16,
                              color: _AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Drawer Balance: ₱${_cashDrawer.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _AppColors.primary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PinkTextField(
                        controller: _budgetRequestController,
                        label: 'Amount to request',
                        hint: '0.00',
                        icon: Icons.payments_outlined,
                        keyboardType: TextInputType.number,
                        prefixText: '₱',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _AppColors.primary,
                            side: const BorderSide(
                              color: _AppColors.border,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                          onPressed: () {
                            final requestText = _budgetRequestController.text
                                .trim();
                            final amount = double.tryParse(requestText);
                            if (requestText.isEmpty ||
                                amount == null ||
                                amount <= 0) {
                              _showStyledSnackBar(
                                'Enter a valid budget amount',
                                isError: true,
                              );
                              return;
                            }
                            _submitBudgetRequest();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Confirm',
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
  }

  void _showSendReportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
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
                  color: _AppColors.primary.withOpacity(0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dialog header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_AppColors.primaryDark, _AppColors.primary],
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
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Send Report',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                // Cash drawer total section
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _AppColors.primary.withOpacity(0.15),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cash Drawer Total',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₱${_cashDrawer.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: _AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Today\'s Transactions',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildClosingInventoryPreview(),
                    ],
                  ),
                ),
                // Today's transactions list
                Expanded(
                  child: FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('completed_sales')
                        .orderBy('timestamp', descending: true)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: _AppColors.primary,
                            strokeWidth: 2,
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No transactions today',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }

                      final userId = FirebaseAuth.instance.currentUser?.uid;
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);

                      final docs = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final timestamp = data['timestamp'] as Timestamp?;
                        final docUserId = data['userId'];

                        if (timestamp == null || docUserId != userId)
                          return false;

                        final docDate = DateTime(
                          timestamp.toDate().year,
                          timestamp.toDate().month,
                          timestamp.toDate().day,
                        );
                        return docDate == today;
                      }).toList();

                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No transactions today',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          final timestamp = data['timestamp'] as Timestamp?;
                          final total =
                              (data['total'] as num?)?.toDouble() ?? 0;
                          final paidAmount =
                              (data['paidAmount'] as num?)?.toDouble() ?? 0;
                          final change =
                              (data['change'] as num?)?.toDouble() ?? 0;
                          final subtotal =
                              (data['subtotal'] as num?)?.toDouble() ?? total;
                          final discount =
                              (data['discount'] as num?)?.toDouble() ?? 0;
                          final discountType =
                              data['discountType']?.toString() ?? 'None';
                          final salesId = data['salesId']?.toString() ?? 'N/A';
                          final items = List<Map<String, dynamic>>.from(
                            data['items'] ?? [],
                          );

                          final timeStr = timestamp != null
                              ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
                              : 'Unknown';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _AppColors.cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _AppColors.primary.withOpacity(0.1),
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
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'ID: $salesId',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: _AppColors.primary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Expanded(
                                      child: Text(
                                        '₱${total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: _AppColors.primary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Divider(
                                  color: _AppColors.border,
                                  height: 8,
                                ),
                                const SizedBox(height: 6),
                                ...items
                                    .where(
                                      (item) => _parseInt(item['quantity']) > 0,
                                    )
                                    .map((item) {
                                      final itemName =
                                          item['name']?.toString() ?? 'Unknown';
                                      final variant =
                                          item['variant']?.toString() ?? '';
                                      final displayName = variant.isNotEmpty
                                          ? '$itemName ($variant)'
                                          : itemName;
                                      final qty = _parseInt(item['quantity']);
                                      final price = _parsePrice(item['price']);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 5,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$qty × $displayName',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: _AppColors.textSoft,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              '₱${(qty * price).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: _AppColors.textMid,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                const SizedBox(height: 4),
                                _CompactAmountLine(
                                  label: 'Subtotal:',
                                  value: '₱${subtotal.toStringAsFixed(2)}',
                                ),
                                if (discount > 0.01)
                                  _CompactAmountLine(
                                    label: 'Discount ($discountType):',
                                    value: '-₱${discount.toStringAsFixed(2)}',
                                    valueColor: const Color(0xFF2E7D32),
                                  ),
                                _CompactAmountLine(
                                  label: 'Customer Payment:',
                                  value: '₱${paidAmount.toStringAsFixed(2)}',
                                ),
                                _CompactAmountLine(
                                  label: 'Change:',
                                  value: '₱${change.toStringAsFixed(2)}',
                                  valueColor: const Color(0xFF2E7D32),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _AppColors.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Total Paid:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _AppColors.primary,
                                        ),
                                      ),
                                      Text(
                                        '₱${total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: _AppColors.primary,
                                        ),
                                      ),
                                    ],
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
                // Cancel and Confirm buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _AppColors.primary,
                            side: const BorderSide(
                              color: _AppColors.border,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                            Navigator.of(context).pop();
                            await _sendDailyReport();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Confirm',
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
  }

  void _cancelCurrentOrder() {
    setState(() {
      _cart.clear();
      _selectedGroupName = null;
      _showCartReview = false;
      _seniorDiscount = false;
      _pwdDiscount = false;
      for (final controller in _qtyControllers.values) {
        controller.clear();
      }
    });
  }

  void _openCartReview() {
    if (!_cartHasValidItems(_latestOrderItems)) {
      _showStyledSnackBar('Add items to cart first', isError: true);
      return;
    }
    setState(() {
      _selectedGroupName = null;
      _showCartReview = true;
    });
  }

  void _discardGroupSelections(
    List<MapEntry<int, Map<String, dynamic>>> variants,
  ) {
    setState(() {
      for (final variant in variants) {
        final key = _cartKey(variant.value);
        _cart.remove(key);
        _syncQtyController(key, 0);
      }
      _selectedGroupName = null;
    });
  }

  Widget _buildClosingInventoryPreview() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return const SizedBox.shrink();

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('staffId', isEqualTo: userId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final rows = <Map<String, dynamic>>[];
        for (final doc in snapshot.data!.docs) {
          final data = doc.data();
          if (data['isDeleted'] == true || data['isBundle'] == true) continue;
          final items = (data['items'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          if (items.isEmpty) continue;
          var started = 0;
          var remaining = 0;
          for (final item in items) {
            final stock = _parseInt(item['stock']);
            started += _parseInt(item['startingStock'], fallback: stock);
            remaining += stock;
          }
          rows.add({
            'name': data['name']?.toString() ?? 'Category',
            'started': started,
            'remaining': remaining,
            'sold': max(0, started - remaining),
          });
        }
        if (rows.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Closing Inventory',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              ...rows.take(3).map((row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row['name']?.toString() ?? 'Category',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _AppColors.textMid,
                          ),
                        ),
                      ),
                      Text(
                        '${row['started']} start  ${row['remaining']} left  ${row['sold']} sold',
                        style: const TextStyle(
                          fontSize: 10,
                          color: _AppColors.textSoft,
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
    );
  }

  Future<void> _sendDailyReport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showStyledSnackBar(
        'Unable to send report: user not authenticated',
        isError: true,
      );
      return;
    }

    try {
      final sent = await _sendDailyReportForDate(
        DateTime.now(),
        automatic: false,
        resetDrawerAfterSend: true,
      );
      if (sent) {
        _showStyledSnackBar('Report sent successfully');
      } else {
        _showStyledSnackBar('Report already sent for today');
      }
    } catch (e) {
      _showStyledSnackBar('Error sending report: $e', isError: true);
    }
  }

  String _reportDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _runAutomaticDailyReportCheck(String uid) async {
    if (_autoReportCheckStarted) return;
    _autoReportCheckStarted = true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    try {
      await _sendDailyReportForDate(
        yesterday,
        automatic: true,
        resetDrawerAfterSend: true,
      );
    } catch (_) {
      // Automatic report should never block the staff sales page.
    }
  }

  void _scheduleNextDailyReportCheck() {
    _dailyReportTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1, minutes: 1));
    _dailyReportTimer = Timer(nextMidnight.difference(now), () async {
      final reportDay = DateTime.now().subtract(const Duration(days: 1));
      try {
        await _sendDailyReportForDate(
          reportDay,
          automatic: true,
          resetDrawerAfterSend: true,
        );
      } catch (_) {
        // Keep the timer alive even if the report could not be created.
      } finally {
        if (mounted) _scheduleNextDailyReportCheck();
      }
    });
  }

  Future<bool> _sendDailyReportForDate(
    DateTime reportDate, {
    required bool automatic,
    required bool resetDrawerAfterSend,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final branchId = _activeDrawerId();
    if (branchId.isEmpty) {
      throw Exception('No branch cash drawer found');
    }

    final day = DateTime(reportDate.year, reportDate.month, reportDate.day);
    final dateKey = _reportDateKey(day);
    final reportId = 'daily_report_${user.uid}_${branchId}_$dateKey'.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final reportRef = FirebaseFirestore.instance
        .collection('daily_reports')
        .doc(reportId);
    final existingReport = await reportRef.get();
    if (existingReport.exists) return false;

    final staffName = _staffDisplayName.trim().isNotEmpty
        ? _staffDisplayName.trim()
        : (user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : 'Staff');
    final staffPublicId = _staffPublicId.trim();
    final startOfDay = Timestamp.fromDate(day);
    final endOfDay = Timestamp.fromDate(day.add(const Duration(days: 1)));

    final snapshot = await FirebaseFirestore.instance
        .collection('completed_sales')
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .where('timestamp', isLessThan: endOfDay)
        .orderBy('timestamp', descending: true)
        .get();

    final docsForDay = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['userId'] == user.uid &&
          (data['branchId']?.toString() ?? branchId) == branchId;
    }).toList();

    if (!automatic && docsForDay.isEmpty) {
      throw Exception('No transactions found for this date');
    }
    if (automatic && docsForDay.isEmpty) {
      return false;
    }

    final transactions = docsForDay.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      final items =
          (data['items'] as List<dynamic>?)?.map((itemData) {
            if (itemData is Map<String, dynamic>) {
              return {
                'name': itemData['name']?.toString() ?? 'Product',
                'variant': itemData['variant']?.toString() ?? '',
                'price': itemData['price'] is num
                    ? (itemData['price'] as num).toDouble()
                    : double.tryParse(itemData['price']?.toString() ?? '') ??
                          0.0,
                'quantity': itemData['quantity'] is num
                    ? (itemData['quantity'] as num).toInt()
                    : int.tryParse(itemData['quantity']?.toString() ?? '') ?? 0,
                'category': itemData['category']?.toString() ?? '',
              };
            }
            return {
              'name': itemData?.toString() ?? 'Product',
              'variant': '',
              'price': 0.0,
              'quantity': 0,
              'category': '',
            };
          }).toList() ??
          [];

      return {
        'salesId': data['salesId'] ?? doc.id,
        'total': (data['total'] as num?)?.toDouble() ?? 0.0,
        'paidAmount': (data['paidAmount'] as num?)?.toDouble() ?? 0.0,
        'change': (data['change'] as num?)?.toDouble() ?? 0.0,
        'timestamp': timestamp?.toDate().toIso8601String() ?? '',
        'items': items,
      };
    }).toList();

    final totalSales = transactions.fold<double>(
      0.0,
      (sum, item) => sum + (item['total'] as double),
    );
    final allocationDoc = await FirebaseFirestore.instance
        .collection('staff_budget')
        .doc(branchId)
        .get();
    final openingCash =
        (allocationDoc.data()?['allocatedBudget'] as num?)?.toDouble() ?? 0.0;
    final drawerDoc = await FirebaseFirestore.instance
        .collection('staff_cash_drawer')
        .doc(branchId)
        .get();
    final closingCash =
        (drawerDoc.data()?['balance'] as num?)?.toDouble() ?? _cashDrawer;
    final now = DateTime.now();
    final closingInventory = automatic
        ? <Map<String, dynamic>>[]
        : await _saveClosingInventorySnapshot(user.uid);

    final reportPayload = {
      'title': automatic
          ? 'Automatic daily cash drawer report'
          : 'Daily cash drawer report submitted',
      'message':
          '$staffName submitted $dateKey branch sales report. Total sales: ₱${totalSales.toStringAsFixed(2)}.',
      'category': 'Reports',
      'time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'createdAt': Timestamp.fromDate(now),
      'isRead': false,
      'type': 'report',
      'automatic': automatic,
      'staffId': user.uid,
      'staffPublicId': staffPublicId,
      'staffName': staffName,
      'branchId': branchId,
      'branchIds': _staffInventoryIds,
      'reportDate': day.toIso8601String(),
      'reportDateKey': dateKey,
      'openingCash': openingCash,
      'allocatedBudget': openingCash,
      'cashDrawerTotal': closingCash,
      'closingCash': closingCash,
      'cashOverOpening': closingCash - openingCash,
      'transactionCount': docsForDay.length,
      'totalSales': totalSales,
      'transactions': transactions,
      'closingInventory': closingInventory,
    };

    await reportRef.set(reportPayload, SetOptions(merge: false));
    await FirebaseFirestore.instance
        .collection('admin_notifications')
        .doc('notification_$reportId')
        .set(reportPayload, SetOptions(merge: false));

    if (resetDrawerAfterSend) {
      await FirebaseFirestore.instance
          .collection('staff_cash_drawer')
          .doc(branchId)
          .set({
            'balance': openingCash,
            'lastResetAt': FieldValue.serverTimestamp(),
            'lastResetReportId': reportId,
            'updatedAt': DateTime.now(),
            'staffId': branchId,
            'branchId': branchId,
            'handledByStaffId': user.uid,
          }, SetOptions(merge: true));
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> _saveClosingInventorySnapshot(
    String _,
  ) async {
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    final snapshot = ids.isEmpty
        ? await FirebaseFirestore.instance
              .collection('staff_inventory')
              .where('staffId', isEqualTo: '')
              .get()
        : ids.length == 1
        ? await FirebaseFirestore.instance
              .collection('staff_inventory')
              .where('staffId', isEqualTo: ids.first)
              .get()
        : await FirebaseFirestore.instance
              .collection('staff_inventory')
              .where('staffId', whereIn: ids)
              .get();
    final closingReports = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isDeleted'] == true || data['isBundle'] == true) continue;

      final categoryName = data['name']?.toString() ?? '';
      if (categoryName.trim().isEmpty) continue;
      final sourceId = data['sourceInventoryId']?.toString() ?? doc.id;
      final items = (data['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (items.isEmpty) continue;

      final reportItems = <Map<String, dynamic>>[];
      final starting = <int>[];
      final remaining = <int>[];
      for (final item in items.take(3)) {
        final currentStock = _parseInt(item['stock']);
        final startingStock = _parseInt(
          item['startingStock'],
          fallback: currentStock,
        );
        final itemName = item['name']?.toString() ?? 'Item';
        final price = item['price'] ?? 0;
        starting.add(startingStock);
        remaining.add(currentStock);
        reportItems.add({
          'name': itemName,
          'variant': item['variant']?.toString() ?? '',
          'price': price,
          'quantity': startingStock,
          'remaining': currentStock,
          'sold': max(0, startingStock - currentStock),
        });
      }

      while (starting.length < 3) starting.add(0);
      while (remaining.length < 3) remaining.add(0);

      InventoryService().addRemainingStockForItem(
        itemName: categoryName,
        sourceInventoryId: sourceId,
        quantityA: remaining[0],
        quantityB: remaining[1],
        quantityC: remaining[2],
        startingA: starting[0],
        startingB: starting[1],
        startingC: starting[2],
        items: reportItems,
      );

      closingReports.add({
        'categoryName': categoryName,
        'sourceInventoryId': sourceId,
        'items': reportItems,
        'startingTotal': starting.fold<int>(0, (sum, qty) => sum + qty),
        'remainingTotal': remaining.fold<int>(0, (sum, qty) => sum + qty),
        'soldTotal': List.generate(
          3,
          (index) => max(0, starting[index] - remaining[index]),
        ).fold<int>(0, (sum, qty) => sum + qty),
      });
    }

    return closingReports;
  }

  String _generateSalesId() {
    final now = DateTime.now();
    final random = Random().nextInt(900) + 100;
    return 'S-${now.year}${now.month.toString().padLeft(2, "0")}${now.day.toString().padLeft(2, "0")}-${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}-$random';
  }

  Future<void> _notifyAdminOutOfStock({
    required String itemName,
    required String variantName,
    required String sourceInventoryId,
    required String staffInventoryDocId,
  }) async {
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final identity = [
      sourceInventoryId,
      staffInventoryDocId,
      itemName,
      variantName,
      dateKey,
    ].where((part) => part.trim().isNotEmpty).join('_');
    final safeId =
        'out_of_stock_${identity.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

    await FirebaseFirestore.instance
        .collection('admin_notifications')
        .doc(safeId)
        .set({
          'type': 'out_of_stock',
          'title': 'Item Out of Stock',
          'message': variantName.trim().isEmpty
              ? '$itemName is now out of stock.'
              : '$itemName - $variantName is now out of stock.',
          'itemName': itemName,
          'variantName': variantName,
          'sourceInventoryId': sourceInventoryId,
          'staffInventoryDocId': staffInventoryDocId,
          'staffId': _currentUserId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _finalizeOrder(
    double orderTotal,
    double paidAmount,
    double change,
    String salesId,
    List<Map<String, dynamic>> orderItems,
    String discountProofId,
  ) async {
    try {
      final receiptEntries = _validCartEntries(orderItems);
      final receiptItems = receiptEntries.map<Map<String, dynamic>>((entry) {
        final item = orderItems.firstWhere(
          (element) => _cartKey(element) == entry.key,
          orElse: () => {},
        );
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        return <String, dynamic>{
          'name': item.isEmpty
              ? _displayName(entry.key)
              : _itemDisplayLabel(item),
          'quantity': entry.value,
          'price': price,
          'lineTotal': price * entry.value,
        };
      }).toList();
      final subtotal = _cartTotal(orderItems);
      final discountAmount = (_seniorDiscount || _pwdDiscount)
          ? subtotal * 0.2
          : 0.0;
      final discountType = _seniorDiscount
          ? 'Senior'
          : (_pwdDiscount ? 'PWD' : 'None');

      final drawerId = _drawerIdForOrder(orderItems);
      if (_currentUserId != null && drawerId.isNotEmpty) {
        final drawerRef = FirebaseFirestore.instance
            .collection('staff_cash_drawer')
            .doc(drawerId);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final drawerSnapshot = await transaction.get(drawerRef);
          final currentBalance = drawerSnapshot.exists
              ? (drawerSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0.0
              : 0.0;
          if (change > 0 && currentBalance + 0.001 < change) {
            throw Exception(
              'Cash drawer is not enough for ₱${change.toStringAsFixed(2)} change.',
            );
          }
          final newCashBalance = currentBalance + paidAmount - change;
          transaction.set(drawerRef, {
            'balance': newCashBalance,
            'updatedAt': DateTime.now(),
            'staffId': drawerId,
            'branchId': drawerId,
            'handledByStaffId': _currentUserId,
          }, SetOptions(merge: true));
        });

        // Update inventory stock for each sold item
        final Map<String, Map<String, dynamic>> itemVariantQtys = {};

        for (final entry in _validCartEntries(orderItems)) {
          final item = orderItems.firstWhere(
            (element) => _cartKey(element) == entry.key,
            orElse: () => {},
          );
          if (item.isEmpty) continue;

          final itemName = item['name'] as String?;
          final variantName = item['variant'] as String?;
          final sourceInventoryId = item['sourceInventoryId']?.toString() ?? '';
          final staffInventoryDocId =
              item['staffInventoryDocId']?.toString() ?? '';
          final qtyRemoved = entry.value;

          if (itemName != null && itemName.isNotEmpty) {
            final remainingKey = sourceInventoryId.isNotEmpty
                ? sourceInventoryId
                : itemName;
            final variantIndex = item['variantSlot'] is num
                ? (item['variantSlot'] as num).toInt()
                : orderItems.indexWhere((e) {
                    return e['name'] == itemName &&
                        e['variant'] == variantName &&
                        (e['sourceInventoryId']?.toString() ?? '') ==
                            sourceInventoryId;
                  });
            final tracker = itemVariantQtys.putIfAbsent(
              remainingKey,
              () => {
                'itemName': itemName,
                'sourceInventoryId': sourceInventoryId,
                'variants': <int, int>{},
                'starting': <int, int>{},
                'remaining': <int, int>{},
                'items': <int, Map<String, dynamic>>{},
              },
            );
            final variants = tracker['variants'] as Map<int, int>;
            if (variantIndex >= 0) {
              variants[variantIndex] =
                  (variants[variantIndex] ?? 0) + qtyRemoved;
              final startingBySlot = tracker['starting'] as Map<int, int>;
              final remainingBySlot = tracker['remaining'] as Map<int, int>;
              final itemBySlot =
                  tracker['items'] as Map<int, Map<String, dynamic>>;
              final currentStock = _parseInt(item['stock']);
              final startingStock = _parseInt(
                item['startingStock'],
                fallback: currentStock,
              );
              startingBySlot[variantIndex] = max(
                startingBySlot[variantIndex] ?? 0,
                startingStock,
              );
              remainingBySlot[variantIndex] = max(
                0,
                (remainingBySlot[variantIndex] ?? currentStock) - qtyRemoved,
              );
              itemBySlot[variantIndex] = {
                'id': item['itemId'] ?? item['id'] ?? '',
                'name': (variantName?.isNotEmpty ?? false)
                    ? variantName
                    : itemName,
                'variant': variantName ?? '',
                'price': item['price'] ?? 0,
                'quantity': startingStock,
                'reducedQuantity': _parseInt(item['reducedQuantity']),
                'isBundle': item['isBundle'] == true,
                'isCoffee': item['isCoffee'] == true,
                'coffeeId': item['coffeeId'] ?? '',
                'coffeeSize': item['coffeeSize'] ?? '',
                'addonName': item['addonName'] ?? '',
                'sugarLevel': item['sugarLevel'] ?? '',
              };
            }

            final stockDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
            if (staffInventoryDocId.isNotEmpty) {
              final stockDoc = await FirebaseFirestore.instance
                  .collection('staff_inventory')
                  .doc(staffInventoryDocId)
                  .get();
              if (stockDoc.exists) stockDocs.add(stockDoc);
            }
            if (stockDocs.isEmpty) {
              var staffQuery = FirebaseFirestore.instance
                  .collection('staff_inventory')
                  .where('staffId', isEqualTo: _currentUserId)
                  .where('name', isEqualTo: itemName);
              if (sourceInventoryId.isNotEmpty) {
                staffQuery = staffQuery.where(
                  'sourceInventoryId',
                  isEqualTo: sourceInventoryId,
                );
              }
              final querySnapshot = await staffQuery.get();
              stockDocs.addAll(querySnapshot.docs);
            }

            for (final doc in stockDocs) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null) continue;

              if (data['isBundle'] == true) {
                final int currentBundleCount = data['bundleCount'] is num
                    ? (data['bundleCount'] as num).toInt()
                    : int.tryParse(data['bundleCount']?.toString() ?? '') ?? 0;
                final updatedBundleCount = max(
                  0,
                  currentBundleCount - qtyRemoved,
                );
                await doc.reference.update({'bundleCount': updatedBundleCount});
                if (updatedBundleCount == 0) {
                  await _notifyAdminOutOfStock(
                    itemName: itemName,
                    variantName: '',
                    sourceInventoryId: sourceInventoryId,
                    staffInventoryDocId: doc.id,
                  );
                }
                continue;
              }

              final itemsList = data['items'] as List<dynamic>? ?? [];
              final updatedItems = itemsList.map((itemData) {
                if (itemData is Map<String, dynamic>) {
                  final savedVariant = itemData['name']?.toString() ?? '';
                  final savedVariantAlt = itemData['variant']?.toString() ?? '';
                  final savedId = itemData['id']?.toString() ?? '';
                  final wantedId =
                      item['itemId']?.toString() ??
                      item['id']?.toString() ??
                      '';
                  final matchesVariant =
                      (wantedId.isNotEmpty && savedId == wantedId) ||
                      (wantedId.isEmpty &&
                          (savedVariant == (variantName ?? '') ||
                              savedVariantAlt == (variantName ?? '')));

                  if (matchesVariant) {
                    // Update the stock for this variant.
                    // If 'stock' field is missing, use 'startingStock' as the base.
                    int currentStock;
                    if (itemData.containsKey('stock') &&
                        itemData['stock'] != null) {
                      currentStock = itemData['stock'] is num
                          ? (itemData['stock'] as num).toInt()
                          : int.tryParse(itemData['stock']?.toString() ?? '') ??
                                0;
                    } else {
                      currentStock = itemData['startingStock'] is num
                          ? (itemData['startingStock'] as num).toInt()
                          : int.tryParse(
                                  itemData['startingStock']?.toString() ?? '',
                                ) ??
                                0;
                    }

                    final updatedStock = max(0, currentStock - qtyRemoved);
                    if (updatedStock == 0) {
                      unawaited(
                        _notifyAdminOutOfStock(
                          itemName: itemName,
                          variantName: variantName ?? '',
                          sourceInventoryId: sourceInventoryId,
                          staffInventoryDocId: doc.id,
                        ),
                      );
                    }
                    return {...itemData, 'stock': updatedStock};
                  }
                }
                return itemData;
              }).toList();

              await doc.reference.update({'items': updatedItems});
            }

            final trackedBundleItemName =
                (variantName != null && variantName.isNotEmpty)
                ? variantName
                : itemName;
            await _consumeBundleTrackedStock(
              itemName: trackedBundleItemName,
              quantity: qtyRemoved,
            );
          }
        }

        // Update remaining stock in InventoryService for each item sold
        for (final itemEntry in itemVariantQtys.values) {
          final itemName = itemEntry['itemName']?.toString() ?? '';
          final sourceInventoryId =
              itemEntry['sourceInventoryId']?.toString() ?? '';
          final variantQtys = itemEntry['variants'] as Map<int, int>;
          final startingBySlot = itemEntry['starting'] as Map<int, int>;
          final remainingBySlot = itemEntry['remaining'] as Map<int, int>;
          final itemBySlot =
              itemEntry['items'] as Map<int, Map<String, dynamic>>;

          int qtyA = 0, qtyB = 0, qtyC = 0;

          // Map variant indices to A, B, C positions
          for (final variantEntry in variantQtys.entries) {
            final variantIndex = variantEntry.key;
            final qty = variantEntry.value;

            if (variantIndex == 0)
              qtyA = qty;
            else if (variantIndex == 1)
              qtyB = qty;
            else if (variantIndex == 2)
              qtyC = qty;
          }

          // Compute revenue for this item entry after any discount allocation.
          final itemLineTotal = itemBySlot.entries.fold<double>(0.0, (
            sum,
            variantEntry,
          ) {
            final idx = variantEntry.key;
            final price =
                double.tryParse(
                  variantEntry.value['price']?.toString() ?? '0',
                ) ??
                0.0;
            final qty = variantQtys[idx] ?? 0;
            return sum + (price * qty);
          });
          final double revenueShare;
          if (subtotal > 0 && discountAmount > 0) {
            final discountShare = itemLineTotal / subtotal * discountAmount;
            revenueShare = (itemLineTotal - discountShare).clamp(
              0.0,
              double.infinity,
            );
          } else {
            revenueShare = itemLineTotal;
          }

          // Subtract from remaining stock
          if (qtyA > 0 || qtyB > 0 || qtyC > 0) {
            final existing = InventoryService().getEntryForItemToday(
              itemName,
              sourceInventoryId: sourceInventoryId,
            );
            if (existing != null) {
              InventoryService().addRemainingStockForItem(
                itemName: itemName,
                quantityA: remainingBySlot[0] ?? existing.safeRemainingA,
                quantityB: remainingBySlot[1] ?? existing.safeRemainingB,
                quantityC: remainingBySlot[2] ?? existing.safeRemainingC,
                startingA: max(
                  existing.safeStartingA,
                  startingBySlot[0] ?? existing.safeStartingA,
                ),
                startingB: max(
                  existing.safeStartingB,
                  startingBySlot[1] ?? existing.safeStartingB,
                ),
                startingC: max(
                  existing.safeStartingC,
                  startingBySlot[2] ?? existing.safeStartingC,
                ),
                saleRevenue: revenueShare,
                sourceInventoryId: sourceInventoryId,
                items: existing.safeItems.isNotEmpty
                    ? existing.safeItems
                    : [0, 1, 2]
                          .where((slot) => itemBySlot.containsKey(slot))
                          .map((slot) => itemBySlot[slot]!)
                          .toList(),
              );
            } else {
              InventoryService().addRemainingStockForItem(
                itemName: itemName,
                quantityA: remainingBySlot[0] ?? 0,
                quantityB: remainingBySlot[1] ?? 0,
                quantityC: remainingBySlot[2] ?? 0,
                startingA: startingBySlot[0] ?? 0,
                startingB: startingBySlot[1] ?? 0,
                startingC: startingBySlot[2] ?? 0,
                saleRevenue: revenueShare,
                sourceInventoryId: sourceInventoryId,
                items: [0, 1, 2]
                    .where((slot) => itemBySlot.containsKey(slot))
                    .map((slot) => itemBySlot[slot]!)
                    .toList(),
              );
            }
          }
        }

        // Record the order in completed_sales (separate from inventory)
        await FirebaseFirestore.instance.collection('completed_sales').add({
          'userId': _currentUserId,
          if (drawerId.isNotEmpty) 'branchId': drawerId,
          'salesId': salesId,
          'subtotal': subtotal,
          'discount': discountAmount,
          'discountType': discountType,
          'discountProofId': discountProofId.trim(),
          'total': orderTotal,
          'paidAmount': paidAmount,
          'change': change,
          'items': receiptEntries.map((entry) {
            final item = orderItems.firstWhere(
              (element) => _cartKey(element) == entry.key,
              orElse: () => {},
            );
            return {
              'name': item['name'],
              'variant': item['variant'],
              'price': item['price'],
              'quantity': entry.value,
              'category': item['category'] ?? '',
              'isBundle': item['isBundle'] == true,
              'isCoffee': item['isCoffee'] == true,
              'coffeeSize': item['coffeeSize'] ?? '',
              'coffeeId': item['coffeeId'] ?? '',
              'basePrice': item['basePrice'] ?? 0,
              'sizePriceDelta': item['sizePriceDelta'] ?? 0,
              'addonName': item['addonName'] ?? '',
              'addonPriceDelta': item['addonPriceDelta'] ?? 0,
              'sourceInventoryId': item['sourceInventoryId'] ?? '',
            };
          }).toList(),
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'completed',
        });
      }
      if (!mounted) return;
      // Success receipt is shown after inventory refresh.
      setState(() {
        _cart.clear();
        _showCartReview = false;
        _selectedGroupName = null;
        _seniorDiscount = false;
        _pwdDiscount = false;
        for (final controller in _qtyControllers.values) {
          controller.clear();
        }
      });

      // Refresh inventory data to show updated stock
      await InventoryService().initialize();
      if (mounted) {
        setState(() {
          entries = InventoryService().currentUserEntries;
        });
      }
      if (!mounted) return;
      await _showOrderSuccessDialog(
        salesId: salesId,
        items: receiptItems,
        subtotal: subtotal,
        discountAmount: discountAmount,
        discountType: discountType,
        total: orderTotal,
        paidAmount: paidAmount,
        change: change,
      );
    } catch (e) {
      if (mounted) {
        _showStyledSnackBar('Error finalizing order: $e', isError: true);
      }
    }
  }

  Future<void> _showOrderSuccessDialog({
    required String salesId,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    required String discountType,
    required double total,
    required double paidAmount,
    required double change,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _AppColors.primary.withOpacity(0.2),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_AppColors.primaryDark, _AppColors.primary],
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Order Successful',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Receipt ID: $salesId',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                    child: Column(
                      children: [
                        ...items.map((item) {
                          final qty = item['quantity'] as int? ?? 0;
                          final name = item['name']?.toString() ?? 'Item';
                          final lineTotal =
                              (item['lineTotal'] as num?)?.toDouble() ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _AppColors.cardBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${qty}x',
                                    style: const TextStyle(
                                      color: _AppColors.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: _AppColors.textMid,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '\u20B1${lineTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: _AppColors.textMid,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(color: _AppColors.divider, height: 22),
                        _SummaryRow(
                          label: 'Subtotal',
                          value: '\u20B1${subtotal.toStringAsFixed(2)}',
                        ),
                        if (discountAmount > 0) ...[
                          const SizedBox(height: 6),
                          _SummaryRow(
                            label: '$discountType discount',
                            value:
                                '- \u20B1${discountAmount.toStringAsFixed(2)}',
                            valueColor: const Color(0xFF2E7D32),
                          ),
                        ],
                        const SizedBox(height: 6),
                        _SummaryRow(
                          label: 'Total',
                          value: '\u20B1${total.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 6),
                        _SummaryRow(
                          label: 'Customer paid',
                          value: '\u20B1${paidAmount.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 6),
                        _SummaryRow(
                          label: 'Change',
                          value: '\u20B1${change.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext, rootNavigator: true).pop();
                      },
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: const Text('Back to Order'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

  Future<void> _savePendingOrder(List<Map<String, dynamic>> orderItems) async {
    if (!_cartHasValidItems(orderItems)) {
      _showStyledSnackBar('Add items to the cart first', isError: true);
      return;
    }
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showStyledSnackBar('User not authenticated', isError: true);
      return;
    }
    final pendingItems = <Map<String, dynamic>>[];
    final knownItems = _knownOrderItems(orderItems);
    for (final entry in _cart.entries) {
      final item = knownItems.firstWhere(
        (element) => _cartKey(element) == entry.key,
        orElse: () => {},
      );
      if (item.isEmpty) continue;
      pendingItems.add({
        'name': item['name']?.toString() ?? '',
        'variant': item['variant']?.toString() ?? '',
        'price': _parsePrice(item['price']),
        'quantity': entry.value,
        'itemId': item['itemId']?.toString() ?? item['id']?.toString() ?? '',
        'sourceInventoryId': item['sourceInventoryId']?.toString() ?? '',
        'groupKey': item['groupKey']?.toString() ?? '',
      });
    }
    if (pendingItems.isEmpty) {
      _showStyledSnackBar('No valid items to save', isError: true);
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('pending_orders').add({
        'userId': userId,
        'items': pendingItems,
        'discountType': _seniorDiscount
            ? 'Senior'
            : (_pwdDiscount ? 'PWD' : 'None'),
        'discountApplied': _seniorDiscount || _pwdDiscount,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _cart.clear();
        _cartItemLookup.clear();
        for (final controller in _qtyControllers.values) {
          controller.dispose();
        }
        _qtyControllers.clear();
        _seniorDiscount = false;
        _pwdDiscount = false;
        _showCartReview = false;
      });
      _showStyledSnackBar('Order saved as pending');
    } catch (e) {
      _showStyledSnackBar('Error saving pending order: $e', isError: true);
    }
  }

  Future<void> _showPendingOrders() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showStyledSnackBar('User not authenticated', isError: true);
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pending_orders')
          .where('userId', isEqualTo: userId)
          .get();
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTime =
              (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          final bTime =
              (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          return bTime.compareTo(aTime);
        });
      if (!mounted) return;
      if (docs.isEmpty) {
        _showStyledSnackBar('No pending orders found');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _buildStyledDialog(
            title: 'Pending Orders',
            icon: Icons.bookmark_rounded,
            dialogContext: dialogContext,
            child: Column(
              children: docs.map((doc) {
                final order = doc.data();
                final items = List<Map<String, dynamic>>.from(
                  order['items'] ?? [],
                );
                final createdAt = order['createdAt'] as Timestamp?;
                final timeStr = createdAt != null
                    ? '${createdAt.toDate().hour}:${createdAt.toDate().minute.toString().padLeft(2, '0')}'
                    : 'Unknown';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _AppColors.primary.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: _AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Order at $timeStr',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () async {
                              _restorePendingOrder(
                                items,
                                discountType:
                                    order['discountType']?.toString() ?? 'None',
                              );
                              await doc.reference.delete();
                              Navigator.pop(dialogContext);
                            },
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(right: 8, top: 2),
                                decoration: const BoxDecoration(
                                  color: _AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                '${item['name']} ${item['variant']} x${item['quantity']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _AppColors.textSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            await doc.reference.delete();
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            _showPendingOrders();
                          },
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 14,
                            color: Color(0xFFB71C1C),
                          ),
                          label: const Text(
                            'Delete',
                            style: TextStyle(
                              color: Color(0xFFB71C1C),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        },
      );
    } catch (e) {
      _showStyledSnackBar('Error loading pending orders: $e', isError: true);
    }
  }

  Future<void> _restoreLatestPendingOrder() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showStyledSnackBar('User not authenticated', isError: true);
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pending_orders')
          .where('userId', isEqualTo: userId)
          .get();
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTime =
              (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          final bTime =
              (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          return bTime.compareTo(aTime);
        });
      if (!mounted) return;
      if (docs.isEmpty) {
        _showStyledSnackBar('No pending orders found');
        return;
      }

      final order = docs.first.data();
      final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
      _restorePendingOrder(
        items,
        discountType: order['discountType']?.toString() ?? 'None',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCartPreviewSheet();
      });
    } catch (e) {
      _showStyledSnackBar('Error loading pending order: $e', isError: true);
    }
  }

  void _restorePendingOrder(
    List<Map<String, dynamic>> items, {
    String discountType = 'None',
  }) {
    setState(() {
      _cart.clear();
      final restoredOrderItems = <Map<String, dynamic>>[];
      final normalizedDiscount = discountType.trim().toLowerCase();
      _seniorDiscount = normalizedDiscount == 'senior';
      _pwdDiscount = normalizedDiscount == 'pwd';
      for (final controller in _qtyControllers.values) {
        controller.clear();
      }
      for (final item in items) {
        final restoredName = item['name']?.toString() ?? '';
        final restoredVariant = item['variant']?.toString() ?? '';
        final restoredPrice = _parsePrice(item['price']);
        final currentItem = _latestOrderItems.firstWhere((orderItem) {
          final sameName =
              (orderItem['name']?.toString() ?? '') == restoredName;
          final sameVariant =
              (orderItem['variant']?.toString() ?? '') == restoredVariant;
          final samePrice =
              (_parsePrice(orderItem['price']) - restoredPrice).abs() < 0.01;
          return sameName && sameVariant && samePrice;
        }, orElse: () => item);
        _cartItemLookup[_cartKey(currentItem)] = currentItem;
        if (!_latestOrderItems.any(
          (orderItem) => _cartKey(orderItem) == _cartKey(currentItem),
        )) {
          restoredOrderItems.add(currentItem);
        }
        final key = _cartKey(currentItem);
        final qty = item['quantity'] is int
            ? item['quantity'] as int
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
        if (qty > 0) _cart[key] = qty;
      }
      if (restoredOrderItems.isNotEmpty) {
        _latestOrderItems = [..._latestOrderItems, ...restoredOrderItems];
      }
      _selectedGroupName = null;
      _showCartReview = _cart.isNotEmpty;
    });
    for (final entry in _cart.entries) {
      _syncQtyController(entry.key, entry.value);
    }
    _showStyledSnackBar('Pending order restored');
  }

  Future<void> _showOrderHistory() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        _showStyledSnackBar('User not authenticated', isError: true);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('completed_sales')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      final docs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['userId'] == userId;
      }).toList();
      if (!mounted) return;
      if (docs.isEmpty) {
        _showStyledSnackBar('No transaction history found');
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _buildStyledDialog(
            title: 'Transaction History',
            icon: Icons.history_rounded,
            dialogContext: dialogContext,
            child: Column(
              children: docs.map((doc) {
                final data = doc.data();
                final items = List<Map<String, dynamic>>.from(
                  data['items'] ?? [],
                );
                final timestamp = data['timestamp'] as Timestamp?;
                final subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0;
                final total = (data['total'] as num?)?.toDouble() ?? 0;
                final paidAmount =
                    (data['paidAmount'] as num?)?.toDouble() ?? 0;
                final change = (data['change'] as num?)?.toDouble() ?? 0;
                final discount = (data['discount'] as num?)?.toDouble() ?? 0;
                final discountType = data['discountType']?.toString() ?? 'None';
                final discountProofId =
                    data['discountProofId']?.toString().trim() ?? '';
                final salesId = data['salesId']?.toString() ?? 'N/A';
                final transactionType = data['type']?.toString() ?? 'sale';
                final isRefund =
                    transactionType == 'refund' ||
                    data['status']?.toString() == 'Refund';
                final refundReason = data['reason']?.toString() ?? '';
                final refundSource = data['source']?.toString() ?? '';

                // Only show discount if there actually is one
                final hasDiscount = discount > 0.01 && discountType != 'None';

                final timeStr = timestamp != null
                    ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')} - ${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}'
                    : 'Unknown';
                final status = data['status']?.toString() ?? 'Completed';
                final statusColor = isRefund
                    ? const Color(0xFFE65100)
                    : const Color(0xFF4CAF50);
                final hasBundleItem = items.any(
                  (item) =>
                      item['isBundle'] == true ||
                      item['isBundle']?.toString().toLowerCase() == 'true',
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _AppColors.primary.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Transaction ID and time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID: $salesId',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _AppColors.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      timeStr,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _AppColors.textSoft,
                                      ),
                                    ),
                                    if (hasBundleItem) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFCDD2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Text(
                                          'Bundle',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFC62828),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: _AppColors.border, height: 8),
                      const SizedBox(height: 8),
                      // Items list with quantities
                      ...items
                          .where((item) => _parseInt(item['quantity']) > 0)
                          .map((item) {
                            final itemName = item['name'] ?? 'Unknown';
                            final itemVariant =
                                item['variant']?.isNotEmpty == true
                                ? item['variant']
                                : '';
                            final isCoffee = item['isCoffee'] == true;
                            final coffeeId =
                                item['coffeeId']?.toString().trim() ?? '';
                            final displayName = isCoffee
                                ? [
                                    itemName,
                                    if (coffeeId.isNotEmpty) '($coffeeId)',
                                    if (itemVariant.isNotEmpty)
                                      '- $itemVariant',
                                  ].join(' ')
                                : itemVariant.isNotEmpty
                                ? '$itemName ($itemVariant)'
                                : itemName;
                            final quantity = _parseInt(item['quantity']);
                            final price = _parsePrice(item['price']);
                            final lineTotal = quantity * price;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$quantity × $displayName',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _AppColors.textSoft,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '₱${lineTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _AppColors.textMid,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      if (isRefund && refundReason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _AppColors.border),
                          ),
                          child: Text(
                            'Reason${refundSource.isNotEmpty ? ' ($refundSource)' : ''}: $refundReason',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _AppColors.textSoft,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Divider(color: _AppColors.border, height: 8),
                      const SizedBox(height: 8),
                      // Totals
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Customer Payment:',
                            style: TextStyle(
                              fontSize: 11,
                              color: _AppColors.textSoft,
                            ),
                          ),
                          Text(
                            '₱${paidAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Discount ($discountType):',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                            Text(
                              '-₱${discount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                        if (discountProofId.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$discountType ID: $discountProofId',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _AppColors.textSoft,
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isRefund ? 'Refund Amount:' : 'Total Paid:',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _AppColors.primary,
                              ),
                            ),
                            Text(
                              '₱${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Change:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          Text(
                            '₱${change.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        },
      );
    } catch (e) {
      _showStyledSnackBar(
        'Error loading transaction history: $e',
        isError: true,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadRefundableShelfItems(
    List<Map<String, dynamic>> fallbackItems,
  ) async {
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    if (ids.isEmpty) return _knownOrderItems(fallbackItems);

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'staff_inventory',
    );
    query = ids.length == 1
        ? query.where('staffId', isEqualTo: ids.first)
        : query.where('staffId', whereIn: ids);
    final snapshot = await query.get();
    final docs = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isDeleted'] == true || data['isBundle'] == true) continue;
      final sourceId = data['sourceInventoryId']?.toString() ?? doc.id;

      if (data['isCoffee'] == true) {
        final basePrice = _parsePrice(data['basePrice']);
        final rawSizes = (data['sizes'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((size) => Map<String, dynamic>.from(size))
            .where((size) => (size['name']?.toString().trim() ?? '').isNotEmpty)
            .toList();
        final sizes = rawSizes.isEmpty
            ? [
                {'name': 'Regular', 'priceDelta': 0},
              ]
            : rawSizes;
        final addons = (data['addonOptions'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((addon) => Map<String, dynamic>.from(addon))
            .where(
              (addon) => (addon['name']?.toString().trim() ?? '').isNotEmpty,
            )
            .toList();
        final coffeeItems = <Map<String, dynamic>>[];
        for (var sizeIndex = 0; sizeIndex < sizes.length; sizeIndex++) {
          final size = sizes[sizeIndex];
          final sizeName = size['name']?.toString().trim() ?? 'Regular';
          final sizeDelta = _parsePrice(size['priceDelta']);
          final sizePrice = basePrice + sizeDelta;
          coffeeItems.add({
            'id': '$sourceId|size:$sizeName|addon:none',
            'name': data['name'] ?? 'Coffee',
            'variant': sizeName,
            'flavor': data['name'] ?? 'Coffee',
            'price': sizePrice,
            'stock': 999,
            'startingStock': 999,
            'isCoffee': true,
            'coffeeSize': sizeName,
            'addonName': '',
            'coffeeId': data['coffeeId'] ?? '',
            'variantSlot': sizeIndex,
          });
          for (final addon in addons) {
            final addonName = addon['name']?.toString().trim() ?? '';
            final addonDelta = _parsePrice(addon['priceDelta']);
            coffeeItems.add({
              'id':
                  '$sourceId|size:$sizeName|addon:${addonName.toLowerCase().replaceAll(' ', '_')}',
              'name': data['name'] ?? 'Coffee',
              'variant': '$sizeName + $addonName',
              'flavor': data['name'] ?? 'Coffee',
              'price': sizePrice + addonDelta,
              'stock': 999,
              'startingStock': 999,
              'isCoffee': true,
              'coffeeSize': sizeName,
              'addonName': addonName,
              'coffeeId': data['coffeeId'] ?? '',
              'variantSlot': sizeIndex,
            });
          }
        }
        docs.add({
          ...data,
          'staffDocId': doc.id,
          'sourceInventoryId': sourceId,
          'items': coffeeItems,
        });
        continue;
      }

      docs.add({...data, 'staffDocId': doc.id, 'sourceInventoryId': sourceId});
    }

    final loadedItems = _orderItemsFromDocs(docs);
    return loadedItems.isEmpty ? _knownOrderItems(fallbackItems) : loadedItems;
  }

  Future<void> _showRefundDialog(List<Map<String, dynamic>> orderItems) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showStyledSnackBar('User not authenticated', isError: true);
      return;
    }

    final refundableItems = await _loadRefundableShelfItems(orderItems);
    final categoryItemsByKey = <String, Map<String, dynamic>>{};
    final coffeeItemsByKey = <String, Map<String, dynamic>>{};
    for (final item in refundableItems.where((item) {
      if (item['isBundle'] == true) return false;
      final stock = _parseInt(
        item['stock'],
        fallback: _parseInt(item['startingStock']),
      );
      return stock > 0;
    })) {
      if (item['isCoffee'] == true) {
        coffeeItemsByKey.putIfAbsent(_cartKey(item), () => item);
      } else {
        categoryItemsByKey.putIfAbsent(_cartKey(item), () => item);
      }
    }
    final categoryItems = categoryItemsByKey.values.toList();
    final coffeeItems = coffeeItemsByKey.values.toList();
    final bundleOptions = <Map<String, dynamic>>[];

    try {
      final ids = _staffInventoryIds
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .take(10)
          .toList();
      Query<Map<String, dynamic>> bundleQuery = FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('isBundle', isEqualTo: true);
      bundleQuery = ids.isEmpty
          ? bundleQuery.where('staffId', isEqualTo: userId)
          : ids.length == 1
          ? bundleQuery.where('staffId', isEqualTo: ids.first)
          : bundleQuery.where('staffId', whereIn: ids);
      final bundleSnapshot = await bundleQuery.get();

      for (final doc in bundleSnapshot.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;
        final bundleCount = _parseInt(data['bundleCount']);
        if (bundleCount <= 0) continue;
        final instances = _bundleInstancesFromData(data);
        for (
          var instanceIndex = 0;
          instanceIndex < instances.length;
          instanceIndex++
        ) {
          final instance = instances[instanceIndex];
          final status =
              instance['status']?.toString().toLowerCase() ?? 'available';
          if (status != 'available') continue;
          final items = instance['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final originalQty = _parseInt(item['quantity'], fallback: 1);
            final refundedQty = _parseInt(item['refunded']);
            final maxRefundQty = max(0, originalQty - refundedQty);
            if (maxRefundQty <= 0) continue;
            bundleOptions.add({
              'docRef': doc.reference,
              'docId': doc.id,
              'bundleName': data['name']?.toString() ?? 'Bundle',
              'bundleId': data['bundleId']?.toString() ?? '',
              'instanceIndex': instanceIndex,
              'instanceNumber': instance['number'] ?? instanceIndex + 1,
              'instanceId':
                  instance['id'] ??
                  _bundleInstanceId(
                    data['bundleId']?.toString() ?? '',
                    instanceIndex,
                  ),
              'itemName': item['name']?.toString() ?? 'Item',
              'price': _parsePrice(item['price']),
              'originalQty': originalQty,
              'refundedQty': refundedQty,
              'maxRefundQty': maxRefundQty,
            });
          }
        }
      }
    } catch (e) {
      _showStyledSnackBar('Error loading refund options: $e', isError: true);
      return;
    }

    if (!mounted) return;
    if (categoryItems.isEmpty && bundleOptions.isEmpty && coffeeItems.isEmpty) {
      _showStyledSnackBar('No refundable items found', isError: true);
      return;
    }

    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    var source = categoryItems.isNotEmpty
        ? 'category'
        : bundleOptions.isNotEmpty
        ? 'bundle'
        : 'coffee';
    var selectedCategoryKey = categoryItems.isNotEmpty
        ? _cartKey(categoryItems.first)
        : null;
    var selectedCoffeeKey = coffeeItems.isNotEmpty
        ? _cartKey(coffeeItems.first)
        : null;
    var selectedBundleIndex = bundleOptions.isNotEmpty ? 0 : null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (source == 'category' && categoryItems.isEmpty) {
              source = bundleOptions.isNotEmpty ? 'bundle' : 'coffee';
              selectedBundleIndex = source == 'bundle' ? 0 : null;
            }
            if (source == 'bundle' && bundleOptions.isEmpty) {
              source = categoryItems.isNotEmpty ? 'category' : 'coffee';
              selectedCategoryKey = source == 'category'
                  ? _cartKey(categoryItems.first)
                  : null;
            }
            if (source == 'coffee' && coffeeItems.isEmpty) {
              source = categoryItems.isNotEmpty ? 'category' : 'bundle';
              selectedCoffeeKey = null;
            }
            final isCategory = source == 'category';
            final isCoffee = source == 'coffee';
            final validCategoryKeys = categoryItems.map(_cartKey).toSet();
            final validCoffeeKeys = coffeeItems.map(_cartKey).toSet();
            if (selectedCategoryKey != null &&
                !validCategoryKeys.contains(selectedCategoryKey)) {
              selectedCategoryKey = categoryItems.isNotEmpty
                  ? _cartKey(categoryItems.first)
                  : null;
            }
            if (selectedCoffeeKey != null &&
                !validCoffeeKeys.contains(selectedCoffeeKey)) {
              selectedCoffeeKey = coffeeItems.isNotEmpty
                  ? _cartKey(coffeeItems.first)
                  : null;
            }
            if (selectedBundleIndex != null &&
                (selectedBundleIndex! < 0 ||
                    selectedBundleIndex! >= bundleOptions.length)) {
              selectedBundleIndex = bundleOptions.isNotEmpty ? 0 : null;
            }
            final selectedCategoryItem = selectedCategoryKey == null
                ? null
                : categoryItems.firstWhere(
                    (item) => _cartKey(item) == selectedCategoryKey,
                    orElse: () => {},
                  );
            final selectedBundleOption = selectedBundleIndex == null
                ? null
                : bundleOptions[selectedBundleIndex!];
            final selectedCoffeeItem = selectedCoffeeKey == null
                ? null
                : coffeeItems.firstWhere(
                    (item) => _cartKey(item) == selectedCoffeeKey,
                    orElse: () => {},
                  );
            final selectedShelfItem = isCoffee
                ? selectedCoffeeItem
                : selectedCategoryItem;
            final maxQty = isCategory || isCoffee
                ? _parseInt(
                    selectedShelfItem?['stock'],
                    fallback: _parseInt(selectedShelfItem?['startingStock']),
                  )
                : selectedBundleOption?['maxRefundQty'] as int? ?? 0;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 660),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _AppColors.primary.withOpacity(0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Refund Item',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: _AppColors.textMid,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                            color: _AppColors.textSoft,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: source,
                        isExpanded: true,
                        decoration: _refundInputDecoration(
                          'Refund source',
                          Icons.swap_horiz_rounded,
                        ),
                        items: [
                          if (categoryItems.isNotEmpty)
                            const DropdownMenuItem(
                              value: 'category',
                              child: Text('Categories'),
                            ),
                          if (bundleOptions.isNotEmpty)
                            const DropdownMenuItem(
                              value: 'bundle',
                              child: Text('Bundle'),
                            ),
                          if (coffeeItems.isNotEmpty)
                            const DropdownMenuItem(
                              value: 'coffee',
                              child: Text('Coffee'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            source = value;
                            if (source == 'category') {
                              selectedCategoryKey = categoryItems.isNotEmpty
                                  ? _cartKey(categoryItems.first)
                                  : null;
                            } else if (source == 'coffee') {
                              selectedCoffeeKey = coffeeItems.isNotEmpty
                                  ? _cartKey(coffeeItems.first)
                                  : null;
                            } else {
                              selectedBundleIndex = bundleOptions.isNotEmpty
                                  ? 0
                                  : null;
                            }
                            qtyController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (isCategory || isCoffee)
                        DropdownButtonFormField<String>(
                          value: isCoffee
                              ? selectedCoffeeKey
                              : selectedCategoryKey,
                          isExpanded: true,
                          decoration: _refundInputDecoration(
                            isCoffee ? 'Coffee item' : 'Category item',
                            isCoffee
                                ? Icons.local_cafe_rounded
                                : Icons.category_rounded,
                          ),
                          items: (isCoffee ? coffeeItems : categoryItems).map((
                            item,
                          ) {
                            final key = _cartKey(item);
                            return DropdownMenuItem(
                              value: key,
                              child: Text(
                                _itemDisplayLabel(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              if (isCoffee) {
                                selectedCoffeeKey = value;
                              } else {
                                selectedCategoryKey = value;
                              }
                              qtyController.clear();
                            });
                          },
                        )
                      else
                        DropdownButtonFormField<int>(
                          value: selectedBundleIndex,
                          isExpanded: true,
                          decoration: _refundInputDecoration(
                            'Bundle item',
                            Icons.inventory_2_rounded,
                          ),
                          items: bundleOptions.asMap().entries.map((entry) {
                            final option = entry.value;
                            return DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                '${option['bundleName']} · Bundle #${option['instanceNumber']} · ${option['itemName']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedBundleIndex = value;
                              qtyController.clear();
                            });
                          },
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration:
                            _refundInputDecoration(
                              'Returned quantity',
                              Icons.undo_rounded,
                            ).copyWith(
                              helperText: maxQty > 0
                                  ? 'Max refundable: $maxQty'
                                  : 'No quantity available',
                            ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _refundInputDecoration(
                          'Reason',
                          Icons.edit_note_rounded,
                        ).copyWith(hintText: 'e.g. damaged item, wrong order'),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final qty = _parseInt(qtyController.text);
                              final reason = reasonController.text.trim();
                              if (qty <= 0) {
                                _showStyledSnackBar(
                                  'Enter refund quantity',
                                  isError: true,
                                );
                                return;
                              }
                              if (qty > maxQty) {
                                _showStyledSnackBar(
                                  'Quantity cannot exceed $maxQty',
                                  isError: true,
                                );
                                return;
                              }
                              if (reason.isEmpty) {
                                _showStyledSnackBar(
                                  'Enter refund reason',
                                  isError: true,
                                );
                                return;
                              }

                              if (isCategory || isCoffee) {
                                if (selectedShelfItem == null ||
                                    selectedShelfItem.isEmpty) {
                                  _showStyledSnackBar(
                                    'Select an item to refund',
                                    isError: true,
                                  );
                                  return;
                                }
                                await _confirmCategoryRefund(
                                  item: selectedShelfItem,
                                  quantity: qty,
                                  reason: reason,
                                  source: isCoffee ? 'Coffee' : 'Categories',
                                );
                              } else {
                                if (selectedBundleOption == null) {
                                  _showStyledSnackBar(
                                    'Select a bundle item to refund',
                                    isError: true,
                                  );
                                  return;
                                }
                                await _confirmBundleRefund(
                                  option: selectedBundleOption,
                                  quantity: qty,
                                  reason: reason,
                                );
                              }

                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              if (!mounted) return;
                              _showStyledSnackBar(
                                'Refund failed: $e',
                                isError: true,
                              );
                            }
                          },
                          icon: const Icon(Icons.assignment_return_rounded),
                          label: const Text('Confirm Refund'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
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

    qtyController.dispose();
    reasonController.dispose();
  }

  InputDecoration _refundInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _AppColors.primary, size: 18),
      labelStyle: const TextStyle(color: _AppColors.primary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AppColors.border, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AppColors.primary, width: 2),
      ),
      filled: true,
      fillColor: _AppColors.cardBg,
    );
  }

  String _generateRefundId() {
    final now = DateTime.now();
    final random = Random().nextInt(900) + 100;
    return 'R-${now.year}${now.month.toString().padLeft(2, "0")}${now.day.toString().padLeft(2, "0")}-${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}-$random';
  }

  Future<void> _confirmCategoryRefund({
    required Map<String, dynamic> item,
    required int quantity,
    required String reason,
    String source = 'Categories',
  }) async {
    final itemName = item['name']?.toString() ?? '';
    final variantName = item['variant']?.toString() ?? '';
    final price = _parsePrice(item['price']);

    await _saveRefundTransaction(
      source: source,
      reason: reason,
      amount: price * quantity,
      items: [
        {
          'name': itemName,
          'variant': variantName,
          'price': price,
          'quantity': quantity,
          'returnedToStock': false,
          'isBundle': false,
        },
      ],
    );

    _showStyledSnackBar('Refund recorded');
  }

  Future<void> _confirmBundleRefund({
    required Map<String, dynamic> option,
    required int quantity,
    required String reason,
  }) async {
    final docRef = option['docRef'] as DocumentReference<Map<String, dynamic>>;
    final instanceIndex = option['instanceIndex'] as int;
    final itemName = option['itemName']?.toString() ?? 'Item';
    final price = _parsePrice(option['price']);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = snapshot.data();
      if (data == null) {
        throw Exception('Bundle not found');
      }

      final instances = _bundleInstancesFromData(data);
      if (instanceIndex < 0 || instanceIndex >= instances.length) {
        throw Exception('Bundle instance not found');
      }

      final instance = instances[instanceIndex];
      final items = instance['items'] as List<dynamic>? ?? [];
      var itemFound = false;
      final updatedItems = items.map((item) {
        if (item is! Map<String, dynamic>) return item;
        if ((item['name']?.toString() ?? '') != itemName) return item;

        itemFound = true;
        final originalQty = _parseInt(item['quantity'], fallback: 1);
        final currentRefunded = _parseInt(item['refunded']);
        final nextRefunded = currentRefunded + quantity;
        if (nextRefunded > originalQty) {
          throw Exception('Refund quantity is greater than bundle item count');
        }
        return {...item, 'refunded': nextRefunded};
      }).toList();

      if (!itemFound) {
        throw Exception('Bundle item not found');
      }

      instances[instanceIndex] = {
        ...instance,
        'items': updatedItems,
        'lastRefundedAt': Timestamp.now(),
      };

      transaction.update(docRef, {
        'bundleInstances': instances,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _saveRefundTransaction(
      source: 'Bundle',
      reason: reason,
      amount: price * quantity,
      items: [
        {
          'name': option['bundleName']?.toString() ?? 'Bundle',
          'variant': itemName,
          'price': price,
          'quantity': quantity,
          'bundleInstance': option['instanceNumber'],
          'bundleInstanceId': option['instanceId'],
          'isBundle': true,
        },
      ],
    );

    _showStyledSnackBar('Bundle refund recorded');
  }

  Future<void> _saveRefundTransaction({
    required String source,
    required String reason,
    required double amount,
    required List<Map<String, dynamic>> items,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final firestore = FirebaseFirestore.instance;
    final refundAmount = amount.abs();
    final salesRef = firestore.collection('completed_sales').doc();
    final drawerId = _activeDrawerId();
    final drawerRef = firestore
        .collection('staff_cash_drawer')
        .doc(drawerId.isNotEmpty ? drawerId : userId);

    final balanceAfterRefund = await firestore.runTransaction<double>((
      transaction,
    ) async {
      final drawerSnapshot = await transaction.get(drawerRef);
      final currentBalance =
          (drawerSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final newBalance = currentBalance - refundAmount;

      transaction.set(salesRef, {
        'userId': userId,
        'salesId': _generateRefundId(),
        'type': 'refund',
        'source': source,
        'reason': reason,
        'subtotal': -refundAmount,
        'discount': 0.0,
        'discountType': 'None',
        'total': -refundAmount,
        'paidAmount': 0.0,
        'change': 0.0,
        'cashDrawerDelta': -refundAmount,
        'cashDrawerBalanceAfter': newBalance,
        if (drawerId.isNotEmpty) 'branchId': drawerId,
        'items': items,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'Refund',
      });

      transaction.set(drawerRef, {
        'balance': newBalance,
        'updatedAt': FieldValue.serverTimestamp(),
        'staffId': drawerId.isNotEmpty ? drawerId : userId,
        'handledByStaffId': userId,
      }, SetOptions(merge: true));

      return newBalance;
    });

    if (mounted) {
      setState(() {
        _cashDrawer = balanceAfterRefund;
      });
    }
  }

  Future<void> _showOrderConfirmationDialog(
    List<Map<String, dynamic>> orderItems,
  ) async {
    if (!_cartHasValidItems(orderItems)) {
      _showStyledSnackBar('Add items to the cart first', isError: true);
      return;
    }
    final validCartEntries = _validCartEntries(orderItems);
    final salesId = _generateSalesId();
    final paymentController = TextEditingController();
    final discountProofController = TextEditingController();
    final hasDiscount = _seniorDiscount || _pwdDiscount;
    final discountProofLabel = _seniorDiscount ? 'Senior ID' : 'PWD ID';
    double paidAmount = 0;
    double change = 0;
    final totalDue = _discountedTotal(orderItems);

    final result = await showDialog<_OrderConfirmationResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            paidAmount =
                double.tryParse(
                  paymentController.text.trim().replaceAll(
                    RegExp(r'[^0-9.]'),
                    '',
                  ),
                ) ??
                0;
            change = paidAmount - totalDue;
            final hasRequiredProof =
                !hasDiscount || discountProofController.text.trim().isNotEmpty;
            final hasEnoughCashForChange =
                change <= 0 || _cashDrawer + 0.001 >= change;
            final canConfirm =
                paidAmount >= totalDue &&
                hasRequiredProof &&
                hasEnoughCashForChange;
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
                      color: _AppColors.primary.withOpacity(0.2),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dialog header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _AppColors.primaryDark,
                            _AppColors.primaryLight,
                          ],
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
                              Icons.receipt_long_rounded,
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
                                  'Confirm Order',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'ID: $salesId',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Items list
                            ...validCartEntries.map((entry) {
                              final item = orderItems.firstWhere(
                                (element) => _cartKey(element) == entry.key,
                                orElse: () => {},
                              );
                              final price =
                                  (item['price'] as num?)?.toDouble() ?? 0;
                              final lineTotal = price * entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.value}x ${_formatCartEntryName(entry.key, orderItems)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: _AppColors.textMid,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '₱${lineTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: _AppColors.textMid,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(
                              color: _AppColors.divider,
                              height: 24,
                            ),
                            // Totals
                            _OrderRow(
                              label: 'Subtotal',
                              value:
                                  '₱${_cartTotal(orderItems).toStringAsFixed(2)}',
                            ),
                            if (_seniorDiscount || _pwdDiscount) ...[
                              const SizedBox(height: 6),
                              _OrderRow(
                                label: _discountLabel,
                                value:
                                    '- ₱${_discountValue(orderItems).toStringAsFixed(2)}',
                                isDiscount: true,
                              ),
                              const SizedBox(height: 14),
                              _PinkTextField(
                                controller: discountProofController,
                                label: '$discountProofLabel / Proof ID',
                                hint: _seniorDiscount
                                    ? 'Enter senior citizen ID'
                                    : 'Enter PWD ID',
                                icon: Icons.badge_outlined,
                                keyboardType: TextInputType.text,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _AppColors.primary.withOpacity(0.08),
                                    _AppColors.primaryLight.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _AppColors.border,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Due',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _AppColors.primary,
                                    ),
                                  ),
                                  Text(
                                    '₱${totalDue.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: _AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _PinkTextField(
                              controller: paymentController,
                              label: 'Customer Paid',
                              hint: '0.00',
                              icon: Icons.payments_outlined,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              prefixText: '₱',
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: change >= 0
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Change',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: change >= 0
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFB71C1C),
                                    ),
                                  ),
                                  Text(
                                    '₱${(change >= 0 ? change : 0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: change >= 0
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFB71C1C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.wallet_rounded,
                                  size: 14,
                                  color: _AppColors.textSoft,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Cash Drawer: ₱${_cashDrawer.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _AppColors.textSoft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (change > 0 && !hasEnoughCashForChange) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFFCDD2),
                                  ),
                                ),
                                child: Text(
                                  'Cash drawer is not enough for ₱${change.toStringAsFixed(2)} change.',
                                  style: const TextStyle(
                                    color: Color(0xFFB71C1C),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
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
                              onPressed: () {
                                Navigator.of(
                                  dialogContext,
                                  rootNavigator: true,
                                ).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _AppColors.primary,
                                side: const BorderSide(
                                  color: _AppColors.border,
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
                              onPressed: canConfirm
                                  ? () {
                                      final finalPaidAmount =
                                          double.tryParse(
                                            paymentController.text
                                                .trim()
                                                .replaceAll(
                                                  RegExp(r'[^0-9.]'),
                                                  '',
                                                ),
                                          ) ??
                                          0;
                                      Navigator.of(
                                        dialogContext,
                                        rootNavigator: true,
                                      ).pop(
                                        _OrderConfirmationResult(
                                          totalDue: totalDue,
                                          paidAmount: finalPaidAmount,
                                          change: finalPaidAmount - totalDue,
                                          salesId: salesId,
                                          discountProofId:
                                              discountProofController.text,
                                        ),
                                      );
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _AppColors.primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _AppColors.border,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text(
                                'Confirm',
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
    await Future<void>.delayed(const Duration(milliseconds: 300));
    paymentController.dispose();
    discountProofController.dispose();
    if (result == null) return;
    if (!mounted) return;
    await _finalizeOrder(
      result.totalDue,
      result.paidAmount,
      result.change,
      result.salesId,
      orderItems,
      result.discountProofId,
    );
  }

  // ─── Reusable styled dialog ─────────────────────────────────────────────
  Widget _buildStyledDialog({
    required String title,
    required IconData icon,
    required BuildContext dialogContext,
    required Widget child,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxHeight: 580),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _AppColors.primary.withOpacity(0.18),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_AppColors.primaryDark, _AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.cardBg,
                    foregroundColor: _AppColors.primary,
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
  }

  // ─── Build Header ────────────────────────────────────────────────────────
  Widget _buildPageHeader() {
    return FadeTransition(
      opacity: _headerFade,
      child: SlideTransition(
        position: _headerSlide,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_AppColors.primaryDark, _AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _AppColors.primary.withOpacity(0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sales Process',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _AppColors.primary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      _formattedToday(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _AppColors.textSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formattedToday() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  void _showCartPreviewSheet() {
    final orderItems = _knownOrderItems(_latestOrderItems);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.46,
          minChildSize: 0.28,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: _AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: _buildCartReviewPanel(orderItems),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOrderSearchField() {
    return TextField(
      controller: _orderSearchController,
      onChanged: (value) => setState(() => _orderSearchQuery = value.trim()),
      decoration: InputDecoration(
        hintText: _selectedGroupName != null
            ? (_showBundleView ? 'Search bundle items' : 'Search items')
            : _showBundleView
            ? 'Search bundles'
            : _showCoffeeView
            ? 'Search coffee'
            : 'Search categories',
        prefixIcon: const Icon(Icons.search_rounded, color: _AppColors.primary),
        suffixIcon: _orderSearchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _orderSearchController.clear();
                  setState(() => _orderSearchQuery = '');
                },
                icon: const Icon(Icons.close_rounded),
                color: _AppColors.textSoft,
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _AppColors.border, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _AppColors.primary, width: 1.6),
        ),
      ),
    );
  }

  // ─── Build Budget Card ────────────────────────────────────────────────────
  Widget _buildBudgetCard() {
    return FadeTransition(
      opacity: _budgetCardFade,
      child: SlideTransition(
        position: _budgetCardSlide,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                _AppColors.primaryDark,
                _AppColors.primary,
                _AppColors.primaryLight,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _AppColors.primary.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -34,
                right: -24,
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
              ),
              Positioned(
                bottom: -44,
                left: -34,
                child: Container(
                  width: 124,
                  height: 124,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Cash Drawer',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Available Drawer Cash',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _cashDrawer > 0
                          ? '₱${_cashDrawer.toStringAsFixed(2)}'
                          : '₱0.00',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _cashDrawer > 0 ? 30 : 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: _cashDrawer > 0 ? -0.5 : 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build Order Section ─────────────────────────────────────────────────
  Widget _buildOrderSection() {
    if (_showCartReview) {
      final orderItems = _knownOrderItems(_latestOrderItems);
      return _buildCashierOrderFlow(
        orderItems: orderItems,
        groupedOrderItems: _groupOrderItemsByName(orderItems),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _staffInventoryStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState('Error loading order items.');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: _AppColors.primary),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        return StreamBuilder<QuerySnapshot>(
          stream: _rootSalesInventoryStream,
          builder: (context, rootSnapshot) {
            if (rootSnapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: _AppColors.primary),
                ),
              );
            }
            final activeRootById = <String, Map<String, dynamic>>{};
            final activeRootByName = <String, Map<String, dynamic>>{};
            for (final rootDoc in rootSnapshot.data?.docs ?? []) {
              final rootData = rootDoc.data() as Map<String, dynamic>?;
              if (rootData == null || rootData['isDeleted'] == true) continue;
              activeRootById[rootDoc.id] = rootData;
              final rootName = rootData['name']
                  ?.toString()
                  .trim()
                  .toLowerCase();
              if (rootName != null && rootName.isNotEmpty) {
                activeRootByName[rootName] = rootData;
              }
            }

            String itemKey(Map<String, dynamic> item) =>
                '${item['name'] ?? ''}|${item['price'] ?? ''}'.toLowerCase();

            final filteredDocs = <Map<String, dynamic>>[];
            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null || data['isDeleted'] == true) continue;
              final isBundle = data['isBundle'] == true;
              final isCoffee = data['isCoffee'] == true;
              if (_showCoffeeView) {
                if (!isCoffee) continue;
              } else if (isBundle != _showBundleView || isCoffee) {
                continue;
              }

              final sourceId = data['sourceInventoryId']?.toString() ?? '';
              final name = data['name']?.toString().trim().toLowerCase() ?? '';
              final rootData =
                  activeRootById[sourceId] ??
                  activeRootByName[name] ??
                  (isCoffee ? data : null);
              if (rootData == null) continue;

              if (isCoffee) {
                final basePrice = _parsePrice(data['basePrice']);
                final sizes = (data['sizes'] as List<dynamic>? ?? [])
                    .whereType<Map>()
                    .map((size) => Map<String, dynamic>.from(size))
                    .where(
                      (size) =>
                          (size['name']?.toString().trim() ?? '').isNotEmpty,
                    )
                    .toList();
                final coffeeSizes = sizes.isEmpty
                    ? [
                        {'name': 'Regular', 'priceDelta': 0},
                      ]
                    : sizes;
                final addonByName = <String, Map<String, dynamic>>{};
                for (final addon
                    in (data['addonOptions'] as List<dynamic>? ?? [])
                        .whereType<Map>()) {
                  final name = addon['name']?.toString().trim() ?? '';
                  if (name.isEmpty) continue;
                  addonByName.putIfAbsent(
                    name,
                    () => Map<String, dynamic>.from(addon),
                  );
                }
                if (!identical(rootData, data)) {
                  for (final addon
                      in (rootData['addonOptions'] as List<dynamic>? ?? [])
                          .whereType<Map>()) {
                    final name = addon['name']?.toString().trim() ?? '';
                    if (name.isEmpty) continue;
                    addonByName.putIfAbsent(
                      name,
                      () => Map<String, dynamic>.from(addon),
                    );
                  }
                }
                final addonOptions = addonByName.values.toList();
                final coffeeItems = <Map<String, dynamic>>[];
                for (
                  var sizeIndex = 0;
                  sizeIndex < coffeeSizes.length;
                  sizeIndex++
                ) {
                  final size = coffeeSizes[sizeIndex];
                  final sizeName = size['name']?.toString().trim() ?? 'Regular';
                  final delta = _parsePrice(size['priceDelta']);
                  final baseVariantPrice = basePrice + delta;
                  final itemSourceId = sourceId.isNotEmpty ? sourceId : doc.id;

                  coffeeItems.add({
                    'id': '$itemSourceId|size:$sizeName|addon:none',
                    'name': data['name'] ?? 'Coffee',
                    'variant': sizeName,
                    'flavor': data['name'] ?? 'Coffee',
                    'price': baseVariantPrice,
                    'basePrice': basePrice,
                    'sizePriceDelta': delta,
                    'addonName': '',
                    'addonPriceDelta': 0,
                    'stock': 999,
                    'startingStock': 999,
                    'imageUrl': data['imageUrl']?.toString() ?? '',
                    'categoryImageUrl': data['imageUrl']?.toString() ?? '',
                    'isCoffee': true,
                    'coffeeId': data['coffeeId'] ?? '',
                    'coffeeSize': sizeName,
                    'variantSlot': sizeIndex,
                  });

                  for (final addon in addonOptions) {
                    final addonName = addon['name']?.toString().trim() ?? '';
                    if (addonName.isEmpty) continue;
                    final addonDelta = _parsePrice(addon['priceDelta']);
                    coffeeItems.add({
                      'id':
                          '$itemSourceId|size:$sizeName|addon:${addonName.toLowerCase().replaceAll(' ', '_')}',
                      'name': data['name'] ?? 'Coffee',
                      'variant': '$sizeName + $addonName',
                      'flavor': data['name'] ?? 'Coffee',
                      'price': baseVariantPrice + addonDelta,
                      'basePrice': basePrice,
                      'sizePriceDelta': delta,
                      'addonName': addonName,
                      'addonPriceDelta': addonDelta,
                      'stock': 999,
                      'startingStock': 999,
                      'imageUrl': data['imageUrl']?.toString() ?? '',
                      'categoryImageUrl': data['imageUrl']?.toString() ?? '',
                      'isCoffee': true,
                      'coffeeId': data['coffeeId'] ?? '',
                      'coffeeSize': sizeName,
                      'variantSlot': sizeIndex,
                    });
                  }
                }
                filteredDocs.add({
                  ...data,
                  'staffDocId': doc.id,
                  'sourceInventoryId': sourceId,
                  'name': data['name'] ?? 'Coffee',
                  'imageUrl': data['imageUrl'],
                  'items': coffeeItems,
                });
              } else if (!isBundle) {
                final rootKeys = ((rootData['items'] as List<dynamic>?) ?? [])
                    .whereType<Map>()
                    .map((item) => itemKey(Map<String, dynamic>.from(item)))
                    .toSet();
                final items = ((data['items'] as List<dynamic>?) ?? [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .where(
                      (item) =>
                          rootKeys.isEmpty || rootKeys.contains(itemKey(item)),
                    )
                    .toList();
                if (items.isEmpty) continue;
                filteredDocs.add({
                  ...data,
                  'staffDocId': doc.id,
                  'sourceInventoryId': sourceId,
                  'name': rootData['name'] ?? data['name'],
                  'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                  'items': items,
                });
              } else {
                filteredDocs.add({
                  ...data,
                  'staffDocId': doc.id,
                  'sourceInventoryId': sourceId,
                  'name': rootData['name'] ?? data['name'],
                  'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                });
              }
            }

            final orderItems = _orderItemsFromDocs(filteredDocs);
            _latestOrderItems = orderItems;
            _rememberOrderItems(orderItems);

            final groupedOrderItems = _groupOrderItemsByName(orderItems);

            if (_selectedGroupName != null &&
                !groupedOrderItems.containsKey(_selectedGroupName)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _selectedGroupName = null);
              });
            }

            if (_selectedGroupName != '__legacy_order_flow__') {
              return _buildCashierOrderFlow(
                orderItems: orderItems,
                groupedOrderItems: groupedOrderItems,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section title
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.restaurant_menu_rounded,
                        color: _AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Order Items',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                _buildInventoryModeToggle(),
                const SizedBox(height: 12),

                // ── Discount toggles
                _buildDiscountToggle(
                  title: 'Senior Discount',
                  subtitle: '20% off for senior citizens',
                  value: _seniorDiscount,
                  onChanged: (v) => setState(() {
                    _seniorDiscount = v;
                    if (v) _pwdDiscount = false;
                  }),
                  icon: Icons.elderly_rounded,
                ),
                const SizedBox(height: 10),
                _buildDiscountToggle(
                  title: 'PWD Discount',
                  subtitle: '20% off for persons with disability',
                  value: _pwdDiscount,
                  onChanged: (v) => setState(() {
                    _pwdDiscount = v;
                    if (v) _seniorDiscount = false;
                  }),
                  icon: Icons.accessible_rounded,
                ),
                const SizedBox(height: 16),

                // ── Item groups
                if (orderItems.isEmpty)
                  _buildEmptyState(
                    _showBundleView
                        ? 'No bundle items for today.'
                        : 'No category items for today.',
                  )
                else
                  ..._buildAnimatedItemGroups(groupedOrderItems, orderItems),

                const SizedBox(height: 16),

                // ── Cart panel
                _buildCartPanel(orderItems),

                const SizedBox(height: 32),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteItemFromInventory(String itemName) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('staffId', isEqualTo: _currentUserId)
          .where('name', isEqualTo: itemName)
          .get();

      for (var doc in querySnapshot.docs) {
        await doc.reference.update({'isDeleted': true});
      }

      _showStyledSnackBar('$itemName permanently removed from inventory');
    } catch (e) {
      _showStyledSnackBar('Error removing item: $e', isError: true);
    }
  }

  Widget _buildCashierOrderFlow({
    required List<Map<String, dynamic>> orderItems,
    required Map<String, List<MapEntry<int, Map<String, dynamic>>>>
    groupedOrderItems,
  }) {
    if (_showCartReview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _showCartReview = false),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: _AppColors.primary,
                style: IconButton.styleFrom(
                  backgroundColor: _AppColors.primary.withOpacity(0.08),
                  fixedSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Order Review',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBudgetCard(),
          const SizedBox(height: 16),
          _buildDiscountToggle(
            title: 'Senior Discount',
            subtitle: '20% off for senior citizens',
            value: _seniorDiscount,
            onChanged: (v) => setState(() {
              _seniorDiscount = v;
              if (v) _pwdDiscount = false;
            }),
            icon: Icons.elderly_rounded,
          ),
          const SizedBox(height: 10),
          _buildDiscountToggle(
            title: 'PWD Discount',
            subtitle: '20% off for persons with disability',
            value: _pwdDiscount,
            onChanged: (v) => setState(() {
              _pwdDiscount = v;
              if (v) _seniorDiscount = false;
            }),
            icon: Icons.accessible_rounded,
          ),
          const SizedBox(height: 16),
          _buildCartPanel(orderItems),
          const SizedBox(height: 32),
        ],
      );
    }

    if (_selectedGroupName != null && _showBundleView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 14),
          if (!groupedOrderItems.containsKey(_selectedGroupName))
            _buildEmptyState('Category no longer available.')
          else
            _buildItemsInCategory(
              _selectedGroupName!,
              groupedOrderItems[_selectedGroupName]!,
              orderItems,
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedGroupName = null),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: Text(
                    _showBundleView
                        ? 'Back to Bundles'
                        : _showCoffeeView
                        ? 'Back to Coffee'
                        : 'Back to Categories',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _AppColors.primary,
                    side: const BorderSide(color: _AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _cartHasValidItems(orderItems)
                      ? _openCartReview
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _AppColors.border,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Review Order'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                color: _AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Order Items',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _AppColors.primary,
                  ),
                ),
              ),
              if (_selectedGroupName != null && _showBundleView)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedGroupName = null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(
                    foregroundColor: _AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    backgroundColor: _AppColors.primary.withOpacity(0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _buildInventoryModeToggle(),
        const SizedBox(height: 14),
        if (orderItems.isEmpty)
          _buildEmptyState(
            _showBundleView
                ? 'No bundle items for today.'
                : 'No category items for today.',
          )
        else
          _buildCategoryGrid(groupedOrderItems, orderItems),
        const SizedBox(height: 96),
      ],
    );
  }

  Widget _buildCashierToolsPanel(List<Map<String, dynamic>> orderItems) {
    return Column(
      children: [
        _buildBudgetCard(),
        const SizedBox(height: 14),
        _buildStoreActions(orderItems),
      ],
    );
  }

  Widget _buildOrderDraftActions(List<Map<String, dynamic>> orderItems) {
    final hasItems = _cartHasValidItems(orderItems);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasPendingOrders)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: _showPendingOrders,
                icon: const Icon(Icons.bookmark_border_rounded, size: 17),
                label: Text('Restore held ticket ($_pendingOrderCount)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _AppColors.textMid,
                  side: const BorderSide(color: _AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: hasItems ? _cancelCurrentOrder : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB71C1C),
                  disabledForegroundColor: _AppColors.textSoft.withOpacity(
                    0.45,
                  ),
                  side: BorderSide(
                    color: hasItems
                        ? const Color(0xFFFFCDD2)
                        : _AppColors.border.withOpacity(0.6),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Cancel Order'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: hasItems ? _openCartReview : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _AppColors.border,
                  disabledForegroundColor: Colors.white.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Review Order'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStoreActions(List<Map<String, dynamic>> orderItems) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            icon: Icons.history_rounded,
            label: 'View\nHistory',
            onPressed: _showOrderHistory,
            color: const Color(0xFF0288D1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.assignment_return_rounded,
            label: 'Refund\nItem',
            onPressed: () => _showRefundDialog(orderItems),
            color: const Color(0xFFE65100),
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _selectedGroupName != null
                ? () => setState(() => _selectedGroupName = null)
                : null,
            child: Row(
              children: [
                Icon(
                  _showBundleView
                      ? Icons.inventory_2_rounded
                      : _showCoffeeView
                      ? Icons.local_cafe_rounded
                      : Icons.category_rounded,
                  size: 14,
                  color: _selectedGroupName != null
                      ? _AppColors.primary
                      : _AppColors.textSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  _showBundleView
                      ? 'Bundles'
                      : _showCoffeeView
                      ? 'Coffee'
                      : 'Categories',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _selectedGroupName != null
                        ? _AppColors.primary
                        : _AppColors.textSoft,
                    decoration: _selectedGroupName != null
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          if (_selectedGroupName != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _AppColors.textSoft,
              ),
            ),
            Expanded(
              child: Text(
                _groupLabel(_selectedGroupName!, null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _AppColors.textMid,
                ),
              ),
            ),
          ] else
            Expanded(
              child: Text(
                _showCoffeeView ? ' Select a coffee ' : ' Select a category ',
                style: const TextStyle(
                  fontSize: 12,
                  color: _AppColors.textSoft,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _orderImageBox(
    String imageUrl, {
    required IconData fallbackIcon,
    double size = 56,
    double? width,
    double? height,
  }) {
    final trimmed = imageUrl.trim();
    final boxWidth = width ?? size;
    final boxHeight = height ?? size;
    final fallback = Container(
      width: boxWidth,
      height: boxHeight,
      decoration: BoxDecoration(
        color: _AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(fallbackIcon, color: _AppColors.primary, size: size * 0.42),
    );
    if (trimmed.isEmpty) return fallback;

    Widget image;
    if (trimmed.startsWith('Assets/') || trimmed.startsWith('assets/')) {
      image = Image.asset(trimmed, fit: BoxFit.cover);
    } else if (trimmed.startsWith('data:image/')) {
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex == -1) return fallback;
      try {
        image = Image.memory(
          base64Decode(trimmed.substring(commaIndex + 1)),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    } else {
      image = Image.network(
        trimmed,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return fallback;
        },
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: boxWidth, height: boxHeight, child: image),
    );
  }

  Widget _buildCategoryGrid(
    Map<String, List<MapEntry<int, Map<String, dynamic>>>> groupedOrderItems,
    List<Map<String, dynamic>> orderItems,
  ) {
    final query = _orderSearchQuery.toLowerCase();
    final entries = groupedOrderItems.entries.where((entry) {
      if (query.isEmpty) return true;
      final displayName = _groupLabel(entry.key, entry.value).toLowerCase();
      final groupMatch = displayName.contains(query);
      final itemMatch = entry.value.any((variant) {
        final item = variant.value;
        final name = item['name']?.toString().toLowerCase() ?? '';
        final flavor = item['flavor']?.toString().toLowerCase() ?? '';
        final variantName = item['variant']?.toString().toLowerCase() ?? '';
        return name.contains(query) ||
            flavor.contains(query) ||
            variantName.contains(query);
      });
      return groupMatch || itemMatch;
    }).toList();
    final selectedKey = entries.any((entry) => entry.key == _selectedGroupName)
        ? _selectedGroupName!
        : entries.isNotEmpty
        ? entries.first.key
        : null;
    final selectedEntry = selectedKey == null
        ? null
        : entries.firstWhere((entry) => entry.key == selectedKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _showBundleView
              ? 'BUNDLE REGISTER'
              : _showCoffeeView
              ? 'COFFEE REGISTER'
              : 'CATEGORY REGISTER',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _AppColors.textSoft.withOpacity(0.7),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          _buildEmptyState('No matching categories found.')
        else
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final groupKey = entries[idx].key;
                final variants = entries[idx].value;
                final groupName = _groupLabel(groupKey, variants);
                final isSelected = groupKey == selectedKey;

                return _DelayedFadeSlide(
                  delay: Duration(milliseconds: 100 + idx * 60),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () =>
                          setState(() => _selectedGroupName = groupKey),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        constraints: const BoxConstraints(minWidth: 92),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? _AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? _AppColors.primary
                                : _AppColors.border.withOpacity(0.85),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _AppColors.primary.withOpacity(
                                isSelected ? 0.18 : 0.06,
                              ),
                              blurRadius: isSelected ? 14 : 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: isSelected
                                ? Colors.white
                                : _AppColors.textMid,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (selectedEntry != null) ...[
          const SizedBox(height: 14),
          _buildItemsInCategory(
            selectedEntry.key,
            selectedEntry.value,
            orderItems,
          ),
        ],
      ],
    );
  }

  Widget _buildFastItemGrid({
    required String displayGroupName,
    required IconData groupIcon,
    required bool isBundleGroup,
    required List<MapEntry<int, Map<String, dynamic>>> visibleVariants,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        if (visibleVariants.isEmpty)
          _buildEmptyState('No matching items found.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.86,
            ),
            itemCount: visibleVariants.length,
            itemBuilder: (context, listIdx) {
              final entry = visibleVariants[listIdx];
              final item = entry.value;
              final key = _cartKey(item);
              final price = _parsePrice(item['price']);
              final flavor = item['flavor']?.toString() ?? 'Item';
              final stock = _stockForItem(item, entry.key);
              final qty = _cart[key] ?? 0;
              final remainingStock = max(0, stock - qty);
              final isOutOfStock = remainingStock == 0;
              final imageUrl = item['imageUrl']?.toString() ?? '';

              return _DelayedFadeSlide(
                delay: Duration(milliseconds: 80 + listIdx * 45),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isOutOfStock
                        ? null
                        : () => _addSingleItemToTicket(item, stock),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: qty > 0
                              ? _AppColors.primary
                              : _AppColors.border.withOpacity(0.75),
                          width: qty > 0 ? 1.8 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: qty > 0
                                ? _AppColors.primary.withOpacity(0.14)
                                : _AppColors.primary.withOpacity(0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _orderImageBox(
                                imageUrl,
                                fallbackIcon: groupIcon,
                                size: 60,
                                width: double.infinity,
                                height: 118,
                              ),
                              const Spacer(),
                              Text(
                                flavor,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: isOutOfStock
                                      ? Colors.grey.shade400
                                      : _AppColors.textMid,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _MiniTag(
                                    label: '\u20B1${price.toStringAsFixed(0)}',
                                    bgColor: const Color(0xFFE8F5E9),
                                    textColor: const Color(0xFF2E7D32),
                                  ),
                                  _MiniTag(
                                    label: isOutOfStock
                                        ? 'Out'
                                        : '$remainingStock left',
                                    bgColor: isOutOfStock
                                        ? const Color(0xFFFFEBEE)
                                        : _AppColors.cardBg,
                                    textColor: isOutOfStock
                                        ? const Color(0xFFB71C1C)
                                        : _AppColors.textSoft,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (qty > 0)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _AppColors.primary,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '${qty}x',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildItemsInCategory(
    String groupName,
    List<MapEntry<int, Map<String, dynamic>>> variants,
    List<Map<String, dynamic>> orderItems,
  ) {
    final isBundleGroup =
        variants.isNotEmpty && variants.first.value['isBundle'] == true;
    final displayGroupName = _groupLabel(groupName, variants);
    final groupIcon = isBundleGroup
        ? Icons.inventory_2_rounded
        : _showCoffeeView
        ? Icons.local_cafe_rounded
        : Icons.category_rounded;
    final query = _orderSearchQuery.toLowerCase();
    final visibleVariants = variants.where((entry) {
      if (query.isEmpty) return true;
      final item = entry.value;
      final name = item['name']?.toString().toLowerCase() ?? '';
      final flavor = item['flavor']?.toString().toLowerCase() ?? '';
      final variantName = item['variant']?.toString().toLowerCase() ?? '';
      return name.contains(query) ||
          flavor.contains(query) ||
          variantName.contains(query);
    }).toList();
    if (_showCoffeeView && !isBundleGroup) {
      return _buildCoffeeItemsInCategory(displayGroupName, visibleVariants);
    }
    if (!_showCoffeeView || isBundleGroup) {
      return _buildFastItemGrid(
        displayGroupName: displayGroupName,
        groupIcon: groupIcon,
        isBundleGroup: isBundleGroup,
        visibleVariants: visibleVariants,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _AppColors.primary.withOpacity(0.1),
                _AppColors.primaryLight.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _AppColors.primary.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(groupIcon, size: 18, color: _AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayGroupName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _AppColors.textMid,
                      ),
                    ),
                    Text(
                      '${variants.length} variant${variants.length != 1 ? 's' : ''} available',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _AppColors.textSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visibleVariants.isEmpty)
          _buildEmptyState('No matching items found.')
        else
          ...visibleVariants.asMap().entries.map((indexedEntry) {
            final listIdx = indexedEntry.key;
            final entry = indexedEntry.value;
            final item = entry.value;
            final key = _cartKey(item);
            final price = (item['price'] as num).toDouble();
            final flavor = item['flavor'] as String;
            final index = entry.key;
            final stock = _stockForItem(item, index);
            final qty = _cart[key] ?? 0;
            final remainingStock = max(0, stock - qty);
            final isOutOfStock = remainingStock == 0;
            final imageUrl = item['imageUrl']?.toString() ?? '';

            return _DelayedFadeSlide(
              delay: Duration(milliseconds: 80 + listIdx * 60),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: qty > 0
                        ? _AppColors.primary.withOpacity(0.4)
                        : _AppColors.border.withOpacity(0.6),
                    width: qty > 0 ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: qty > 0
                          ? _AppColors.primary.withOpacity(0.1)
                          : _AppColors.primary.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _orderImageBox(
                      imageUrl,
                      fallbackIcon: groupIcon,
                      size: 52,
                      width: 96,
                      height: 72,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            flavor,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isOutOfStock
                                  ? Colors.grey.shade400
                                  : _AppColors.textMid,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _MiniTag(
                                label: '₱${price.toStringAsFixed(0)}',
                                bgColor: const Color(0xFFE8F5E9),
                                textColor: const Color(0xFF2E7D32),
                              ),
                              _MiniTag(
                                label: isOutOfStock
                                    ? 'Out of stock'
                                    : 'Stock: $remainingStock',
                                bgColor: isOutOfStock
                                    ? const Color(0xFFFFEBEE)
                                    : _AppColors.cardBg,
                                textColor: isOutOfStock
                                    ? const Color(0xFFB71C1C)
                                    : _AppColors.textSoft,
                              ),
                              if (qty > 0)
                                _MiniTag(
                                  label:
                                      '₱${(price * qty).toStringAsFixed(0)} total',
                                  bgColor: _AppColors.primary.withOpacity(0.1),
                                  textColor: _AppColors.primary,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: _AppColors.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: qty > 0
                              ? _AppColors.primary.withOpacity(0.3)
                              : _AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StepperButton(
                            icon: Icons.remove_rounded,
                            onPressed: qty > 0 ? () => _removeItem(key) : null,
                          ),
                          SizedBox(
                            width: 56,
                            height: 36,
                            child: Center(
                              child: TextField(
                                controller: _qtyControllerFor(key, qty),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: qty > 0
                                      ? _AppColors.primary
                                      : Colors.grey,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  counterText: '',
                                  hintText: '0',
                                ),
                                onChanged: (value) =>
                                    _setItemQuantity(key, value, stock),
                              ),
                            ),
                          ),
                          _StepperButton(
                            icon: Icons.add_rounded,
                            onPressed: !isOutOfStock
                                ? () => _addItem(key)
                                : null,
                            isAdd: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCoffeeItemsInCategory(
    String displayGroupName,
    List<MapEntry<int, Map<String, dynamic>>> variants,
  ) {
    final coffeeId = variants.isNotEmpty
        ? variants.first.value['coffeeId']?.toString() ?? ''
        : '';
    final sizeGroups = <String, List<Map<String, dynamic>>>{};
    for (final entry in variants) {
      final item = entry.value;
      final sizeName =
          item['coffeeSize']?.toString() ??
          item['variant']?.toString() ??
          'Regular';
      sizeGroups.putIfAbsent(sizeName, () => []).add(item);
    }
    final sizeEntries = sizeGroups.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sizeEntries.isEmpty)
          _buildEmptyState('No coffee sizes available.')
        else ...[
          _buildCoffeeFlavorCard(displayGroupName, coffeeId, sizeEntries),
          if (_orderSearchQuery == '\u0000')
            ...sizeEntries.asMap().entries.map((indexedEntry) {
              final listIdx = indexedEntry.key;
              final sizeEntry = indexedEntry.value;
              final sizeName = sizeEntry.key;
              final sizeVariants = sizeEntry.value;
              Map<String, dynamic> baseVariant = sizeVariants.first;
              for (final variant in sizeVariants) {
                final addonName = variant['addonName']?.toString() ?? '';
                if (addonName.isEmpty) {
                  baseVariant = variant;
                  break;
                }
              }
              final basePrice = _parsePrice(baseVariant['price']);
              final sizeDelta = _parsePrice(baseVariant['sizePriceDelta']);
              final sizeCartCount = sizeVariants.fold<int>(0, (sum, item) {
                final key = _cartKey(item);
                return sum + (_cart[key] ?? 0);
              });
              final addonEntries = <String, double>{};
              for (final item in sizeVariants) {
                final addonName = item['addonName']?.toString().trim() ?? '';
                if (addonName.isEmpty) continue;
                addonEntries[addonName] = _parsePrice(item['addonPriceDelta']);
              }
              final addonCount = addonEntries.length;
              final imageUrl = baseVariant['imageUrl']?.toString() ?? '';

              return _DelayedFadeSlide(
                delay: Duration(milliseconds: 80 + listIdx * 60),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: sizeCartCount > 0
                          ? _AppColors.primary.withOpacity(0.4)
                          : _AppColors.border.withOpacity(0.6),
                      width: sizeCartCount > 0 ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: sizeCartCount > 0
                            ? _AppColors.primary.withOpacity(0.1)
                            : _AppColors.primary.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _orderImageBox(
                        imageUrl,
                        fallbackIcon: Icons.local_cafe_rounded,
                        size: 52,
                        width: 96,
                        height: 72,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sizeName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _AppColors.textMid,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _MiniTag(
                                  label: '₱${basePrice.toStringAsFixed(0)}',
                                  bgColor: const Color(0xFFE8F5E9),
                                  textColor: const Color(0xFF2E7D32),
                                ),
                                if (sizeDelta > 0)
                                  _MiniTag(
                                    label:
                                        '+₱${sizeDelta.toStringAsFixed(0)} size',
                                    bgColor: const Color(0xFFFFF3E0),
                                    textColor: const Color(0xFFE65100),
                                  ),
                                if (addonCount > 0)
                                  _MiniTag(
                                    label:
                                        '$addonCount add-on${addonCount != 1 ? 's' : ''}',
                                    bgColor: _AppColors.cardBg,
                                    textColor: _AppColors.textSoft,
                                  ),
                                if (sizeCartCount > 0)
                                  _MiniTag(
                                    label: '$sizeCartCount in cart',
                                    bgColor: _AppColors.primary.withOpacity(
                                      0.1,
                                    ),
                                    textColor: _AppColors.primary,
                                  ),
                              ],
                            ),
                            if (addonEntries.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: addonEntries.entries.map((entry) {
                                  final addonName = entry.key;
                                  final addonPrice = entry.value;
                                  final priceLabel = addonPrice > 0
                                      ? ' +₱${addonPrice.toStringAsFixed(0)}'
                                      : '';
                                  return _MiniTag(
                                    label: '$addonName$priceLabel',
                                    bgColor: const Color(0xFFF3E5F5),
                                    textColor: const Color(0xFF6A1B9A),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ],
    );
  }

  Widget _buildCoffeeFlavorCard(
    String displayGroupName,
    String coffeeId,
    List<MapEntry<String, List<Map<String, dynamic>>>> sizeEntries,
  ) {
    final coffeeVariants = sizeEntries.expand((entry) => entry.value).toList();
    final imageUrl = coffeeVariants.isEmpty
        ? ''
        : coffeeVariants.first['imageUrl']?.toString() ?? '';
    final originalPrices = coffeeVariants
        .map((item) {
          final basePrice = _parsePrice(item['basePrice']);
          if (basePrice > 0) return basePrice;
          return _parsePrice(item['price']) -
              _parsePrice(item['sizePriceDelta']) -
              _parsePrice(item['addonPriceDelta']);
        })
        .where((price) => price > 0)
        .toList();
    final originalPrice = originalPrices.isEmpty
        ? 0.0
        : originalPrices.reduce(min);
    final priceLabel = '\u20B1${originalPrice.toStringAsFixed(0)}';

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.86,
      ),
      itemCount: 1,
      itemBuilder: (context, index) {
        return _DelayedFadeSlide(
          delay: const Duration(milliseconds: 80),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showCoffeeCustomizeDialog(
                flavorName: displayGroupName,
                coffeeId: coffeeId,
                variants: coffeeVariants,
              ),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _AppColors.border.withOpacity(0.75),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _AppColors.primary.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _orderImageBox(
                      imageUrl,
                      fallbackIcon: Icons.local_cafe_rounded,
                      size: 60,
                      width: double.infinity,
                      height: 118,
                    ),
                    const Spacer(),
                    Text(
                      displayGroupName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _AppColors.textMid,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniTag(
                          label: priceLabel,
                          bgColor: const Color(0xFFE8F5E9),
                          textColor: const Color(0xFF2E7D32),
                        ),
                        _MiniTag(
                          label:
                              '${sizeEntries.length} size${sizeEntries.length == 1 ? '' : 's'}',
                          bgColor: _AppColors.cardBg,
                          textColor: _AppColors.textSoft,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildAnimatedItemGroups(
    Map<String, List<MapEntry<int, Map<String, dynamic>>>> groupedOrderItems,
    List<Map<String, dynamic>> orderItems,
  ) {
    final entries = groupedOrderItems.entries.toList();
    return entries.asMap().entries.map((indexedEntry) {
      final idx = indexedEntry.key;
      final groupEntry = indexedEntry.value;
      final groupName = groupEntry.key;
      final variants = groupEntry.value;

      return _DelayedFadeSlide(
        delay: Duration(milliseconds: 300 + idx * 80),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _AppColors.border.withOpacity(0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _AppColors.primary.withOpacity(0.07),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Group header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _AppColors.primary.withOpacity(0.08),
                      _AppColors.primaryLight.withOpacity(0.04),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        groupName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _AppColors.textMid,
                        ),
                      ),
                    ),
                    // View Items button for bundles
                    if (variants.isNotEmpty &&
                        variants.first.value['isBundle'] == true)
                      TextButton.icon(
                        onPressed: () => _showBundleItemsDialog(groupName),
                        icon: const Icon(Icons.visibility_rounded, size: 16),
                        label: const Text(
                          'View Items',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: _AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          backgroundColor: _AppColors.primary.withOpacity(0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Variants
              ...variants.map((entry) {
                final item = entry.value;
                final key = _cartKey(item);
                final price = (item['price'] as num).toDouble();
                final flavor = item['flavor'] as String;
                final index = entry.key;
                final stock = _stockForItem(item, index);
                final qty = _cart[key] ?? 0;
                final remainingStock = max(0, stock - qty);
                final isOutOfStock = remainingStock == 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              flavor,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isOutOfStock
                                    ? Colors.grey
                                    : _AppColors.textMid,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _MiniTag(
                                  label: '₱${price.toStringAsFixed(0)}',
                                  bgColor: const Color(0xFFE8F5E9),
                                  textColor: const Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 6),
                                _MiniTag(
                                  label: isOutOfStock
                                      ? 'Out of stock'
                                      : 'Stock: $remainingStock',
                                  bgColor: isOutOfStock
                                      ? const Color(0xFFFFEBEE)
                                      : _AppColors.cardBg,
                                  textColor: isOutOfStock
                                      ? const Color(0xFFB71C1C)
                                      : _AppColors.textSoft,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Qty stepper
                      Container(
                        decoration: BoxDecoration(
                          color: _AppColors.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: qty > 0
                                ? _AppColors.border
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StepperButton(
                              icon: Icons.remove_rounded,
                              onPressed: qty > 0
                                  ? () => _removeItem(key)
                                  : null,
                            ),
                            SizedBox(
                              width: 72,
                              height: 36,
                              child: Center(
                                child: TextField(
                                  controller: _qtyControllerFor(key, qty),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: qty > 0
                                        ? _AppColors.primary
                                        : Colors.grey,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    counterText: '',
                                    hintText: '0',
                                  ),
                                  onChanged: (value) =>
                                      _setItemQuantity(key, value, stock),
                                ),
                              ),
                            ),
                            _StepperButton(
                              icon: Icons.add_rounded,
                              onPressed: !isOutOfStock
                                  ? () => _addItem(key)
                                  : null,
                              isAdd: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }).toList();
  }

  String _itemDisplayLabel(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? 'Item';
    final variant = item['variant']?.toString() ?? '';
    final flavor = item['flavor']?.toString() ?? '';
    final isCoffee = item['isCoffee'] == true;
    final coffeeSize = item['coffeeSize']?.toString() ?? '';
    final addonName = item['addonName']?.toString() ?? '';
    final sugarLevel = item['sugarLevel']?.toString() ?? '';
    if (isCoffee) {
      if (sugarLevel.isNotEmpty && variant.isNotEmpty && variant != name) {
        return '$name ($variant)';
      }
      if (variant.isNotEmpty && variant != name) return '$name ($variant)';
      if (coffeeSize.isNotEmpty && addonName.isNotEmpty) {
        final sugar = sugarLevel.isEmpty ? '' : ', Sugar $sugarLevel';
        return '$name ($coffeeSize + $addonName$sugar)';
      }
      if (coffeeSize.isNotEmpty) {
        final sugar = sugarLevel.isEmpty ? '' : ', Sugar $sugarLevel';
        return '$name ($coffeeSize$sugar)';
      }
      if (flavor.isNotEmpty && flavor != name) return flavor;
      return name;
    }
    if (variant.isNotEmpty) return '$name ($variant)';
    if (flavor.isNotEmpty && flavor != name) return flavor;
    return name;
  }

  Widget _buildCartReviewPanel(List<Map<String, dynamic>> orderItems) {
    final validCartEntries = _validCartEntries(orderItems);
    final validCartItemCount = validCartEntries.fold(
      0,
      (totalQty, entry) => totalQty + entry.value,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _AppColors.border.withOpacity(0.75)),
        boxShadow: [
          BoxShadow(
            color: _AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_AppColors.primaryDark, _AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_bag_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Order Review',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    '$validCartItemCount items',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (validCartEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 42,
                    color: _AppColors.border,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No items yet.',
                    style: TextStyle(
                      color: _AppColors.textSoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Column(
                children: validCartEntries.map((entry) {
                  final item = orderItems.firstWhere(
                    (element) => _cartKey(element) == entry.key,
                    orElse: () => {},
                  );
                  final price = (item['price'] as num?)?.toDouble() ?? 0;
                  final subtotal = price * entry.value;
                  final variantSlot = item['variantSlot'] is int
                      ? item['variantSlot'] as int
                      : 0;
                  final stock = item.isEmpty
                      ? entry.value
                      : _stockForItem(item, variantSlot);
                  final qtyController = _qtyControllerFor(
                    entry.key,
                    entry.value,
                  );
                  final qtyText = entry.value.toString();
                  if (qtyController.text != qtyText) {
                    qtyController.value = TextEditingValue(
                      text: qtyText,
                      selection: TextSelection.collapsed(
                        offset: qtyText.length,
                      ),
                    );
                  }
                  return Dismissible(
                    key: ValueKey('review-cart-${entry.key}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB71C1C),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) => _deleteCartItem(entry.key),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _AppColors.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _AppColors.border),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Column(
                              children: [
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 12,
                                      color: _AppColors.primary,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Edit',
                                      style: TextStyle(
                                        color: _AppColors.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: qtyController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _AppColors.border,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _AppColors.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: _AppColors.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  onChanged: (value) =>
                                      _setItemQuantity(entry.key, value, stock),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _itemDisplayLabel(item),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _AppColors.textMid,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\u20B1${price.toStringAsFixed(2)} each',
                                  style: const TextStyle(
                                    color: _AppColors.textSoft,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Line total: \u20B1${subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: _AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _AppColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _StepperButton(
                                  icon: Icons.remove_rounded,
                                  onPressed: entry.value > 1
                                      ? () => _removeItem(entry.key)
                                      : null,
                                ),
                                _StepperButton(
                                  icon: Icons.add_rounded,
                                  onPressed: entry.value < stock
                                      ? () => _addItem(entry.key)
                                      : null,
                                  isAdd: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Subtotal',
                  value: '\u20B1${_cartTotal(orderItems).toStringAsFixed(2)}',
                ),
                if (_seniorDiscount || _pwdDiscount) ...[
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: _discountLabel,
                    value:
                        '- \u20B1${_discountValue(orderItems).toStringAsFixed(2)}',
                    valueColor: const Color(0xFF2E7D32),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE4EC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: _AppColors.textMid,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '\u20B1${_discountedTotal(orderItems).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: _AppColors.primary,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCartPanel(List<Map<String, dynamic>> orderItems) {
    final validCartEntries = _validCartEntries(orderItems);
    final validCartItemCount = validCartEntries.fold(
      0,
      (totalQty, entry) => totalQty + entry.value,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _AppColors.border.withOpacity(0.7), width: 1),
        boxShadow: [
          BoxShadow(
            color: _AppColors.primary.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Cart Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _AppColors.primaryDark,
                  _AppColors.primary,
                  _AppColors.primaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_cart_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Cart',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$validCartItemCount items',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cart Items
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: validCartEntries.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 40,
                          color: _AppColors.border,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No items yet. Add products above.',
                          style: TextStyle(
                            color: _AppColors.textSoft,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: validCartEntries.map((entry) {
                      final item = orderItems.firstWhere(
                        (element) => _cartKey(element) == entry.key,
                        orElse: () => {},
                      );
                      final price = (item['price'] as num?)?.toDouble() ?? 0;
                      final subtotal = price * entry.value;
                      final displayName = item.isNotEmpty
                          ? _itemDisplayLabel(item)
                          : _displayName(entry.key);
                      final variantSlot = item['variantSlot'] is int
                          ? item['variantSlot'] as int
                          : 0;
                      final stock = item.isEmpty
                          ? entry.value
                          : _stockForItem(item, variantSlot);
                      final qtyController = _qtyControllerFor(
                        entry.key,
                        entry.value,
                      );
                      final qtyText = entry.value.toString();
                      if (qtyController.text != qtyText) {
                        qtyController.value = TextEditingValue(
                          text: qtyText,
                          selection: TextSelection.collapsed(
                            offset: qtyText.length,
                          ),
                        );
                      }
                      return Dismissible(
                        key: ValueKey('cart-${entry.key}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: const Color(0xFFB71C1C),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) => _deleteCartItem(entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _AppColors.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _StepperButton(
                                      icon: Icons.remove_rounded,
                                      onPressed: entry.value > 1
                                          ? () => _removeItem(entry.key)
                                          : null,
                                    ),
                                    SizedBox(
                                      width: 42,
                                      height: 36,
                                      child: TextField(
                                        controller: qtyController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        textAlign: TextAlign.center,
                                        onChanged: (value) => _setItemQuantity(
                                          entry.key,
                                          value,
                                          stock,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: _AppColors.primary,
                                          fontSize: 12,
                                        ),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _StepperButton(
                                      icon: Icons.add_rounded,
                                      onPressed: entry.value < stock
                                          ? () => _addItem(entry.key)
                                          : null,
                                      isAdd: true,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: _AppColors.textMid,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                '₱${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _AppColors.textMid,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),

          // Totals
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                const Divider(color: _AppColors.divider, thickness: 1),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Subtotal',
                  value: '₱${_cartTotal(orderItems).toStringAsFixed(2)}',
                ),
                if (_seniorDiscount || _pwdDiscount) ...[
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: _discountLabel,
                    value:
                        '- ₱${_discountValue(orderItems).toStringAsFixed(2)}',
                    valueColor: const Color(0xFF2E7D32),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFCE4EC), Color(0xFFFFF0F5)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _AppColors.textMid,
                        ),
                      ),
                      Text(
                        '₱${_discountedTotal(orderItems).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Quick actions hint
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Color(0xFFF57C00),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Customer leaving? Save as pending and restore later.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // SECONDARY ACTIONS (visually separated from Confirm Order)
          // ─────────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _AppColors.textSoft,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionButton(
                        icon: Icons.bookmark_add_rounded,
                        label: 'Save\nPending',
                        onPressed: validCartEntries.isNotEmpty
                            ? () => _savePendingOrder(orderItems)
                            : null,
                        color: _AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickActionButton(
                        icon: Icons.list_alt_rounded,
                        label: 'View\nPending',
                        onPressed: _showPendingOrders,
                        color: const Color(0xFF7B1FA2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Visual separator between secondary and primary actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                const Expanded(child: Divider(color: _AppColors.divider)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _AppColors.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _AppColors.border, width: 1),
                    ),
                    child: const Text(
                      'Payment',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _AppColors.textSoft,
                      ),
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: _AppColors.divider)),
              ],
            ),
          ),

          // ── CONFIRM ORDER — prominently separated
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, child) {
                  return Transform.scale(
                    scale: validCartEntries.isNotEmpty ? _pulseAnim.value : 1.0,
                    child: child,
                  );
                },
                child: ElevatedButton(
                  onPressed: () => _showOrderConfirmationDialog(orderItems),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shadowColor: _AppColors.primary.withOpacity(0.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Confirm Order',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (validCartEntries.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '₱${_discountedTotal(orderItems).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: value ? _AppColors.primary.withOpacity(0.07) : _AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value ? _AppColors.border : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? _AppColors.primary.withOpacity(0.15)
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? _AppColors.primary : _AppColors.textSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: value ? _AppColors.primary : _AppColors.textMid,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _AppColors.textSoft,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _AppColors.accent,
            activeTrackColor: _AppColors.primary.withOpacity(0.25),
            inactiveTrackColor: _AppColors.border,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 52, color: _AppColors.border),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: _AppColors.textSoft, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Text(
        message,
        style: const TextStyle(color: _AppColors.primary, fontSize: 13),
      ),
    );
  }

  Widget _buildInventoryModeToggle() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _modeButton(
            label: 'Category',
            icon: Icons.category_rounded,
            selected: !_showBundleView && !_showCoffeeView,
            onTap: () => setState(() {
              _showBundleView = false;
              _showCoffeeView = false;
              _selectedGroupName = null;
              _showCartReview = false;
            }),
          ),
          const SizedBox(width: 10),
          _modeButton(
            label: 'Bundle',
            icon: Icons.inventory_2_rounded,
            selected: _showBundleView,
            onTap: () => setState(() {
              _showBundleView = true;
              _showCoffeeView = false;
              _selectedGroupName = null;
              _showCartReview = false;
            }),
          ),
          const SizedBox(width: 10),
          _modeButton(
            label: 'Coffee',
            icon: Icons.local_cafe_rounded,
            selected: _showCoffeeView,
            onTap: () => setState(() {
              _showBundleView = false;
              _showCoffeeView = true;
              _selectedGroupName = null;
              _showCartReview = false;
            }),
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? _AppColors.primary : _AppColors.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _AppColors.primary : _AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? Colors.white : _AppColors.textMid,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _AppColors.textMid,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: _buildPageHeader(),
            ),
            if (!_showCartReview)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _buildOrderSearchField(),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: _buildOrderSection(),
              ),
            ),
            if (!_showCartReview &&
                (!_showBundleView || _selectedGroupName == null))
              _buildDockedOrderActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildDockedOrderActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + _staffBottomNavReserve,
      ),
      decoration: BoxDecoration(
        color: _AppColors.bg.withOpacity(0.96),
        border: Border(
          top: BorderSide(color: _AppColors.border.withOpacity(0.7), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: _buildOrderDraftActions(_knownOrderItems(_latestOrderItems)),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _DelayedFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _DelayedFadeSlide({required this.child, required this.delay});

  @override
  State<_DelayedFadeSlide> createState() => _DelayedFadeSlideState();
}

class _DelayedFadeSlideState extends State<_DelayedFadeSlide>
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
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isAdd;
  const _StepperButton({
    required this.icon,
    this.onPressed,
    this.isAdd = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onPressed != null
              ? (isAdd ? _AppColors.primary : _AppColors.cardBg)
              : Colors.grey.shade100,
          borderRadius: isAdd
              ? const BorderRadius.horizontal(right: Radius.circular(14))
              : const BorderRadius.horizontal(left: Radius.circular(14)),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onPressed != null
              ? (isAdd ? Colors.white : _AppColors.primary)
              : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  const _QuickActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedOpacity(
        opacity: isEnabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  const _MiniTag({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: _AppColors.textSoft),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _AppColors.textMid,
          ),
        ),
      ],
    );
  }
}

class _CompactAmountLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _CompactAmountLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: _AppColors.textSoft),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor ?? _AppColors.textMid,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDiscount;
  const _OrderRow({
    required this.label,
    required this.value,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDiscount ? const Color(0xFF2E7D32) : _AppColors.textSoft,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDiscount ? const Color(0xFF2E7D32) : _AppColors.textMid,
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
  final String? prefixText;
  final ValueChanged<String>? onChanged;

  const _PinkTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.prefixText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        prefixIcon: Icon(icon, color: _AppColors.primary, size: 18),
        labelStyle: const TextStyle(color: _AppColors.primary),
        hintStyle: TextStyle(
          color: _AppColors.textSoft.withOpacity(0.4),
          fontSize: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: _AppColors.cardBg,
      ),
    );
  }
}
