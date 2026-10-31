import '../widgets/inventory_batches.dart';
import '../services/bundle_stock_service.dart';
import '../widgets/allocation_checklist.dart';
import '../widgets/staff_inventory_history.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import '../services/inventory_display_ids.dart';
import '../services/public_item_id.dart';
import '../services/beverage_sales_summary.dart';
import '../services/local_database_sync_service.dart';
import '../services/offline_stock_reduction_service.dart';
import '../services/sale_stock.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/inventory_service.dart';
import '../services/number_format.dart';
import '../widgets/top_notification.dart';
import '../widgets/top_edge_refresh.dart';

class AllCategPage extends StatefulWidget {
  final String? selectedCategoryName;
  final String? selectedSourceInventoryId;
  final bool selectedIsBundle;
  final bool selectedIsCoffee;
  final bool embedded;
  final bool tabletLayout;
  final GlobalKey? inventoryActionsTourKey;
  final GlobalKey? inventoryChecklistTourKey;
  final GlobalKey? inventoryReturnsTourKey;
  final GlobalKey? inventoryTourKey;

  const AllCategPage({
    super.key,
    this.selectedCategoryName,
    this.selectedSourceInventoryId,
    this.selectedIsBundle = false,
    this.selectedIsCoffee = false,
    this.embedded = false,
    this.tabletLayout = false,
    this.inventoryActionsTourKey,
    this.inventoryChecklistTourKey,
    this.inventoryReturnsTourKey,
    this.inventoryTourKey,
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
  bool _showCoffeeAddonsTable = false;
  bool _showAllCategoryItems = false;
  String _tableSearchQuery = '';
  String? _selectedTableCategoryKey;
  List<String> _staffInventoryIds = const [];
  // Keep both subscriptions stable while the user searches or switches tabs.
  // Recreating them from build() temporarily put StreamBuilder back into its
  // waiting state, which replaced the search field with the loading layout.
  Stream<QuerySnapshot>? _staffInventoryStreamCache;
  late final Stream<QuerySnapshot> _rootInventoryStream;
  StreamSubscription<String>? _offlineSalesSubscription;
  StreamSubscription<String>? _offlineInventorySubscription;
  StreamSubscription<void>? _offlineReductionsSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<Map<String, dynamic>> _pendingOfflineSales = const [];
  List<Map<String, dynamic>> _pendingOfflineReductions = const [];
  bool _inventoryOnline = false;
  bool _syncingOfflineReductions = false;

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
    _offlineSalesSubscription = LocalDatabaseSyncService().collectionUpdates
        .where((collection) => collection == 'completed_sales')
        .listen((_) => _loadPendingOfflineSales());
    _offlineInventorySubscription = LocalDatabaseSyncService().collectionUpdates
        .where((collection) => collection == 'staff_inventory')
        .listen((_) => _loadPendingOfflineReductions(sync: false));
    _offlineReductionsSubscription = OfflineStockReductionService().changes
        .listen((_) => _loadPendingOfflineReductions(sync: false));
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final online = !results.contains(ConnectivityResult.none);
      if (online != _inventoryOnline) {
        _inventoryOnline = online;
        unawaited(_loadPendingOfflineReductions());
      }
    });
    unawaited(_loadPendingOfflineSales());
    unawaited(_loadPendingOfflineReductions());
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

  Future<void> _refreshInventory() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await OfflineStockReductionService().sync(FirebaseFirestore.instance);
        await _loadPendingOfflineReductions();
      }
      final prefs = await SharedPreferences.getInstance();
      final uid =
          FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('lastStaffDocId') ??
          prefs.getString('lastUserId');
      if (uid != null && uid.isNotEmpty) {
        await _loadStaffInventoryIds(uid);
      }
      final ids = _staffInventoryIds
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .take(10)
          .toList();
      final inventory = FirebaseFirestore.instance.collection(
        'staff_inventory',
      );
      await Future.wait([
        FirebaseFirestore.instance
            .collection('sales_inventory')
            .get(const GetOptions(source: Source.server)),
        if (ids.isEmpty)
          inventory
              .where('staffId', isEqualTo: '')
              .get(const GetOptions(source: Source.server))
        else if (ids.length == 1)
          inventory
              .where('staffId', isEqualTo: ids.first)
              .get(const GetOptions(source: Source.server))
        else
          inventory
              .where('staffId', whereIn: ids)
              .get(const GetOptions(source: Source.server)),
      ]).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() => _staffInventoryStreamCache = null);
      }
    } catch (error) {
      debugPrint('Unable to refresh staff inventory: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to refresh inventory. Check your connection.',
            ),
          ),
        );
      }
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
    _offlineSalesSubscription?.cancel();
    _offlineInventorySubscription?.cancel();
    _offlineReductionsSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _headerAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingOfflineSales() async {
    try {
      final sales = await LocalDatabaseSyncService().getCachedCollection(
        'completed_sales',
      );
      final pending = sales
          .where((sale) => sale['stockSyncRequired'] == true)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _pendingOfflineSales = pending);
    } catch (error) {
      debugPrint('Unable to load pending offline stock sales: $error');
    }
  }

  Future<void> _loadPendingOfflineReductions({bool sync = true}) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final online = !connectivity.contains(ConnectivityResult.none);
      final service = OfflineStockReductionService();
      var pending = await service.pending();
      if (!mounted) return;
      final sameQueue =
          jsonEncode(_pendingOfflineReductions) == jsonEncode(pending);
      if (_inventoryOnline != online ||
          !sameQueue ||
          _syncingOfflineReductions !=
              (online && pending.isNotEmpty && service.isSyncing) ||
          (sync && online && pending.isNotEmpty)) {
        setState(() {
          _inventoryOnline = online;
          _pendingOfflineReductions = pending;
          _syncingOfflineReductions =
              online && pending.isNotEmpty && (sync || service.isSyncing);
        });
      }
      if (!sync || !online || pending.isEmpty) return;
      await service.sync(FirebaseFirestore.instance);
      pending = await service.pending();
      if (!mounted) return;
      setState(() {
        _pendingOfflineReductions = pending;
        _syncingOfflineReductions =
            online && pending.isNotEmpty && service.isSyncing;
      });
    } catch (error) {
      debugPrint('Unable to load pending stock reductions: $error');
      if (mounted && sync) {
        setState(() => _syncingOfflineReductions = false);
      }
    }
  }

  Future<void> _queueOfflineStockReduction({
    required String id,
    required String inventoryId,
    required Map<String, dynamic> item,
    required int quantity,
    required String categoryName,
    required String reason,
    required String comment,
    required String staffId,
    required String staffName,
  }) async {
    await OfflineStockReductionService().enqueue({
      'id': id,
      'inventoryId': inventoryId,
      'itemId':
          item['id']?.toString() ??
          item['itemId']?.toString() ??
          item['variantId']?.toString() ??
          '',
      'itemName': item['name']?.toString() ?? '',
      'variant': item['variant']?.toString() ?? '',
      'sourceInventoryId': item['sourceInventoryId']?.toString() ?? '',
      'quantity': quantity,
      'unitPrice': _parsePrice(item['price']),
      'categoryName': categoryName,
      'reason': reason,
      'comment': comment,
      'staffId': staffId,
      'staffName': staffName,
    });
    await _loadPendingOfflineReductions();
  }

  Map<String, dynamic> _inventoryDataWithPendingSales(
    Map<String, dynamic> rawData,
    String documentId,
  ) {
    var data = <String, dynamic>{...rawData, '_localDocId': documentId};
    for (final sale in _pendingOfflineSales) {
      final saleId = sale['salesId']?.toString() ?? '';
      if (saleId.isEmpty) continue;
      final lines = expandSaleStockLines(
        (sale['items'] as List? ?? []).whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ),
      ).where((line) => line['staffInventoryDocId'] == documentId).toList();
      if (lines.isEmpty) continue;
      data = applySaleStock(data, saleId, lines);
    }
    return data;
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

  Color _stockColor(int stock, {String type = 'Categories'}) {
    if (stock == 0) return const Color(0xFFE53935);
    if (inventoryLowStock(stock, type: type)) {
      return const Color(0xFFF57C00);
    }
    return const Color(0xFF2E7D32);
  }

  bool _isNearExpiry(dynamic value) {
    final expiry = value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse('${value ?? ''}');
    if (expiry == null) return false;
    final today = DateUtils.dateOnly(DateTime.now());
    final expiryDay = DateUtils.dateOnly(expiry);
    return !expiryDay.isBefore(today) &&
        !expiryDay.isAfter(today.add(const Duration(days: 5)));
  }

  bool _isExpiredDate(dynamic value) {
    final expiry = value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse('${value ?? ''}');
    return expiry != null &&
        DateUtils.dateOnly(expiry).isBefore(DateUtils.dateOnly(DateTime.now()));
  }

  bool _hasExpiredBundleInventory(Map<String, dynamic> bundle) {
    if (_isExpiredDate(bundle['expirationDate'])) return true;
    final instances = bundleRows(bundle['bundleInstances']);
    if (instances.isEmpty) {
      return bundleRows(
        bundle['items'],
      ).any((item) => _isExpiredDate(item['expirationDate']));
    }
    final availableInstances = instances.where((instance) {
      final status = '${instance['status'] ?? 'available'}'.toLowerCase();
      return instance['isDeleted'] != true &&
          instance['isVoided'] != true &&
          (status.isEmpty || status == 'available');
    }).toList();
    return availableInstances.isNotEmpty &&
        availableInstances.every((instance) {
          if (_isExpiredDate(instance['expirationDate'])) return true;
          final items = bundleRows(instance['items']);
          final expiryItems = items.isEmpty
              ? bundleRows(bundle['items'])
              : items;
          return expiryItems.any(
            (item) => _isExpiredDate(item['expirationDate']),
          );
        });
  }

  String _availabilityLabel({
    required int stock,
    required dynamic expirationDate,
    required String type,
    bool expiredBundle = false,
  }) {
    if (_isExpiredDate(expirationDate) || (expiredBundle && stock == 0)) {
      return 'Expired';
    }
    if (stock <= 0) return 'Sold Out';
    final lowStock = inventoryLowStock(stock, type: type);
    final nearExpiry = _isNearExpiry(expirationDate);
    if (lowStock && nearExpiry) return 'Low Stock/Near Expiry';
    if (lowStock) return 'Low Stock';
    if (nearExpiry) return 'Near Expiry';
    return 'Available';
  }

  Color _availabilityColor(String status) {
    if (status == 'Expired' || status == 'Sold Out') return Colors.red.shade700;
    if (status.contains('Low Stock') || status == 'Near Expiry') {
      return Colors.deepOrange.shade700;
    }
    return const Color(0xFF2E7D32);
  }

  DataCell _availabilityCell(String status) => _tableCell(
    status,
    width: 150,
    color: _availabilityColor(status),
    weight: FontWeight.w800,
  );

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
    child: Icon(icon, color: AppColors.primaryDark, size: 30),
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
    for (final source in [data, ?rootData]) {
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
        'costPrice': coffeeSizeCostPrice(
          size: size,
          data: data,
          rootData: rootData,
        ),
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
        'Beverages flavor';
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
        'title': 'Beverages flavor is running low',
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
        _buildSnackBar('Failed to mark beverage low: $e', isError: true),
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

  int _bundleStockForData(Map<String, dynamic> data) =>
      availableBundleStock(data);

  int _pendingBundleCount(Map<String, dynamic> data) =>
      (data['bundleInstances'] as List? ?? const [])
          .whereType<Map>()
          .where((instance) => instance['status'] == 'reconciliation_pending')
          .length;

  List<Map<String, dynamic>> _groupBundleAllocations(
    Iterable<Map<String, dynamic>> records,
  ) {
    final groups = <String, Map<String, dynamic>>{};
    for (final record in records) {
      final allocationId = '${record['sourceDocId'] ?? record['id'] ?? ''}';
      final key = bundleInventoryGroupKey(record);
      final group = groups.putIfAbsent(key, () {
        return {
          ...record,
          'bundleCount': 0,
          'assignedStartingStock': 0,
          'bundleInstances': <Map<String, dynamic>>[],
        };
      });
      final count = _parseInt(record['bundleCount']);
      final instances = _bundleInstancesFromData(record).map((instance) {
        return {
          ...instance,
          'batchId': instance['batchId'] ?? allocationId,
          'assignedAt': instance['assignedAt'] ?? record['assignedAt'],
        };
      }).toList();
      group['bundleCount'] = _parseInt(group['bundleCount']) + count;
      group['assignedStartingStock'] =
          _parseInt(group['assignedStartingStock']) +
          _parseInt(record['assignedStartingStock'], fallback: count);
      (group['bundleInstances'] as List<Map<String, dynamic>>).addAll(
        instances,
      );
      final assignedAt = record['assignedAt'] ?? record['allocatedAt'];
      final groupAssignedAt = group['assignedAt'] ?? group['allocatedAt'];
      DateTime toDate(dynamic value) {
        if (value is Timestamp) return value.toDate();
        if (value is DateTime) return value;
        return DateTime.tryParse('$value') ?? DateTime(1970);
      }

      if (toDate(assignedAt).isAfter(toDate(groupAssignedAt))) {
        for (final field in [
          'name',
          'price',
          'costPrice',
          'imageUrl',
          'bundleId',
          'publicId',
          'assignedAt',
          'allocatedAt',
          'sourceDocId',
          'expirationDate',
          'items',
        ]) {
          if (record.containsKey(field) &&
              (field != 'price' ||
                  _parsePrice(record[field]) > 0 ||
                  _parsePrice(group[field]) <= 0)) {
            group[field] = record[field];
          }
        }
      }
    }
    return groups.values.toList();
  }

  String _bundleExpirationDate(Map<String, dynamic> bundleData) {
    return bundleExpirationDateLabel(bundleData);
  }

  bool _hasExpiredBundleItem(Map<String, dynamic> data) =>
      availableBundleStock(data) == 0;

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
      return expiryDate.isBefore(DateTime(today.year, today.month, today.day));
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
    final pageContext = context;
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
                        color: AppColors.primaryDark.withOpacity(0.18),
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
                            colors: [AppColors.primaryDark, AppColors.primary],
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
                                    color: AppColors.primaryDark,
                                  ),
                                  if ((item['variant']?.toString() ?? '')
                                      .isNotEmpty)
                                    _InfoChip(
                                      icon: Icons.tune_rounded,
                                      label: item['variant']?.toString() ?? '',
                                      color: AppColors.primaryDark,
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
                                  color: AppColors.blush,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 16,
                                      color: AppColors.primaryDark,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Current Stock: $currentStock',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  IconButton.filledTonal(
                                    tooltip: 'Decrease quantity',
                                    onPressed: () {
                                      final value =
                                          int.tryParse(qtyController.text) ?? 0;
                                      if (value > 1) {
                                        qtyController.text = '${value - 1}';
                                      }
                                    },
                                    icon: const Icon(Icons.remove_rounded),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _PinkTextField(
                                      controller: qtyController,
                                      label: 'Quantity to reduce',
                                      hint: 'Enter quantity',
                                      icon: Icons.remove_circle_outline,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    tooltip: 'Increase quantity',
                                    onPressed: () {
                                      final value =
                                          int.tryParse(qtyController.text) ?? 0;
                                      if (value < currentStock) {
                                        qtyController.text = '${value + 1}';
                                      }
                                    },
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue: selectedReason,
                                decoration: InputDecoration(
                                  labelText: 'Reason',
                                  labelStyle: const TextStyle(
                                    color: AppColors.primaryDark,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.flag_outlined,
                                    color: AppColors.primaryDark,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: AppColors.blush,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: AppColors.primaryDark,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.surfaceTint,
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
                                      var queuedOffline = false;
                                      final reductionId = FirebaseFirestore
                                          .instance
                                          .collection('stock_adjustments')
                                          .doc()
                                          .id;
                                      try {
                                        final firestore =
                                            FirebaseFirestore.instance;
                                        final docRef = firestore
                                            .collection('staff_inventory')
                                            .doc(sourceDocId);
                                        final adjustmentRef = firestore
                                            .collection('stock_adjustments')
                                            .doc(reductionId);
                                        final notificationRef = firestore
                                            .collection('admin_notifications')
                                            .doc();
                                        final itemId =
                                            item['id']?.toString() ??
                                            item['itemId']?.toString() ??
                                            item['variantId']?.toString() ??
                                            '';
                                        final itemName =
                                            item['name']?.toString() ?? '';
                                        final itemVariant =
                                            item['variant']?.toString() ?? '';
                                        final currentUser =
                                            FirebaseAuth.instance.currentUser;
                                        final staffName =
                                            currentUser?.displayName
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? currentUser!.displayName!
                                            : currentUser?.email
                                                      ?.split('@')
                                                      .first ??
                                                  'Staff';

                                        final connectivity =
                                            await Connectivity()
                                                .checkConnectivity();
                                        if (connectivity.contains(
                                          ConnectivityResult.none,
                                        )) {
                                          await _queueOfflineStockReduction(
                                            id: adjustmentRef.id,
                                            inventoryId: sourceDocId,
                                            item: item,
                                            quantity: quantity,
                                            categoryName: categoryName,
                                            reason: reason,
                                            comment: comment,
                                            staffId: currentUser?.uid ?? '',
                                            staffName: staffName,
                                          );
                                          queuedOffline = true;
                                        } else {
                                          final initialSnapshot = await docRef
                                              .get();
                                          final initialData = initialSnapshot
                                              .data();
                                          if (initialData == null) {
                                            throw StateError(
                                              'Inventory item no longer exists.',
                                            );
                                          }
                                          final sourceInventoryId =
                                              '${initialData['sourceInventoryId'] ?? item['sourceInventoryId'] ?? ''}'
                                                  .trim();
                                          final allocationRefs =
                                              <
                                                String,
                                                DocumentReference<
                                                  Map<String, dynamic>
                                                >
                                              >{docRef.id: docRef};
                                          final branchId =
                                              '${initialData['staffId'] ?? ''}'
                                                  .trim();
                                          if (branchId.isNotEmpty &&
                                              sourceInventoryId.isNotEmpty) {
                                            final allocations = await firestore
                                                .collection('staff_inventory')
                                                .where(
                                                  'staffId',
                                                  isEqualTo: branchId,
                                                )
                                                .get();
                                            for (final allocation
                                                in allocations.docs) {
                                              if (allocation
                                                      .data()['sourceInventoryId'] ==
                                                  sourceInventoryId) {
                                                allocationRefs[allocation.id] =
                                                    allocation.reference;
                                              }
                                            }
                                          }
                                          await firestore.runTransaction<void>((
                                            transaction,
                                          ) async {
                                            final snapshots = await Future.wait(
                                              allocationRefs.values.map(
                                                transaction.get,
                                              ),
                                            );
                                            final snapshotsById = {
                                              for (final inventorySnapshot
                                                  in snapshots)
                                                inventorySnapshot.id:
                                                    inventorySnapshot,
                                            };
                                            final snapshot =
                                                snapshotsById[docRef.id];
                                            final data = snapshot?.data();
                                            if (snapshot == null ||
                                                !snapshot.exists ||
                                                data == null) {
                                              throw StateError(
                                                'Inventory item no longer exists.',
                                              );
                                            }
                                            final actualSourceInventoryId =
                                                '${data['sourceInventoryId'] ?? sourceInventoryId}'
                                                    .trim();
                                            final staffId =
                                                '${data['staffId'] ?? ''}'
                                                    .trim();
                                            final allocationDocuments =
                                                <
                                                  String,
                                                  Map<String, dynamic>
                                                >{};
                                            for (final allocationSnapshot
                                                in snapshots) {
                                              final allocationData =
                                                  allocationSnapshot.data();
                                              if (allocationData == null ||
                                                  allocationData['isDeleted'] ==
                                                      true) {
                                                continue;
                                              }
                                              final sameScope =
                                                  allocationSnapshot.id ==
                                                      docRef.id ||
                                                  (staffId.isNotEmpty &&
                                                      actualSourceInventoryId
                                                          .isNotEmpty &&
                                                      allocationData['staffId'] ==
                                                          staffId &&
                                                      allocationData['sourceInventoryId'] ==
                                                          actualSourceInventoryId);
                                              if (sameScope) {
                                                allocationDocuments[allocationSnapshot
                                                        .id] =
                                                    allocationData;
                                              }
                                            }
                                            final result =
                                                reduceMatchingInventoryDocuments(
                                                  documents:
                                                      allocationDocuments,
                                                  itemId: itemId,
                                                  itemName: itemName,
                                                  variant: itemVariant,
                                                  quantity: quantity,
                                                  beverage: false,
                                                  fallbackUnitPrice:
                                                      _parsePrice(
                                                        item['price'],
                                                      ),
                                                );
                                            final previousStock =
                                                result.previousStock;
                                            final newStock = result.newStock;
                                            final lossAmount =
                                                result.unitPrice * quantity;

                                            final variantLabel =
                                                itemVariant.isNotEmpty
                                                ? ' ($itemVariant)'
                                                : '';
                                            for (final entry
                                                in result
                                                    .itemsByDocument
                                                    .entries) {
                                              final field =
                                                  allocationDocuments[entry
                                                          .key]!['items']
                                                      is List
                                                  ? 'items'
                                                  : 'sizes';
                                              transaction.update(
                                                firestore
                                                    .collection(
                                                      'staff_inventory',
                                                    )
                                                    .doc(entry.key),
                                                {field: entry.value},
                                              );
                                            }
                                            transaction.set(adjustmentRef, {
                                              'type': 'stock_adjustment',
                                              'userId': currentUser?.uid,
                                              'staffId': currentUser?.uid,
                                              'branchId': data['staffId'],
                                              'branchName':
                                                  data['branchName'] ??
                                                  data['staffName'] ??
                                                  '',
                                              'categoryName': categoryName,
                                              'categoryId': sourceDocId,
                                              if (actualSourceInventoryId
                                                  .isNotEmpty)
                                                'sourceInventoryId':
                                                    actualSourceInventoryId,
                                              'itemId':
                                                  item['id'] ??
                                                  item['itemId'] ??
                                                  item['variantId'] ??
                                                  '',
                                              'itemName': itemName,
                                              'variant': itemVariant,
                                              'quantity': quantity,
                                              'unitPrice': result.unitPrice,
                                              'lossAmount':
                                                  result.unitPrice * quantity,
                                              'previousStock':
                                                  result.previousStock,
                                              'newStock': result.newStock,
                                              'reason': reason,
                                              'comment': comment,
                                              'createdAt':
                                                  FieldValue.serverTimestamp(),
                                            });
                                            transaction.set(notificationRef, {
                                              'title': 'Stock reduced',
                                              'message':
                                                  '$staffName reduced $quantity x $itemName$variantLabel from $previousStock to $newStock. Expected sales decreased by ${formatMoney(lossAmount)}.',
                                              'category': 'Stock',
                                              'type': 'stock_adjustment',
                                              'itemName': itemName,
                                              'variant': itemVariant,
                                              'quantity': quantity,
                                              'reductionAmount': lossAmount,
                                              'categoryName': categoryName,
                                              'staffId': currentUser?.uid,
                                              'staffName': staffName,
                                              'isRead': false,
                                              'createdAt':
                                                  FieldValue.serverTimestamp(),
                                            });
                                          });
                                        }

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

                                        if (mounted) {
                                          Navigator.of(context).pop();
                                          showTopNotification(
                                            pageContext,
                                            queuedOffline
                                                ? 'Stock reduction saved offline. It will sync when online.'
                                                : 'Stock reduced successfully!',
                                          );
                                        }
                                      } catch (e) {
                                        if (e is FirebaseException &&
                                            const {
                                              'unavailable',
                                              'deadline-exceeded',
                                              'network-request-failed',
                                            }.contains(e.code)) {
                                          final currentUser =
                                              FirebaseAuth.instance.currentUser;
                                          final staffName =
                                              currentUser?.displayName
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? currentUser!.displayName!
                                              : currentUser?.email
                                                        ?.split('@')
                                                        .first ??
                                                    'Staff';
                                          await _queueOfflineStockReduction(
                                            id: reductionId,
                                            inventoryId: sourceDocId,
                                            item: item,
                                            quantity: quantity,
                                            categoryName: categoryName,
                                            reason: reason,
                                            comment: comment,
                                            staffId: currentUser?.uid ?? '',
                                            staffName: staffName,
                                          );
                                          InventoryService()
                                              .recordStockReduction(
                                                itemName: categoryName,
                                                variantName:
                                                    item['id']?.toString() ??
                                                    item['name']?.toString() ??
                                                    '',
                                                quantity: quantity,
                                                sourceInventoryId: sourceDocId,
                                              );
                                          if (mounted) {
                                            Navigator.of(context).pop();
                                            showTopNotification(
                                              pageContext,
                                              'Stock reduction saved offline. It will sync when online.',
                                            );
                                          }
                                          return;
                                        }
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
                                backgroundColor: AppColors.primaryDark,
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
    qtyController.dispose();
    commentController.dispose();
  }

  SnackBar _buildSnackBar(String message, {bool isError = false}) {
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError
          ? const Color(0xFFB71C1C)
          : AppColors.primaryDeep,
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

  Future<void> _showStaffActivityHistory({
    required String kind,
    required String categoryName,
    String? categoryId,
    Set<String> itemIds = const {},
    Set<String> itemNames = const {},
  }) => showStaffInventoryHistory(
    context,
    staffId: FirebaseAuth.instance.currentUser?.uid ?? '',
    kind: kind,
    categoryId: categoryId ?? '',
    categoryName: categoryName,
    itemIds: itemIds,
    itemNames: itemNames,
    scopeIds: _staffInventoryIds.toSet(),
  );

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
                      color: AppColors.primaryDark.withOpacity(0.18),
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
                          colors: [AppColors.primaryDark, AppColors.primary],
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
                                fillColor: AppColors.surfaceTint,
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
                                color: AppColors.primaryDark,
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
                                  color: AppColors.surfaceTint,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: AppColors.blush,
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
                                                  color: AppColors.primaryDark,
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
                                            color: AppColors.primaryDark,
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
                                      'Price: ${formatMoney(unitPrice)}',
                                      style: const TextStyle(
                                        color: AppColors.primaryDark,
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
                                          color: AppColors.primaryDark,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$formattedDate  $formattedTime',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.primaryDark,
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
            child: CircularProgressIndicator(color: AppColors.primaryDark),
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
              style: TextStyle(color: AppColors.primaryDark),
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
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.blush),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry['name']}${variant.isEmpty ? '' : ' ($variant)'}',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '-${entry['quantity']}',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Price: ${formatMoney((entry['price'] as double))}'),
                  const SizedBox(height: 4),
                  const Text('Reason: Stock reduction'),
                  const SizedBox(height: 4),
                  Text(
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCoffeeVoidDialog(Map<String, dynamic> category) async {
    final coffeeName = category['categoryName']?.toString() ?? 'Beverages';
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
                        colors: [AppColors.primaryDark, AppColors.primary],
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
                            'Void Beverages Item',
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
                          color: AppColors.primaryDark,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSize,
                          decoration: InputDecoration(
                            labelText: 'Size',
                            prefixIcon: const Icon(
                              Icons.straighten_rounded,
                              color: AppColors.primaryDark,
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
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Decrease quantity',
                              onPressed: () {
                                final value = _parseInt(
                                  quantityController.text,
                                );
                                quantityController.text =
                                    '${value > 1 ? value - 1 : 1}';
                                setState(() {});
                              },
                              icon: const Icon(Icons.remove),
                            ),
                            Expanded(
                              child: _PinkTextField(
                                controller: quantityController,
                                label: 'Quantity to void',
                                hint: 'Enter quantity',
                                icon: Icons.remove_circle_outline,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Increase quantity',
                              onPressed: () {
                                final value = _parseInt(
                                  quantityController.text,
                                );
                                quantityController.text = '${value + 1}';
                                setState(() {});
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedReason,
                          decoration: InputDecoration(
                            labelText: 'Reason',
                            prefixIcon: const Icon(
                              Icons.flag_outlined,
                              color: AppColors.primaryDark,
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
                                            'Please select a beverage size first',
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
                                        final connectivity =
                                            await Connectivity()
                                                .checkConnectivity();
                                        if (connectivity.contains(
                                          ConnectivityResult.none,
                                        )) {
                                          final user =
                                              FirebaseAuth.instance.currentUser;
                                          final userName =
                                              user?.displayName
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? user!.displayName!
                                              : user?.email?.split('@').first ??
                                                    'Staff';
                                          await OfflineStockReductionService()
                                              .enqueue({
                                                'id': FirebaseFirestore.instance
                                                    .collection(
                                                      'stock_adjustments',
                                                    )
                                                    .doc()
                                                    .id,
                                                'type': 'coffee_void',
                                                'inventoryId': sourceDocId,
                                                'coffeeId':
                                                    category['coffeeId']
                                                        ?.toString() ??
                                                    '',
                                                'itemId': '',
                                                'itemName': coffeeName,
                                                'variant': selectedSize,
                                                'quantity': quantity,
                                                'unitPrice': _parsePrice(
                                                  selectedItem['price'],
                                                ),
                                                'categoryName': coffeeName,
                                                'reason': selectedReason,
                                                'comment':
                                                    selectedReason == 'Other'
                                                    ? commentController.text
                                                          .trim()
                                                    : '',
                                                'staffId': user?.uid ?? '',
                                                'staffName': userName,
                                              });
                                          await _loadPendingOfflineReductions();
                                          if (mounted) {
                                            Navigator.pop(context);
                                            showTopNotification(
                                              context,
                                              'Beverages reduction saved offline. It will sync when online.',
                                            );
                                          }
                                          return;
                                        }
                                        if (sourceDocId.trim().isEmpty) {
                                          throw StateError(
                                            'Beverages inventory record was not found.',
                                          );
                                        }
                                        final docRef = FirebaseFirestore
                                            .instance
                                            .collection('staff_inventory')
                                            .doc(sourceDocId);
                                        final historyRef = FirebaseFirestore
                                            .instance
                                            .collection('stock_adjustments')
                                            .doc();
                                        final user =
                                            FirebaseAuth.instance.currentUser;
                                        await FirebaseFirestore.instance
                                            .runTransaction<void>((
                                              transaction,
                                            ) async {
                                              final snapshot = await transaction
                                                  .get(docRef);
                                              final snapshotData = snapshot
                                                  .data();
                                              if (!snapshot.exists ||
                                                  snapshotData == null) {
                                                throw StateError(
                                                  'Beverages inventory record was not found.',
                                                );
                                              }
                                              final inventoryField =
                                                  snapshotData['items'] is List
                                                  ? 'items'
                                                  : 'sizes';
                                              final result =
                                                  reduceMatchingInventoryRows(
                                                    rows:
                                                        snapshotData[inventoryField]
                                                            as List? ??
                                                        const [],
                                                    itemId: '',
                                                    itemName: coffeeName,
                                                    variant: selectedSize!,
                                                    quantity: quantity,
                                                    beverage: true,
                                                    fallbackUnitPrice:
                                                        _parsePrice(
                                                          selectedItem['price'],
                                                        ),
                                                  );
                                              transaction.update(docRef, {
                                                inventoryField: result.items,
                                                'updatedAt':
                                                    FieldValue.serverTimestamp(),
                                              });
                                              transaction.set(historyRef, {
                                                'type': 'coffee_void',
                                                'categoryId': sourceDocId,
                                                'categoryName': coffeeName,
                                                'coffeeId':
                                                    category['coffeeId']
                                                        ?.toString() ??
                                                    '',
                                                'isCoffee': true,
                                                'coffeeSize': selectedSize,
                                                'branchId':
                                                    snapshotData['staffId'],
                                                'branchName':
                                                    snapshotData['branchName'] ??
                                                    snapshotData['staffName'] ??
                                                    '',
                                                'itemName': coffeeName,
                                                'variant': selectedSize,
                                                'quantity': quantity,
                                                'unitPrice': result.unitPrice,
                                                'reason': reason,
                                                'comment':
                                                    selectedReason == 'Other'
                                                    ? commentController.text
                                                          .trim()
                                                    : '',
                                                'userId': user?.uid,
                                                'staffId': user?.uid,
                                                'createdAt':
                                                    FieldValue.serverTimestamp(),
                                              });
                                            })
                                            .timeout(
                                              const Duration(seconds: 15),
                                              onTimeout: () =>
                                                  throw TimeoutException(
                                                    'Saving took too long. Please check your connection and try again.',
                                                  ),
                                            );
                                        if (!mounted) return;
                                        Navigator.pop(context);
                                        showTopNotification(
                                          context,
                                          'Beverages item voided successfully!',
                                        );
                                      } catch (error) {
                                        if (mounted) {
                                          setState(() => isSaving = false);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            _buildSnackBar(
                                              'Failed to void beverage item: $error',
                                              isError: true,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryDark,
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
    final coffeeName = category['categoryName']?.toString() ?? 'Beverages';
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
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    color: AppColors.primaryDark,
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Beverages History',
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
                              hintText:
                                  'Search beverages, ID, price, reason, date',
                              prefixIcon: const Icon(Icons.search_rounded),
                              isDense: true,
                              filled: true,
                              fillColor: AppColors.surfaceTint,
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
                                  final data =
                                      doc.data() as Map<String, dynamic>?;
                                  final timestamp =
                                      data?['createdAt'] as Timestamp?;
                                  if (historyDate != null &&
                                      timestamp != null) {
                                    final date = timestamp.toDate().toLocal();
                                    final startOfDay = DateTime(
                                      historyDate!.year,
                                      historyDate!.month,
                                      historyDate!.day,
                                    );
                                    final endOfDay = startOfDay
                                        .add(const Duration(days: 1))
                                        .subtract(
                                          const Duration(microseconds: 1),
                                        );
                                    if (date.isBefore(startOfDay) ||
                                        date.isAfter(endOfDay)) {
                                      return false;
                                    }
                                  }
                                  if (historySearch.isEmpty) return true;
                                  final createdAtDate = timestamp
                                      ?.toDate()
                                      .toLocal();
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
                                    (aData?['createdAt'] as Timestamp?)
                                        ?.toDate() ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                                final bTime =
                                    (bData?['createdAt'] as Timestamp?)
                                        ?.toDate() ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                                return bTime.compareTo(aTime);
                              });
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No voided beverage items yet.',
                              style: TextStyle(color: AppColors.primaryDark),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data =
                                docs[index].data() as Map<String, dynamic>;
                            final quantity =
                                data['quantity']?.toString() ?? '0';
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
                                color: AppColors.surfaceTint,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: AppColors.blush),
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
                                      'Beverages',
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
                                                color: AppColors.primaryDark,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            if (coffeeId.isNotEmpty)
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
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFF81C784,
                                                    ),
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
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.blush,
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                            border: Border.all(
                                              color: AppColors.rose,
                                            ),
                                          ),
                                          child: Text(
                                            variant,
                                            style: const TextStyle(
                                              color: AppColors.primaryDark,
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
                                          color: AppColors.primaryDark,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                                    'Price: ${formatMoney(_parsePrice(data['unitPrice']))}',
                                    style: const TextStyle(
                                      color: AppColors.primaryDark,
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
    final availableBundleInstances = bundleInstances
        .where((instance) => bundleInstanceAvailable(instance, bundle))
        .toList();
    var bundleSearch = '';
    var selectedBundleFilter = '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final normalizedBundleSearch = bundleSearch.trim().toLowerCase();
            final filteredBundleInstances = availableBundleInstances.where((
              instance,
            ) {
              final index = bundleInstances.indexOf(instance);
              final instanceId = bundleInstanceDisplayId(
                bundle,
                instance,
                index,
              );
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
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 620,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withOpacity(0.18),
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
                            colors: [AppColors.primaryDark, AppColors.primary],
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
                            fillColor: AppColors.surfaceTint,
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
                                      color: AppColors.primaryDark,
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
                                  final instance =
                                      filteredBundleInstances[index];
                                  final items =
                                      instance['items'] as List<dynamic>? ?? [];
                                  final originalIndex = bundleInstances.indexOf(
                                    instance,
                                  );
                                  final instanceId = bundleInstanceDisplayId(
                                    bundle,
                                    instance,
                                    originalIndex,
                                  );

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceTint,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: AppColors.blush,
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
                                                          style:
                                                              const TextStyle(
                                                                color: Color(
                                                                  0xFF4A0020,
                                                                ),
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                              ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip:
                                                            'Copy bundle ID',
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        onPressed: () async {
                                                          await Clipboard.setData(
                                                            ClipboardData(
                                                              text: instanceId,
                                                            ),
                                                          );
                                                          if (!context
                                                              .mounted) {
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
                                                          0xFF963B58,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Bundle price: ${formatMoney(bundlePrice)}',
                                                    style: const TextStyle(
                                                      color:
                                                          AppColors.primaryDark,
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
                                              bgColor: const Color(0xFFE8F5E9),
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
                                              color: AppColors.primaryDark,
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
    final quantityController = TextEditingController(text: '1');
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
    final availableInstances = _bundleInstancesFromData(bundle)
        .asMap()
        .entries
        .where((entry) {
          return bundleInstanceAvailable(entry.value, bundle);
        })
        .toList();
    final maxReductionQuantity = currentStock < availableInstances.length
        ? currentStock
        : availableInstances.length;

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
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.78,
                  ),
                  child: SingleChildScrollView(
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
                              color: AppColors.primaryDark,
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
                            color: AppColors.primaryDark,
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
                                  final enteredId = bundleIdController.text
                                      .trim();
                                  final instances = _bundleInstancesFromData(
                                    bundle,
                                  );
                                  final matchingIndex = instances.indexWhere((
                                    instance,
                                  ) {
                                    final index = instances.indexOf(instance);
                                    final instanceId =
                                        '${instance['id'] ?? ''}'
                                            .trim()
                                            .isNotEmpty
                                        ? '${instance['id']}'.trim()
                                        : _bundleInstanceId(
                                            bundle['bundleId']?.toString() ??
                                                '',
                                            index,
                                          );
                                    return instanceId == enteredId ||
                                        bundleInstanceDisplayId(
                                              bundle,
                                              instance,
                                              index,
                                            ) ==
                                            enteredId;
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
                                      status != 'available' ||
                                      !bundleInstanceAvailable(
                                        instances[matchingIndex],
                                        bundle,
                                      )) {
                                    setDialogState(() {
                                      validationMessage =
                                          'Invalid bundle ID number.';
                                    });
                                    return;
                                  }
                                  final instance = instances[matchingIndex];
                                  final actualId =
                                      '${instance['id'] ?? ''}'
                                          .trim()
                                          .isNotEmpty
                                      ? '${instance['id']}'.trim()
                                      : _bundleInstanceId(
                                          bundle['bundleId']?.toString() ?? '',
                                          matchingIndex,
                                        );
                                  if (selectedBundleIds.contains(actualId)) {
                                    setDialogState(() {
                                      validationMessage =
                                          'Bundle ID already added.';
                                    });
                                    return;
                                  }
                                  setDialogState(() {
                                    selectedBundleIds.add(actualId);
                                    bundleIdController.clear();
                                    validationMessage = null;
                                  });
                                },
                                icon: const Icon(Icons.add_rounded),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.primaryDark,
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
                                  final index = availableInstances.indexWhere((
                                    entry,
                                  ) {
                                    final actualId =
                                        '${entry.value['id'] ?? ''}'.trim();
                                    return (actualId.isNotEmpty
                                            ? actualId
                                            : _bundleInstanceId(
                                                bundle['bundleId']
                                                        ?.toString() ??
                                                    '',
                                                entry.key,
                                              )) ==
                                        id;
                                  });
                                  if (index < 0) {
                                    return const SizedBox.shrink();
                                  }
                                  final entry = availableInstances[index];
                                  final displayId = bundleInstanceDisplayId(
                                    bundle,
                                    entry.value,
                                    entry.key,
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Chip(
                                      label: Text(displayId),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 15,
                                      ),
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
                          const SizedBox(height: 8),
                          const Text(
                            'Or reduce by quantity. Added bundle IDs take priority.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: 'Decrease quantity',
                                onPressed:
                                    _parseInt(quantityController.text) <= 1
                                    ? null
                                    : () {
                                        quantityController.text =
                                            '${_parseInt(quantityController.text) - 1}';
                                        setDialogState(() {});
                                      },
                                icon: const Icon(Icons.remove),
                              ),
                              Expanded(
                                child: _PinkTextField(
                                  controller: quantityController,
                                  label: 'Quantity',
                                  hint: 'Enter quantity',
                                  icon: Icons.inventory_2_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              IconButton.filledTonal(
                                tooltip: 'Increase quantity',
                                onPressed:
                                    _parseInt(quantityController.text) >=
                                        maxReductionQuantity
                                    ? null
                                    : () {
                                        quantityController.text =
                                            '${_parseInt(quantityController.text) + 1}';
                                        setDialogState(() {});
                                      },
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
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
                                color: AppColors.primaryDark,
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
                                      final reason =
                                          selectedReason?.trim() ?? '';
                                      final instances =
                                          _bundleInstancesFromData(bundle);
                                      final requestedQuantity =
                                          selectedBundleIds.isEmpty
                                          ? _parseInt(quantityController.text)
                                          : selectedBundleIds.length;
                                      if (selectedBundleIds.isEmpty &&
                                          (requestedQuantity <= 0 ||
                                              requestedQuantity >
                                                  maxReductionQuantity)) {
                                        setDialogState(() {
                                          validationMessage =
                                              'Enter a quantity from 1 to $maxReductionQuantity.';
                                        });
                                        return;
                                      }
                                      final idsToReduce =
                                          selectedBundleIds.isEmpty
                                          ? availableInstances
                                                .skip(
                                                  (availableInstances.length -
                                                          requestedQuantity)
                                                      .clamp(
                                                        0,
                                                        availableInstances
                                                            .length,
                                                      )
                                                      .toInt(),
                                                )
                                                .take(requestedQuantity)
                                                .map((entry) {
                                                  return entry.value['id']
                                                              ?.toString()
                                                              .trim()
                                                              .isNotEmpty ==
                                                          true
                                                      ? entry.value['id']
                                                            .toString()
                                                      : _bundleInstanceId(
                                                          bundle['bundleId']
                                                                  ?.toString() ??
                                                              '',
                                                          entry.key,
                                                        );
                                                })
                                                .toList()
                                          : List<String>.from(
                                              selectedBundleIds,
                                            );
                                      if (idsToReduce.isEmpty ||
                                          idsToReduce.length >
                                              maxReductionQuantity) {
                                        setDialogState(() {
                                          validationMessage =
                                              'Enter a valid bundle quantity or bundle ID.';
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
                                        for (final selectedId in idsToReduce) {
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
                                          final instance =
                                              instances[instanceIndex];
                                          instances[instanceIndex] = {
                                            ...instance,
                                            'status': 'reduced',
                                            'displayId':
                                                bundleInstanceDisplayId(
                                                  bundle,
                                                  instance,
                                                  instanceIndex,
                                                ),
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
                                        final docRef = FirebaseFirestore
                                            .instance
                                            .collection('staff_inventory')
                                            .doc(sourceDocId);
                                        final batch = FirebaseFirestore.instance
                                            .batch();
                                        batch.update(docRef, {
                                          'bundleInstances': instances,
                                          'bundleCount':
                                              currentStock - idsToReduce.length,
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                        final historyRef = FirebaseFirestore
                                            .instance
                                            .collection('stock_adjustments')
                                            .doc();
                                        final displayIds = idsToReduce.map((
                                          id,
                                        ) {
                                          final index = instances.indexWhere(
                                            (instance) =>
                                                '${instance['id'] ?? ''}'
                                                    .trim() ==
                                                id,
                                          );
                                          if (index < 0) return id;
                                          return bundleInstanceDisplayId(
                                            bundle,
                                            instances[index],
                                            index,
                                          );
                                        }).toList();
                                        final connectivity =
                                            await Connectivity()
                                                .checkConnectivity();
                                        if (connectivity.contains(
                                          ConnectivityResult.none,
                                        )) {
                                          await OfflineStockReductionService()
                                              .enqueue({
                                                'id': historyRef.id,
                                                'type':
                                                    'bundle_instance_adjustment',
                                                'inventoryId': sourceDocId,
                                                'sourceInventoryId':
                                                    bundle['sourceInventoryId'] ??
                                                    '',
                                                'bundleId':
                                                    bundle['bundleId'] ?? '',
                                                'bundleInstanceIds':
                                                    idsToReduce,
                                                'bundleDisplayIds': displayIds,
                                                'itemDisplayId':
                                                    displayIds.length == 1
                                                    ? displayIds.single
                                                    : '${bundle['bundleId'] ?? 'BND'}-${displayIds.length} items',
                                                'quantity': idsToReduce.length,
                                                'unitPrice': _parsePrice(
                                                  bundle['price'],
                                                ),
                                                'categoryName': bundleName,
                                                'reason': reason,
                                                'comment':
                                                    selectedReason == 'Other'
                                                    ? commentController.text
                                                          .trim()
                                                    : '',
                                                'staffId': user?.uid,
                                                'staffName':
                                                    user?.displayName ??
                                                    user?.email
                                                        ?.split('@')
                                                        .first ??
                                                    'Staff',
                                              });
                                          await _loadPendingOfflineReductions();
                                          if (!mounted) return;
                                          Navigator.pop(context);
                                          showTopNotification(
                                            context,
                                            '${idsToReduce.length} bundle(s) saved offline and will sync when online.',
                                          );
                                          return;
                                        }
                                        batch.set(historyRef, {
                                          'type': 'bundle_stock_adjustment',
                                          'userId': user?.uid,
                                          'staffId': user?.uid,
                                          'branchId': bundle['staffId'],
                                          'branchName':
                                              bundle['branchName'] ??
                                              bundle['staffName'] ??
                                              '',
                                          'isBundle': true,
                                          'bundleId': bundle['bundleId'] ?? '',
                                          'itemDisplayId':
                                              displayIds.length == 1
                                              ? displayIds.single
                                              : '${bundle['bundleId'] ?? 'BND'}-${displayIds.length} items',
                                          'categoryId': sourceDocId,
                                          'categoryName': bundleName,
                                          'itemName': bundleName,
                                          'bundlePrice': _parsePrice(
                                            bundle['price'],
                                          ),
                                          'bundleInstanceIds': idsToReduce,
                                          'bundleDisplayIds': displayIds,
                                          'quantity': idsToReduce.length,
                                          'previousStock': currentStock,
                                          'newStock':
                                              currentStock - idsToReduce.length,
                                          'reason': reason,
                                          'comment': selectedReason == 'Other'
                                              ? commentController.text.trim()
                                              : '',
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
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
                                        '${idsToReduce.length} bundle(s) reduced successfully!',
                                      );
                                    },
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                              ),
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
                                backgroundColor: AppColors.primaryDark,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
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
                ),
              ),
            );
          },
        );
      },
    );

    bundleIdController.dispose();
    commentController.dispose();
    quantityController.dispose();
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
    final instanceId = bundleInstanceDisplayId(bundle, instance, instanceIndex);
    final availableInstances = _bundleInstancesFromData(bundle)
        .asMap()
        .entries
        .where((entry) {
          return bundleInstanceAvailable(entry.value, bundle);
        })
        .toList();
    final maxReductionQuantity = currentStock < availableInstances.length
        ? currentStock
        : availableInstances.length;
    var reductionQuantity = maxReductionQuantity > 0 ? 1 : 0;

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
                              color: AppColors.primaryDeep,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.primaryDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoChip(
                      icon: Icons.inventory_2_rounded,
                      label: '$bundleName - $instanceId',
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Reduce quantity',
                          onPressed: reductionQuantity <= 1
                              ? null
                              : () => setDialogState(() => reductionQuantity--),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$reductionQuantity / $maxReductionQuantity',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Increase quantity',
                          onPressed: reductionQuantity >= maxReductionQuantity
                              ? null
                              : () => setDialogState(() => reductionQuantity++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Copy bundle ID',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: instanceId),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                _buildSnackBar('Bundle ID copied'),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        prefixIcon: const Icon(
                          Icons.flag_outlined,
                          color: AppColors.primaryDark,
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
                            sourceDocId.isEmpty ||
                            reductionQuantity <= 0 ||
                            reductionQuantity > maxReductionQuantity) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            _buildSnackBar(
                              'Unable to reduce this bundle',
                              isError: true,
                            ),
                          );
                          return;
                        }
                        final reducedEntries = availableInstances
                            .skip(availableInstances.length - reductionQuantity)
                            .toList();
                        final reducedIds = <String>[];
                        final reducedDisplayIds = <String>[];
                        for (final entry in reducedEntries) {
                          final id =
                              '${entry.value['id'] ?? ''}'.trim().isNotEmpty
                              ? '${entry.value['id']}'.trim()
                              : _bundleInstanceId(
                                  bundle['bundleId']?.toString() ?? '',
                                  entry.key,
                                );
                          reducedIds.add(id);
                          instances[entry.key] = {
                            ...instances[entry.key],
                            'status': 'reduced',
                            'displayId': bundleInstanceDisplayId(
                              bundle,
                              entry.value,
                              entry.key,
                            ),
                            'reductionReason': reason,
                            'reductionComment': selectedReason == 'Other'
                                ? commentController.text.trim()
                                : '',
                            'reducedAt': Timestamp.now(),
                          };
                          reducedDisplayIds.add(
                            bundleInstanceDisplayId(
                              bundle,
                              entry.value,
                              entry.key,
                            ),
                          );
                        }

                        final user = FirebaseAuth.instance.currentUser;
                        final docRef = FirebaseFirestore.instance
                            .collection('staff_inventory')
                            .doc(sourceDocId);
                        await docRef.update({
                          'bundleInstances': instances,
                          'bundleCount': (currentStock - reductionQuantity)
                              .clamp(0, currentStock),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        await FirebaseFirestore.instance
                            .collection('stock_adjustments')
                            .add({
                              'type': 'bundle_instance_adjustment',
                              'userId': user?.uid,
                              'staffId': user?.uid,
                              'branchId': bundle['staffId'],
                              'branchName':
                                  bundle['branchName'] ??
                                  bundle['staffName'] ??
                                  '',
                              'isBundle': true,
                              'bundleId': bundle['bundleId'] ?? '',
                              'itemDisplayId': reducedDisplayIds.length == 1
                                  ? reducedDisplayIds.single
                                  : '${bundle['bundleId'] ?? 'BND'}-${reducedDisplayIds.length} items',
                              'categoryId': sourceDocId,
                              'categoryName': bundleName,
                              'itemName': bundleName,
                              'bundleInstanceId': instanceId,
                              'bundleInstanceIds': reducedIds,
                              'bundleDisplayIds': reducedDisplayIds,
                              'quantity': reductionQuantity,
                              'previousStock': currentStock,
                              'newStock': (currentStock - reductionQuantity)
                                  .clamp(0, currentStock),
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
                        backgroundColor: AppColors.primaryDark,
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
    final bundleItemNames =
        (bundle['items'] as List?)
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
                        colors: [AppColors.primaryDark, AppColors.primary],
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
                              fillColor: AppColors.surfaceTint,
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
                              color: AppColors.primaryDark,
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
                              final createdAtDate = timestamp
                                  ?.toDate()
                                  .toLocal();
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
                                color: AppColors.surfaceTint,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.blush),
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
                                            color: AppColors.primaryDeep,
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
                                            color: AppColors.primaryDark,
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
                                    'Bundle price: ${formatMoney(_parsePrice(data['bundlePrice'] ?? bundle['price']))}',
                                    style: const TextStyle(
                                      color: AppColors.primaryDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Reason: ${data['reason'] ?? ''}',
                                    style: const TextStyle(
                                      color: AppColors.primaryDark,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Reduced on: $reducedOnLabel',
                                    style: const TextStyle(
                                      color: AppColors.primaryDark,
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
    final tabletLayout =
        widget.tabletLayout || MediaQuery.sizeOf(context).width >= 600;

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
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: tabletLayout ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryDark : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.primaryDark : AppColors.blush,
                width: 1.4,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryDark.withOpacity(0.18),
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
                  color: selected ? Colors.white : AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '$label ($count)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.primaryDeep,
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
      padding: EdgeInsets.fromLTRB(16, tabletLayout ? 10 : 18, 16, 0),
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
            label: 'Beverages',
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
          Icon(icon, size: 52, color: AppColors.primaryDark.withOpacity(0.3)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryDark,
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
        color: AppColors.blush,
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
          border: Border.all(color: AppColors.blush),
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
          color: AppColors.primaryDeep,
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
    Color color = AppColors.text,
  }) {
    return DataCell(
      SizedBox(
        width: width,
        child: Tooltip(
          message: value,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: weight, color: color),
          ),
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
        border: Border.all(color: AppColors.blush),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.06),
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
                          color: AppColors.primaryDeep,
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
                            color: AppColors.primaryDeep.withOpacity(0.62),
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
                    color: AppColors.primaryDark,
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
                      foregroundColor: AppColors.primaryDark,
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
                    color: AppColors.primaryDark,
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
                    AppColors.primaryDark.withOpacity(0.08),
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

  Widget _beverageViewButton(
    String label,
    bool selected,
    VoidCallback onPressed,
  ) => Padding(
    padding: const EdgeInsets.all(2),
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(
        label == 'Add-ons'
            ? Icons.add_circle_outline_rounded
            : Icons.local_cafe_outlined,
        size: 17,
      ),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: selected ? AppColors.primaryDark : Colors.white,
        foregroundColor: selected ? Colors.white : AppColors.primaryDark,
        elevation: selected ? 1 : 0,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  String _displayItemId(Map<String, dynamic> item, {String? fallback}) {
    for (final key in [
      'publicId',
      'addonId',
      'coffeeId',
      'bundleId',
      'id',
      'itemId',
      'variantId',
      'sourceItemId',
    ]) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      if (RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(value)) continue;
      return publicItemId(value);
    }
    final safeFallback = fallback?.trim() ?? '';
    return safeFallback.isNotEmpty ? safeFallback : '--';
  }

  String _allocationDateLabel(dynamic value) {
    final date = _allocationDateTime(value);
    if (date == null) return '--';
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  DateTime? _allocationDateTime(dynamic value) {
    return value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '');
  }

  Widget _tableReduceButton({
    required bool enabled,
    required VoidCallback onPressed,
    String label = 'Reduce',
    Widget? icon,
  }) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: icon ?? const Icon(Icons.remove_circle_outline_rounded, size: 16),
      label: Text(enabled ? label : 'Unavailable'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _batchButton(Map<String, dynamic> record, {String? itemId}) =>
      IconButton(
        tooltip: 'View batches',
        icon: const Icon(Icons.layers_outlined),
        onPressed: () => showInventoryBatches(
          context,
          allocationId: '${record['sourceDocId'] ?? ''}',
          scopeIds: _staffInventoryIds,
          itemId: itemId,
        ),
      );

  Widget _buildBundleList(List<Map<String, dynamic>> bundleDocs) {
    if (bundleDocs.isEmpty) {
      return _buildEmptyInventoryState(
        icon: Icons.inventory_2_outlined,
        message: 'No bundles found.',
      );
    }

    final availableBundleCount = bundleDocs.fold<int>(
      0,
      (total, bundle) => total + _bundleStockForData(bundle),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _tableBlock(
          title: 'Bundles',
          subtitle: 'Available bundles: $availableBundleCount',
          onHistory: () => _showStaffActivityHistory(
            kind: 'bundle',
            categoryName: 'Bundle',
            categoryId: '',
          ),
          columns: [
            _tableColumn('ID'),
            _tableColumn('Allocated date'),
            _tableColumn('Bundle Name'),
            _tableColumn('Price'),
            _tableColumn('Stock'),
            _tableColumn('Expire date'),
            _tableColumn('Availability'),
            _tableColumn('Action'),
          ],
          rows: bundleDocs.map((bundle) {
            final bundleName = bundle['name']?.toString() ?? 'Bundle';
            final bundleStock = _bundleStockForData(bundle);
            final bundlePending = _pendingBundleCount(bundle);
            final bundlePrice = _parsePrice(bundle['price']);
            final bundleId = _displayItemId(bundle);
            final bundleExpirationDate = _bundleExpirationDate(bundle);
            final availability = bundleStock == 0 && bundlePending > 0
                ? 'Pending confirmation'
                : _availabilityLabel(
                    stock: bundleStock,
                    expirationDate: bundleExpirationDate,
                    type: 'Bundle',
                    expiredBundle: _hasExpiredBundleInventory(bundle),
                  );

            return DataRow(
              cells: [
                _tableCell(bundleId, width: 160, color: AppColors.primaryDark),
                _tableCell(
                  _allocationDateLabel(
                    bundle['assignedAt'] ?? bundle['allocatedAt'],
                  ),
                  width: 120,
                ),
                _tableCell(bundleName, width: 180, weight: FontWeight.w900),
                _tableCell(
                  formatMoney(bundlePrice),
                  width: 100,
                  color: const Color(0xFF2E7D32),
                ),
                _tableCell(
                  '$bundleStock',
                  width: 70,
                  color: _stockColor(bundleStock, type: 'Bundle'),
                ),
                _tableCell(bundleExpirationDate, width: 120),
                _availabilityCell(availability),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _batchButton(bundle),
                      _tableReduceButton(
                        enabled: bundleStock > 0,
                        onPressed: () => _showBundleReductionDialog(bundle),
                        icon: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.remove_circle_rounded, size: 18),
                            Positioned(
                              right: -3,
                              bottom: -4,
                              child: Icon(
                                Icons.arrow_downward_rounded,
                                size: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
    final coffeeName = category['categoryName']?.toString() ?? 'Beverages';
    final coffeeId = _displayItemId(category);
    final items =
        (category['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final addonByName = <String, Map<String, dynamic>>{};
    for (final rawAddon in (category['addonOptions'] as List?) ?? const []) {
      if (rawAddon is! Map) continue;
      final addon = Map<String, dynamic>.from(rawAddon);
      if (addon['isDeleted'] == true || bundleExpired(addon, DateTime.now())) {
        continue;
      }
      final addonName = addon['name']?.toString().trim().toLowerCase() ?? '';
      if (addonName.isNotEmpty) {
        addonByName.putIfAbsent(addonName, () => addon);
      }
    }
    final addonDocs = addonByName.values.toList();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('completed_sales')
          .snapshots(),
      builder: (context, salesSnapshot) {
        final totalSold = beverageSalesToday(
          sales: [
            for (final doc in salesSnapshot.data?.docs ?? const []) doc.data(),
          ],
          now: DateTime.now(),
          branchIds: _staffInventoryIds.toSet(),
          coffeeId: coffeeId,
          coffeeName: coffeeName,
          publicId: category['publicId']?.toString() ?? '',
        );
        void showBeverageHistory() {
          _showStaffActivityHistory(
            kind: 'beverages',
            categoryName: 'Beverages',
          );
        }

        void showAddonHistory() => _showStaffActivityHistory(
          kind: 'addons',
          categoryName: 'Beverages Add-ons',
          categoryId: '',
          itemIds: {
            for (final addon in addonDocs)
              for (final key in ['id', 'addonId', 'publicId', 'itemId'])
                if (addon[key]?.toString().trim().isNotEmpty == true)
                  addon[key].toString().trim(),
          },
          itemNames: {
            for (final addon in addonDocs)
              if (addon['name']?.toString().trim().isNotEmpty == true)
                addon['name'].toString().trim(),
          },
        );

        int addonSoldQuantity(Map<String, dynamic> addon) {
          final addonName = '${addon['name'] ?? ''}'.trim().toLowerCase();
          if (addonName.isEmpty) return 0;
          var sold = 0;
          for (final doc in salesSnapshot.data?.docs ?? const []) {
            final sale = doc.data();
            if (sale['isVoided'] == true ||
                sale['isDeleted'] == true ||
                ![
                  'void',
                  'voided',
                  'cancelled',
                  'canceled',
                ].contains('${sale['status'] ?? ''}'.toLowerCase()) ||
                (!_staffInventoryIds.contains('${sale['branchId'] ?? ''}') &&
                    !_staffInventoryIds.contains('${sale['userId'] ?? ''}'))) {
              continue;
            }
            for (final rawLine
                in (sale['items'] as List? ?? const []).whereType<Map>()) {
              final line = Map<String, dynamic>.from(rawLine);
              final lineQuantity = _parseInt(line['quantity'], fallback: 1);
              final nestedAddons = [
                ...(line['addons'] as List? ?? const []),
                ...(line['addOns'] as List? ?? const []),
                ...(line['selectedAddons'] as List? ?? const []),
              ].whereType<Map>();
              if (nestedAddons.isNotEmpty) {
                for (final rawAddon in nestedAddons) {
                  if ('${rawAddon['name'] ?? ''}'.trim().toLowerCase() ==
                      addonName) {
                    sold +=
                        lineQuantity *
                        _parseInt(
                          rawAddon['quantity'] ?? rawAddon['count'],
                          fallback: 1,
                        );
                  }
                }
              } else if ('${line['addonName'] ?? ''}'.trim().toLowerCase() ==
                  addonName) {
                sold += lineQuantity;
              }
            }
          }
          return sold;
        }

        final beverageTable = _tableBlock(
          title: 'Beverages',
          subtitle: 'Available Beverages: ${items.isEmpty ? 0 : 1}',
          onHistory: showBeverageHistory,
          compact: true,
          columns: [
            _tableColumn('ID'),
            _tableColumn('Allocated date'),
            _tableColumn('Beverages Name'),
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
                      : formatMoney(_parsePrice(item['price']));
                }

                return DataRow(
                  cells: [
                    _tableCell(
                      coffeeId.isNotEmpty ? coffeeId : '--',
                      width: 105,
                      color: AppColors.primaryDark,
                    ),
                    _tableCell(
                      _allocationDateLabel(
                        category['assignedAt'] ?? category['allocatedAt'],
                      ),
                      width: 120,
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _batchButton(category),
                          _tableReduceButton(
                            enabled: true,
                            label: 'Void',
                            onPressed: () => _showCoffeeVoidDialog(category),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              })(),
          ],
        );
        final addonQuery = _tableSearchQuery.trim().toLowerCase();
        final searchedAddons = addonDocs.where((addon) {
          if (addonQuery.isEmpty) return true;
          return [
            addon['name']?.toString() ?? '',
            _displayItemId(addon),
            addon['priceDelta']?.toString() ?? addon['price']?.toString() ?? '',
          ].join(' ').toLowerCase().contains(addonQuery);
        }).toList();
        final addonsTable = _tableBlock(
          title: 'Beverages Add-ons',
          subtitle: 'Available Add-ons: ${searchedAddons.length}',
          onHistory: showAddonHistory,
          compact: true,
          columns: [
            _tableColumn('ID'),
            _tableColumn('Allocated date'),
            _tableColumn('Add-on name'),
            _tableColumn('Price'),
            _tableColumn('Sold'),
            _tableColumn('Action'),
          ],
          rows: searchedAddons.map((addon) {
            return DataRow(
              cells: [
                _tableCell(_displayItemId(addon), width: 100),
                _tableCell(
                  _allocationDateLabel(
                    addon['assignedAt'] ??
                        addon['allocatedAt'] ??
                        category['assignedAt'],
                  ),
                  width: 120,
                ),
                _tableCell(
                  addon['name']?.toString() ?? 'Add-on',
                  width: 170,
                  weight: FontWeight.w800,
                ),
                _tableCell(
                  formatMoney(
                    _parsePrice(addon['priceDelta'] ?? addon['price']),
                  ),
                  width: 100,
                ),
                _tableCell('${addonSoldQuantity(addon)}', width: 70),
                DataCell(_batchButton(addon, itemId: _displayItemId(addon))),
              ],
            );
          }).toList(),
        );

        return _AnimatedCategorySection(
          index: index,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.blush),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _beverageViewButton(
                          'Beverages',
                          !_showCoffeeAddonsTable,
                          () => setState(() => _showCoffeeAddonsTable = false),
                        ),
                      ),
                      Expanded(
                        child: _beverageViewButton(
                          'Add-ons',
                          _showCoffeeAddonsTable,
                          () => setState(() => _showCoffeeAddonsTable = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showCoffeeAddonsTable) addonsTable else beverageTable,
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
                color: AppColors.blush.withOpacity(0.8),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withOpacity(0.08),
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
                      colors: [AppColors.primaryDark, AppColors.primary],
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
                            label: '${formatMoney(bundlePrice)}',
                            bgColor: const Color(0xFFE8F5E9),
                            textColor: const Color(0xFF2E7D32),
                          ),
                          if ((bundle['bundleId']?.toString() ?? '').isNotEmpty)
                            _ItemTag(
                              icon: Icons.confirmation_number_outlined,
                              label: bundle['bundleId']?.toString() ?? '',
                              bgColor: AppColors.blush,
                              textColor: AppColors.primaryDark,
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
                                foregroundColor: AppColors.primaryDark,
                                side: const BorderSide(
                                  color: AppColors.blush,
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
                                backgroundColor: AppColors.primaryDark,
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
    final coffeeName = category['categoryName']?.toString() ?? 'Beverages';
    final coffeeId = inventoryDisplayId(category);
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
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withOpacity(0.28),
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
                          coffeeId.isNotEmpty ? 'BEVERAGES - $coffeeId' : 'BEVERAGES',
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
                    color: AppColors.blush.withOpacity(0.8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withOpacity(0.07),
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
                                                color: AppColors.primaryDark,
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
                          label: '${formatMoney(price)}',
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
                              ? ' +${formatMoney(addonPrice)}'
                              : '';
                          return _ItemTag(
                            icon: Icons.add_circle_outline_rounded,
                            label: '$addonName$priceLabel',
                            bgColor: AppColors.blush,
                            textColor: AppColors.primaryDark,
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
    var displayAddons = addonDocs;
    final needsCanonicalIds = addonDocs.any(
      (addon) => _displayItemId(addon) == '--',
    );
    if (needsCanonicalIds) {
      try {
        displayAddons = await Future.wait(
          addonDocs.map((addon) async {
            if (_displayItemId(addon) != '--') {
              return addon;
            }
            final sourceId =
                (addon['id'] ?? addon['sourceInventoryId'] ?? addon['addonId'])
                    ?.toString()
                    .trim();
            if (sourceId == null || sourceId.isEmpty) return addon;
            final canonical = await FirebaseFirestore.instance
                .collection('coffee_addons')
                .doc(sourceId)
                .get();
            final canonicalData = canonical.data();
            final canonicalId =
                canonicalData?['publicId'] ?? canonicalData?['addonId'];
            if (canonicalId == null ||
                canonicalId.toString().trim().isEmpty ||
                RegExp(
                  r'^[A-Za-z0-9]{20}$',
                ).hasMatch(canonicalId.toString().trim())) {
              return addon;
            }
            return {...addon, 'publicId': canonicalId};
          }),
        );
      } catch (error) {
        debugPrint('Unable to resolve beverage add-on IDs: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            _buildSnackBar(
              'Could not refresh add-on IDs: $error',
              isError: true,
            ),
          );
        }
      }
    }
    displayAddons = displayAddons
        .map(
          (addon) => {
            ...addon,
            'allocatedAt':
                addon['assignedAt'] ??
                addon['allocatedAt'] ??
                category['assignedAt'] ??
                category['allocatedAt'],
          },
        )
        .toList();
    if (!mounted) return;
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
                        colors: [AppColors.primaryDark, AppColors.primary],
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
                            'Beverages Add-ons',
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
                          color: AppColors.primaryDark,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceTint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.blush),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final filteredAddons = displayAddons.where((addon) {
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
                              style: TextStyle(color: AppColors.primaryDark),
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 650,
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.0),
                                  1: FlexColumnWidth(1.0),
                                  2: FlexColumnWidth(1.4),
                                  3: FlexColumnWidth(1.0),
                                  4: FlexColumnWidth(1.1),
                                  5: FlexColumnWidth(0.9),
                                },
                                border: TableBorder(
                                  horizontalInside: BorderSide(
                                    color: AppColors.blush,
                                  ),
                                ),
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF963B58,
                                      ).withOpacity(0.08),
                                    ),
                                    children: const [
                                      _AddonHeaderCell('ID'),
                                      _AddonHeaderCell('Allocated'),
                                      _AddonHeaderCell('Add-on'),
                                      _AddonHeaderCell('Expire date'),
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
                                          _allocationDateLabel(
                                            addon['allocatedAt'],
                                          ),
                                        ),
                                        _AddonCell(
                                          addonName,
                                          weight: FontWeight.w800,
                                        ),
                                        _AddonCell(
                                          addon['expirationDate']
                                                      ?.toString()
                                                      .trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? addon['expirationDate']
                                                    .toString()
                                              : '--',
                                        ),
                                        _AddonCell(
                                          status,
                                          color:
                                              status.toLowerCase() ==
                                                  'available'
                                              ? const Color(0xFF2E7D32)
                                              : const Color(0xFFC62828),
                                        ),
                                        _AddonCell(
                                          formatMoney(price),
                                          color: const Color(0xFF2E7D32),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
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
              backgroundColor: AppColors.primaryDark,
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
        'categoryName': category['categoryName']?.toString() ?? 'Beverages',
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
              border: Border.all(color: AppColors.blush.withOpacity(0.8)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
                _ItemTag(
                  icon: Icons.payments_outlined,
                  label: '+${formatMoney(price)}',
                  bgColor: AppColors.blush,
                  textColor: AppColors.primaryDark,
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
        onHistory: () => _showStaffActivityHistory(
          kind: 'categories',
          categoryName: categoryName,
          categoryId:
              category['categoryId']?.toString() ??
              (items.isNotEmpty
                  ? items.first['sourceDocId']?.toString()
                  : null),
          itemIds: {
            for (final item in items)
              for (final key in ['itemId', 'id', 'publicId', 'sourceDocId'])
                if (item[key]?.toString().trim().isNotEmpty == true)
                  item[key].toString().trim(),
            for (final item in items) _displayItemId(item),
          },
          itemNames: {
            for (final item in items)
              if (item['name']?.toString().trim().isNotEmpty == true)
                item['name'].toString().trim(),
          },
        ),
        columns: [
          _tableColumn('ID'),
          _tableColumn('Allocated date'),
          _tableColumn('Items Name'),
          _tableColumn('Price'),
          _tableColumn('Stock'),
          _tableColumn('Expire date'),
          _tableColumn('Availability'),
          _tableColumn('Action'),
        ],
        rows: items.map((item) {
          final itemStock = _stockForItem(item);
          final availability = _availabilityLabel(
            stock: itemStock,
            expirationDate: item['expirationDate'],
            type: 'Categories',
          );
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
                color: AppColors.primaryDark,
              ),
              _tableCell(
                _allocationDateLabel(item['allocatedAt'] ?? item['assignedAt']),
                width: 120,
              ),
              _tableCell(
                item['name']?.toString() ?? 'Item',
                width: 180,
                weight: FontWeight.w900,
              ),
              _tableCell(
                formatMoney(_parsePrice(item['price'])),
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
              _availabilityCell(availability),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _batchButton(
                      item,
                      itemId: '${item['id'] ?? item['itemId']}',
                    ),
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
                  ],
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
    final compact = MediaQuery.sizeOf(context).width < 900;
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

      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 14 : 20,
              compact ? 12 : 16,
              0,
            ),
            child: SizedBox(
              height: compact ? 46 : 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categoryDocs.length + 1,
                separatorBuilder: (_, _) => SizedBox(width: compact ? 8 : 10),
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
                          constraints: BoxConstraints(
                            minWidth: compact ? 72 : 88,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 12,
                            vertical: compact ? 7 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primaryDark
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? AppColors.primaryDark
                                  : AppColors.blush,
                              width: 1.3,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.apps_rounded,
                                size: compact ? 14 : 16,
                                color: selected
                                    ? Colors.white
                                    : AppColors.primaryDark,
                              ),
                              SizedBox(width: compact ? 6 : 8),
                              Text(
                                'All',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppColors.primaryDeep,
                                  fontSize: compact ? 12 : 13,
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
                        constraints: BoxConstraints(
                          minWidth: compact ? 104 : 128,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 12 : 18,
                          vertical: compact ? 8 : 13,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primaryDark
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? AppColors.primaryDark
                                : AppColors.blush,
                            width: 1.3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF963B58,
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
                              size: compact ? 14 : 16,
                              color: selected
                                  ? Colors.white
                                  : AppColors.primaryDark,
                            ),
                            SizedBox(width: compact ? 6 : 8),
                            Flexible(
                              child: Text(
                                categoryName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppColors.primaryDeep,
                                  fontSize: compact ? 12 : 13,
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
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
              children: [
                if (_showAllCategoryItems)
                  ...categoryDocs.asMap().entries.map(
                    (entry) => _buildCategoryTable(entry.value, entry.key),
                  )
                else
                  _buildCategoryTable(selectedCategory, 0),
              ],
            ),
          ),
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
                    colors: [AppColors.primaryDark, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withOpacity(0.28),
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
                        color: AppColors.blush.withOpacity(0.8),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryDark.withOpacity(0.07),
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
                                  AppColors.primaryDark,
                                  AppColors.primaryDark.withOpacity(0.2),
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
                                    color: AppColors.text,
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
                                        bgColor: AppColors.blush,
                                        textColor: AppColors.primaryDark,
                                      ),
                                    if ((item['id']?.toString() ?? '')
                                        .isNotEmpty)
                                      _ItemTag(
                                        icon:
                                            Icons.confirmation_number_outlined,
                                        label: 'ID: ${_displayItemId(item)}',
                                        bgColor: AppColors.blush,
                                        textColor: AppColors.primaryDark,
                                      ),
                                    _ItemTag(
                                      icon: Icons.payments_outlined,
                                      label: formatMoney(
                                        _parsePrice(item['price']),
                                      ),
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
                          _batchButton(
                            item,
                            itemId: '${item['id'] ?? item['itemId']}',
                          ),
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
                              backgroundColor: AppColors.primaryDark,
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
    final tabletLayout =
        widget.tabletLayout || MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.surfaceTint,
      body: TopEdgeRefresh(
        displacement: 24,
        color: AppColors.primary,
        onRefresh: _refreshInventory,
        notificationPredicate: (notification) => notification.depth <= 1,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              automaticallyImplyLeading: false,
              expandedHeight: tabletLayout ? 146 : 160,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: AppColors.primaryDark,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryDeep,
                        AppColors.primaryDark,
                        AppColors.primary,
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
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _isFilteredCategory
                                            ? widget.selectedIsBundle
                                                  ? (widget.selectedCategoryName ??
                                                        'Selected Bundle')
                                                  : _isCoffeeView
                                                  ? '${widget.selectedCategoryName ?? 'Selected'} Beverages'
                                                  : '${widget.selectedCategoryName ?? 'Selected'} Categories'
                                            : 'Inventory',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    KeyedSubtree(
                                      key: widget.inventoryActionsTourKey,
                                      child: AllocationChecklistButton(
                                        scopeIds: _staffInventoryIds,
                                        checklistTourKey:
                                            widget.inventoryChecklistTourKey,
                                        returnsTourKey:
                                            widget.inventoryReturnsTourKey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isFilteredCategory
                                      ? widget.selectedIsBundle
                                            ? 'Manage this bundle inventory'
                                            : _isCoffeeView
                                            ? 'Manage this beverage flavor'
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
                        color: AppColors.primaryDark.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Error loading items',
                        style: TextStyle(color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildInventoryLoadingState();
              }

              final docs = snapshot.data?.docs ?? [];
              if (snapshot.hasData &&
                  (!snapshot.data!.metadata.isFromCache || docs.isNotEmpty)) {
                unawaited(
                  LocalDatabaseSyncService().cacheStaffInventorySnapshot(
                    _staffInventoryIds,
                    docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return {...data, '_localDocId': doc.id};
                    }),
                    authoritative: !snapshot.data!.metadata.isFromCache,
                  ),
                );
              }
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

                  final projectedDocs = OfflineStockReductionService()
                      .applyPendingToInventoryDocuments(
                        docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {...data, '_localDocId': doc.id};
                        }),
                        _pendingOfflineReductions,
                      );
                  final visibleDocs = <Map<String, dynamic>>[];
                  for (final projectedData in projectedDocs) {
                    final documentId =
                        projectedData['_localDocId']?.toString() ?? '';
                    final data = _inventoryDataWithPendingSales(
                      projectedData,
                      documentId,
                    );
                    if (data['isDeleted'] == true) continue;
                    if (data['isAddon'] == true) {
                      if (bundleExpired(data, DateTime.now())) continue;
                      visibleDocs.add({...data, 'sourceDocId': documentId});
                      continue;
                    }
                    final sourceId =
                        data['sourceInventoryId']?.toString() ?? '';
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
                              documentId == selectedSourceId);
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
                        'name': data['name'] ?? 'Beverages',
                        'publicId':
                            rootData['publicId'] ??
                            rootData['coffeeId'] ??
                            data['publicId'],
                        'coffeeId':
                            rootData['coffeeId'] ??
                            rootData['publicId'] ??
                            data['coffeeId'],
                        'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                        'items': coffeeItems,
                        'addonOptions': coffeeItems
                            .expand(
                              (item) => item['addons'] as List<dynamic>? ?? [],
                            )
                            .whereType<Map>()
                            .map((addon) => Map<String, dynamic>.from(addon))
                            .toList(),
                        'sourceDocId': documentId,
                        'isCoffee': true,
                      });
                      continue;
                    }

                    if (data['isBundle'] == true) {
                      if (rootData['isBundle'] != true) continue;

                      if (_hasExpiredBundleItem(data)) continue;
                      if (_bundleStockForData(data) <= 0 &&
                          _pendingBundleCount(data) == 0) {
                        continue;
                      }
                      visibleDocs.add({
                        ...data,
                        'name': rootData['name'] ?? data['name'],
                        'publicId': rootData['publicId'] ?? data['publicId'],
                        'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                        'price':
                            _parsePrice(data['price'] ?? data['bundlePrice']) >
                                0
                            ? data['price'] ?? data['bundlePrice']
                            : rootData['price'] ?? rootData['bundlePrice'],
                        'sourceDocId': documentId,
                      });
                      continue;
                    }

                    final rootItems =
                        ((rootData['items'] as List<dynamic>?) ?? [])
                            .whereType<Map>()
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                    final alignedData = alignInventoryDisplayIds(
                      data,
                      rootData,
                    );
                    final activeItems =
                        ((alignedData['items'] as List<dynamic>?) ?? [])
                            .whereType<Map>()
                            .map((item) => Map<String, dynamic>.from(item))
                            .where((item) {
                              final expirationDate =
                                  item['expirationDate']?.toString() ?? '';
                              return !_isExpiredItem(expirationDate) &&
                                  (rootItems.isEmpty ||
                                      rootItems.any(
                                        (root) =>
                                            inventoryVariantsMatch(root, item),
                                      ));
                            })
                            .toList();
                    if (activeItems.isEmpty) continue;
                    visibleDocs.add({
                      ...data,
                      'name': rootData['name'] ?? data['name'],
                      'publicId': rootData['publicId'] ?? data['publicId'],
                      'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                      'items': activeItems,
                      'sourceDocId': documentId,
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
                        (data['items'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final itemRecords = items.map((item) {
                      final itemData = Map<String, dynamic>.from(item);
                      itemData['sourceDocId'] = data['sourceDocId'];
                      itemData['sourceInventoryId'] = data['sourceInventoryId'];
                      itemData['categoryName'] = categoryName;
                      itemData['allocatedAt'] =
                          itemData['assignedAt'] ??
                          data['assignedAt'] ??
                          data['allocatedAt'];
                      return itemData;
                    }).toList();
                    if (itemRecords.isEmpty) continue;
                    final categoryKey =
                        data['sourceInventoryId']
                                ?.toString()
                                .trim()
                                .isNotEmpty ==
                            true
                        ? data['sourceInventoryId'].toString()
                        : data['sourceDocId']?.toString() ?? categoryName;
                    final previousCategory = groupedCategories[categoryKey];
                    final allocationDate =
                        data['assignedAt'] ?? data['allocatedAt'];
                    final currentAllocationDate =
                        _allocationDateTime(allocationDate) ?? DateTime(1970);
                    final previousAllocationDate =
                        _allocationDateTime(previousCategory?['allocatedAt']) ??
                        DateTime(1970);
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
                      'items': [
                        ...aggregateCategoryAllocationItems([
                          ...?groupedCategories[categoryKey]?['items'] as List?,
                          ...itemRecords,
                        ]),
                      ],
                      'addonOptions': data['addonOptions'] ?? const [],
                      'isCoffee': data['isCoffee'] == true,
                      'sourceDocId': data['sourceDocId'],
                      'publicId': data['publicId'],
                      'coffeeId': data['coffeeId'],
                      'allocatedAt':
                          currentAllocationDate.isAfter(previousAllocationDate)
                          ? allocationDate
                          : previousCategory?['allocatedAt'] ?? allocationDate,
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
                  final bundleDocs = _groupBundleAllocations(
                    visibleDocs.where((data) => data['isBundle'] == true),
                  );
                  final addonByName = <String, Map<String, dynamic>>{};
                  for (final data in visibleDocs) {
                    if (data['isAddon'] != true) continue;
                    final name = data['name']?.toString().trim() ?? '';
                    if (name.isNotEmpty) {
                      addonByName.putIfAbsent(name, () => data);
                    }
                  }
                  for (final data in visibleDocs) {
                    if (data['isAddon'] == true) {
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
                            'publicId': data['publicId'],
                            'coffeeId': data['coffeeId'],
                          });
                          final items =
                              (data['items'] as List?)
                                  ?.whereType<Map>()
                                  .map(
                                    (item) => Map<String, dynamic>.from(item),
                                  )
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

                  final searchedCategoryDocs = searchedCategoryData(
                    categoryDocs,
                  );
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
                        _showCoffee =
                            coffeeDocs.isNotEmpty && bundleDocs.isEmpty;
                        _showAddons = false;
                      });
                    });
                  }

                  if (categoryDocs.isEmpty &&
                      bundleDocs.isEmpty &&
                      coffeeDocs.isEmpty &&
                      addonDocs.isEmpty &&
                      _pendingOfflineReductions.isEmpty) {
                    return KeyedSubtree(
                      key: widget.inventoryTourKey,
                      child: _buildEmptyInventoryState(
                        icon: Icons.category_outlined,
                        message: 'No items found.',
                      ),
                    );
                  }

                  return Column(
                    children: [
                      if (_pendingOfflineReductions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                if (_syncingOfflineReductions)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF8A4B08),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 18,
                                    color: Color(0xFF8A4B08),
                                  ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _syncingOfflineReductions
                                            ? 'Syncing saved offline reductions'
                                            : _inventoryOnline
                                            ? 'Saved offline • waiting to sync'
                                            : 'Saved offline • waiting for internet',
                                        style: const TextStyle(
                                          color: Color(0xFF8A4B08),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            transitionBuilder:
                                                (child, animation) =>
                                                    FadeTransition(
                                                      opacity: animation,
                                                      child: SlideTransition(
                                                        position: Tween<Offset>(
                                                          begin: const Offset(
                                                            0,
                                                            0.3,
                                                          ),
                                                          end: Offset.zero,
                                                        ).animate(animation),
                                                        child: child,
                                                      ),
                                                    ),
                                            child: Text(
                                              '${_pendingOfflineReductions.length}',
                                              key: ValueKey(
                                                _pendingOfflineReductions
                                                    .length,
                                              ),
                                              style: const TextStyle(
                                                color: Color(0xFF8A4B08),
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'stock reduction(s) remaining',
                                            style: TextStyle(
                                              color: Color(0xFF8A4B08),
                                              fontWeight: FontWeight.w600,
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
                        ),
                      if (!_isFilteredCategory)
                        _buildInventoryToggle(
                          categoryCount: categoryDocs.length,
                          bundleCount: bundleDocs.length,
                          coffeeCount: coffeeDocs.length,
                          addonCount: addonDocs.length,
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          tabletLayout ? 16 : 20,
                          tabletLayout ? 6 : 10,
                          tabletLayout ? 16 : 20,
                          tabletLayout ? 8 : 12,
                        ),
                        child: TextField(
                          onChanged: (value) =>
                              setState(() => _tableSearchQuery = value),
                          decoration: InputDecoration(
                            hintText: 'Search',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.primaryDark,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.rose,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: KeyedSubtree(
                          key: widget.inventoryTourKey,
                          child: widget.selectedIsCoffee
                              ? _buildCategoryList(
                                  searchedCoffeeDocs,
                                  emptyMessage: 'No beverage items found.',
                                )
                              : widget.selectedIsBundle
                              ? _buildBundleList(searchedBundleDocs)
                              : _isFilteredCategory
                              ? _buildCategoryList(
                                  widget.selectedIsCoffee
                                      ? searchedCoffeeDocs
                                      : searchedCategoryDocs,
                                  emptyMessage: widget.selectedIsCoffee
                                      ? 'No beverage items found.'
                                      : 'No items found.',
                                )
                              : _showCoffee
                              ? _buildCategoryList(
                                  searchedCoffeeDocs,
                                  emptyMessage: 'No beverage items found.',
                                )
                              : _showCategories
                              ? _buildCategoryList(
                                  searchedCategoryDocs,
                                  emptyMessage: 'No items found.',
                                )
                              : _buildBundleList(searchedBundleDocs),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
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
          color: AppColors.primaryDeep,
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
    this.color = AppColors.text,
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
        Icon(icon, size: 13, color: AppColors.primaryDark),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.primaryDeep),
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
        prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 18),
        labelStyle: const TextStyle(color: AppColors.primaryDark),
        hintStyle: TextStyle(
          color: AppColors.primaryDark.withOpacity(0.4),
          fontSize: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.blush, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        filled: true,
        fillColor: AppColors.surfaceTint,
      ),
    );
  }
}
