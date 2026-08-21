// dashboard_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/inventory_service.dart';
import '../services/cash_drawer_service.dart';
import '../services/local_database_sync_service.dart';
import '../Admin_pages/Admin/Message.dart';
import 'AllCateg.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

String _formatDate(DateTime dt) {
  const months = [
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
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _formatTime(DateTime dt) {
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $ampm';
}

String _formatDateTime(DateTime dt) =>
    '${_formatDate(dt)} · ${_formatTime(dt)}';

class _CachedDoc {
  final String id;
  final Map<String, dynamic> _data;

  const _CachedDoc(this.id, this._data);

  factory _CachedDoc.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return _CachedDoc(doc.id, doc.data());
  }

  factory _CachedDoc.fromMap(Map<String, dynamic> map) {
    final id = map['_localDocId']?.toString() ?? map['id']?.toString() ?? '';
    final data = Map<String, dynamic>.from(map)..remove('_localDocId');
    return _CachedDoc(id, data);
  }

  Map<String, dynamic> data() => _data;
}

bool _isExpiredInventoryItem(String expirationDate) {
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

// ═══════════════════════════════════════════════════════════════════════════
int _parseStockValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _availableStockForInventoryItem(Map<String, dynamic> item) {
  final hasStockField = item.containsKey('stock') && item['stock'] != null;
  if (hasStockField) return _parseStockValue(item['stock']);
  return _parseStockValue(item['startingStock']);
}

// Brand Colours (shared)
// ═══════════════════════════════════════════════════════════════════════════

List<String> _inventoryImageUrls(Map<String, dynamic> data) {
  final urls = <String>[];
  final seen = <String>{};
  final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  for (final item in items) {
    final url = item['imageUrl']?.toString().trim() ?? '';
    if (url.isNotEmpty && seen.add(url)) urls.add(url);
  }
  final categoryUrl = data['imageUrl']?.toString().trim() ?? '';
  if (categoryUrl.isNotEmpty && seen.add(categoryUrl)) urls.add(categoryUrl);
  return urls;
}

class _C {
  static const primary = Color(0xFFE91E63);
  static const primaryLight = Color(0xFFF48FB1);
  static const primaryDark = Color(0xFFC2105C);
  static const accent = Color(0xFFFF8C42);
  static const gold = Color(0xFFFFD166);
  static const surface = Color(0xFFFFF8F5);
}

// ═══════════════════════════════════════════════════════════════════════════
// DashboardPage
// ═══════════════════════════════════════════════════════════════════════════

class DashboardPage extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onMessage;
  final VoidCallback? onNotification;
  final void Function({
    required String view,
    required String groupName,
    required String sourceInventoryId,
  })?
  onOpenSalesGroup;

  const DashboardPage({
    super.key,
    required this.scrollController,
    required this.onMessage,
    this.onNotification,
    this.onOpenSalesGroup,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  List inventoryEntries = [];
  String _inventoryView = 'categories';
  List<String> _staffInventoryIds = const [];
  List<_CachedDoc> _cachedStaffInventoryDocs = const [];
  List<_CachedDoc> _cachedSalesInventoryDocs = const [];
  List<_CachedDoc> _cachedCashDrawerDocs = const [];
  String? _staffDocId;
  final Map<String, int> _inventoryPageByView = {
    'categories': 0,
    'bundle': 0,
    'coffee': 0,
  };
  int _performancePage = 0;

  static const int _itemsPerPage = 5;

  @override
  void initState() {
    super.initState();
    _initStaffIdentity();
    _loadLocalDashboardCache();
    InventoryService().addListener(_onInventoryChanged);

    InventoryService().initialize().then((_) {
      if (!mounted) return;
      setState(() {
        inventoryEntries = InventoryService().currentUserEntries;
      });
    });
  }

  Future<void> _loadLocalDashboardCache() async {
    final service = LocalDatabaseSyncService();
    final staffInventory = await service.getCachedCollection('staff_inventory');
    final salesInventory = await service.getCachedCollection('sales_inventory');
    final cashDrawer = await service.getCachedCollection('staff_cash_drawer');
    if (!mounted) return;
    setState(() {
      _cachedStaffInventoryDocs = staffInventory
          .map(_CachedDoc.fromMap)
          .toList();
      _cachedSalesInventoryDocs = salesInventory
          .map(_CachedDoc.fromMap)
          .toList();
      _cachedCashDrawerDocs = cashDrawer.map(_CachedDoc.fromMap).toList();
    });
  }

  Future<void> _initStaffIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final uid =
        FirebaseAuth.instance.currentUser?.uid ??
        prefs.getString('lastStaffDocId') ??
        prefs.getString('lastUserId');
    if ((uid ?? '').isEmpty) return;
    if (mounted) setState(() => _staffDocId = uid);
    _staffInventoryIds = const [];
    await _loadStaffInventoryIds(uid!);
  }

  @override
  void dispose() {
    InventoryService().removeListener(_onInventoryChanged);
    super.dispose();
  }

  void _onInventoryChanged() {
    if (mounted) {
      setState(() => inventoryEntries = InventoryService().currentUserEntries);
    }
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _staffInventoryStream() {
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _receiptStream() {
    final id = _staffDocId?.trim() ?? '';
    final query = FirebaseFirestore.instance.collection('completed_sales');
    if (id.isEmpty) {
      return query.where('userId', isEqualTo: '__missing_staff__').snapshots();
    }
    return query.where('userId', isEqualTo: id).snapshots();
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HistorySheet(
        receiptStream: _receiptStream(),
        localReceiptStream: LocalDatabaseSyncService()
            .watchLocalCompletedSales(),
      ),
    );
  }

  void _openRefundFlow() {
    _showRefundDialog();
  }

  double _parseMoney(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
          value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
        ) ??
        0.0;
  }

  String _refundItemKey(Map<String, dynamic> item) =>
      '${item['name'] ?? ''}|${item['price'] ?? ''}'.toLowerCase();

  List<Map<String, dynamic>> _activeRefundItemsForData(
    Map<String, dynamic> staffData,
    Map<String, dynamic> rootData,
  ) {
    final rootItems = ((rootData['items'] as List<dynamic>?) ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final rootKeys = rootItems.map(_refundItemKey).toSet();
    return ((staffData['items'] as List<dynamic>?) ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
          final expirationDate = item['expirationDate']?.toString() ?? '';
          if (_isExpiredInventoryItem(expirationDate)) return false;
          if (rootKeys.isEmpty) return true;
          return rootKeys.contains(_refundItemKey(item));
        })
        .toList();
  }

  bool _hasExpiredRefundBundleItem(Map<String, dynamic> bundleData) {
    final rawItems = bundleData['items'] as List<dynamic>? ?? [];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (_isExpiredInventoryItem(item['expirationDate']?.toString() ?? '')) {
        return true;
      }
    }
    final instances = bundleData['bundleInstances'];
    if (instances is! List) return false;
    for (final rawInstance in instances.whereType<Map>()) {
      final instance = Map<String, dynamic>.from(rawInstance);
      final items = instance['items'] as List<dynamic>? ?? [];
      for (final raw in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if (_isExpiredInventoryItem(item['expirationDate']?.toString() ?? '')) {
          return true;
        }
      }
    }
    return false;
  }

  int _availableRefundBundleCount(Map<String, dynamic> bundleData) {
    final instances = bundleData['bundleInstances'];
    if (instances is List && instances.isNotEmpty) {
      return instances.whereType<Map>().where((raw) {
        final status =
            raw['status']?.toString().trim().toLowerCase() ?? 'available';
        return status == 'available';
      }).length;
    }
    return _parseStockValue(bundleData['bundleCount']);
  }

  bool _hasRefundBundleContents(Map<String, dynamic> bundleData) {
    final items = bundleData['items'];
    if (items is List && items.whereType<Map>().isNotEmpty) return true;
    final instances = bundleData['bundleInstances'];
    if (instances is List) {
      return instances.whereType<Map>().any((instance) {
        final instanceItems = instance['items'];
        return instanceItems is List &&
            instanceItems.whereType<Map>().isNotEmpty;
      });
    }
    return false;
  }

  List<Map<String, dynamic>> _coffeeRefundOptionsFromData({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, dynamic> data,
    required Map<String, dynamic> rootData,
  }) {
    final sourceId = data['sourceInventoryId']?.toString() ?? doc.id;
    final categoryName = data['name']?.toString() ?? 'Coffee';
    final basePrice = _parseMoney(data['basePrice'] ?? rootData['basePrice']);
    final sizes =
        ((data['sizes'] as List<dynamic>?) ??
                (rootData['sizes'] as List<dynamic>?) ??
                [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .where(
              (entry) => (entry['name']?.toString().trim() ?? '').isNotEmpty,
            )
            .toList();
    final safeSizes = sizes.isEmpty
        ? [
            {'name': 'Regular', 'priceDelta': 0},
          ]
        : sizes;
    final addonByName = <String, Map<String, dynamic>>{};
    for (final source in [data, rootData]) {
      for (final addon
          in (source['addonOptions'] as List<dynamic>? ?? [])
              .whereType<Map>()) {
        final name = addon['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        addonByName.putIfAbsent(name, () => Map<String, dynamic>.from(addon));
      }
    }

    final options = <Map<String, dynamic>>[];
    for (final size in safeSizes) {
      final sizeName = size['name']?.toString() ?? 'Regular';
      final price = basePrice + _parseMoney(size['priceDelta']);
      options.add({
        'source': 'Coffee',
        'docId': doc.id,
        'sourceInventoryId': sourceId,
        'name': categoryName,
        'variant': sizeName,
        'price': price,
        'maxQty': 999,
        'itemId': '$sourceId|size:$sizeName|addon:none',
        'isBundle': false,
        'isCoffee': true,
      });
      for (final addon in addonByName.values) {
        final addonName = addon['name']?.toString().trim() ?? '';
        if (addonName.isEmpty) continue;
        final addonPrice = _parseMoney(addon['priceDelta']);
        options.add({
          'source': 'Coffee',
          'docId': doc.id,
          'sourceInventoryId': sourceId,
          'name': categoryName,
          'variant': '$sizeName + $addonName',
          'price': price + addonPrice,
          'maxQty': 999,
          'itemId':
              '$sourceId|size:$sizeName|addon:${addonName.toLowerCase().replaceAll(' ', '_')}',
          'isBundle': false,
          'isCoffee': true,
        });
      }
    }
    return options;
  }

  Future<List<Map<String, dynamic>>> _loadRefundOptions() async {
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'staff_inventory',
    );
    if (ids.isEmpty) {
      final uid = _staffDocId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      query = query.where('staffId', isEqualTo: uid);
    } else {
      query = ids.length == 1
          ? query.where('staffId', isEqualTo: ids.first)
          : query.where('staffId', whereIn: ids);
    }

    final snapshot = await query.get();
    final rootSnapshot = await FirebaseFirestore.instance
        .collection('sales_inventory')
        .get();
    final activeRootById = <String, Map<String, dynamic>>{};
    final activeRootByName = <String, Map<String, dynamic>>{};
    for (final rootDoc in rootSnapshot.docs) {
      final rootData = rootDoc.data();
      if (rootData['isDeleted'] == true) continue;
      activeRootById[rootDoc.id] = rootData;
      final rootName = rootData['name']?.toString().trim().toLowerCase() ?? '';
      if (rootName.isNotEmpty) activeRootByName[rootName] = rootData;
    }

    final options = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isDeleted'] == true || data['isAddon'] == true) continue;
      final sourceId = data['sourceInventoryId']?.toString() ?? doc.id;
      final categoryName = data['name']?.toString() ?? 'Item';
      final nameKey = categoryName.trim().toLowerCase();
      final isCoffee = data['isCoffee'] == true;
      final rootCandidate = activeRootById[sourceId];
      final rootByName = activeRootByName[nameKey];
      final rootData = data['isBundle'] == true
          ? ((rootCandidate?['isBundle'] == true)
                ? rootCandidate
                : (rootByName?['isBundle'] == true)
                ? rootByName
                : null)
          : isCoffee
          ? ((rootCandidate?['isCoffee'] == true)
                ? rootCandidate
                : (rootByName?['isCoffee'] == true)
                ? rootByName
                : data)
          : ((rootCandidate != null && rootCandidate['isBundle'] != true)
                ? rootCandidate
                : (rootByName != null && rootByName['isBundle'] != true)
                ? rootByName
                : null);
      if (rootData == null) continue;

      if (data['isBundle'] == true) {
        if (rootData['isBundle'] != true) continue;
        if (!_hasRefundBundleContents(data) ||
            !_hasRefundBundleContents(rootData)) {
          continue;
        }
        if (_hasExpiredRefundBundleItem(data)) continue;
        final count = _availableRefundBundleCount(data);
        if (count <= 0) continue;
        options.add({
          'source': 'Bundle',
          'docId': doc.id,
          'sourceInventoryId': sourceId,
          'name': rootData['name'] ?? categoryName,
          'variant': 'Bundle',
          'price': _parseMoney(data['price']),
          'maxQty': count,
          'isBundle': true,
          'isCoffee': false,
        });
        continue;
      }

      if (isCoffee) {
        options.addAll(
          _coffeeRefundOptionsFromData(
            doc: doc,
            data: data,
            rootData: rootData,
          ),
        );
        continue;
      }

      final items = _activeRefundItemsForData(data, rootData);
      for (final item in items) {
        final stock = _availableStockForInventoryItem(item);
        if (stock <= 0) continue;
        options.add({
          'source': 'Categories',
          'docId': doc.id,
          'sourceInventoryId': sourceId,
          'name': rootData['name'] ?? categoryName,
          'variant': item['name']?.toString() ?? 'Item',
          'price': _parseMoney(item['price']),
          'maxQty': stock,
          'itemId': item['id']?.toString() ?? '',
          'isBundle': false,
          'isCoffee': false,
        });
      }
    }
    return options;
  }

  Future<int> _soldQuantityForRefundOption(Map<String, dynamic> option) async {
    final uid = _staffDocId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;
    final query = FirebaseFirestore.instance
        .collection('completed_sales')
        .where('userId', isEqualTo: uid);
    final snapshot = await query.get();
    var soldTotal = 0;
    var refundedTotal = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final items = (data['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item));
      for (final item in items) {
        final sourceInventoryId = item['sourceInventoryId']?.toString() ?? '';
        final variant = item['variant']?.toString() ?? '';
        final name = item['name']?.toString() ?? '';
        final itemId =
            item['itemId']?.toString() ?? item['id']?.toString() ?? '';
        final optionSourceInventoryId =
            option['sourceInventoryId']?.toString() ?? '';
        final optionVariant = option['variant']?.toString() ?? '';
        final optionName = option['name']?.toString() ?? '';
        final optionItemId = option['itemId']?.toString() ?? '';
        final itemIsBundle = item['isBundle'] == true;
        final itemIsCoffee = item['isCoffee'] == true;
        final optionIsBundle = option['isBundle'] == true;
        final optionIsCoffee = option['isCoffee'] == true;

        if (itemIsBundle != optionIsBundle || itemIsCoffee != optionIsCoffee) {
          continue;
        }

        final exactSourceAndVariantMatch =
            optionSourceInventoryId.isNotEmpty &&
            sourceInventoryId == optionSourceInventoryId &&
            variant == optionVariant;
        final sourceAndNameMatch =
            optionSourceInventoryId.isNotEmpty &&
            sourceInventoryId == optionSourceInventoryId &&
            name == optionName;
        final nameAndVariantMatch =
            name == optionName && variant == optionVariant;
        final idMatch =
            optionItemId.isNotEmpty &&
            (itemId == optionItemId ||
                itemId == '$optionSourceInventoryId|$optionItemId');

        if (!(exactSourceAndVariantMatch ||
            sourceAndNameMatch ||
            nameAndVariantMatch ||
            idMatch)) {
          continue;
        }

        final qty = _parseStockValue(item['quantity']);
        final type = data['type']?.toString().toLowerCase() ?? '';
        if (type == 'refund' ||
            data['status']?.toString().toLowerCase() == 'refund') {
          refundedTotal += qty;
        } else {
          soldTotal += qty;
        }
      }
    }

    final netSold = soldTotal - refundedTotal;
    return netSold < 0 ? 0 : netSold;
  }

  Future<void> _saveRefund({
    required Map<String, dynamic> option,
    required int quantity,
    required String reason,
  }) async {
    final uid = _staffDocId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('User not authenticated');
    final drawerId = _staffInventoryIds.isNotEmpty
        ? _staffInventoryIds.first
        : uid;
    final amount = (_parseMoney(option['price']) * quantity).abs();
    final firestore = FirebaseFirestore.instance;
    final salesRef = firestore.collection('completed_sales').doc();
    final drawerRef = firestore.collection('staff_cash_drawer').doc(drawerId);
    final now = DateTime.now();
    final refundId =
        'R-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}-${now.millisecond.toString().padLeft(3, '0')}';
    final currentUser = FirebaseAuth.instance.currentUser;
    final displayName = currentUser?.displayName?.trim() ?? '';
    final staffName = displayName.isNotEmpty
        ? displayName
        : currentUser?.email?.split('@').first ?? 'Staff';
    final itemLabel =
        '${option['name'] ?? 'Item'} (${option['variant'] ?? 'Refund'})';

    await firestore.runTransaction((transaction) async {
      final drawerSnapshot = await transaction.get(drawerRef);
      final currentCash =
          (drawerSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final nextCash = currentCash - amount;
      transaction.set(salesRef, {
        'userId': uid,
        'branchId': drawerId,
        'salesId': refundId,
        'type': 'refund',
        'source': option['source'] ?? 'Refund',
        'reason': reason,
        'subtotal': -amount,
        'discount': 0.0,
        'discountType': 'None',
        'total': -amount,
        'paidAmount': 0.0,
        'change': 0.0,
        'paymentMode': 'Cash',
        'cashDrawerDelta': -amount,
        'cashDrawerBalanceAfter': nextCash,
        'items': [
          {
            'name': option['name'],
            'variant': option['variant'],
            'price': option['price'],
            'quantity': quantity,
            'sourceInventoryId': option['sourceInventoryId'] ?? '',
            'itemId': option['itemId'] ?? '',
            'isBundle': option['isBundle'] == true,
            'isCoffee': option['isCoffee'] == true,
          },
        ],
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'Refund',
      });
      transaction.set(drawerRef, {
        'balance': nextCash,
        'updatedAt': FieldValue.serverTimestamp(),
        'staffId': drawerId,
        'branchId': drawerId,
        'handledByStaffId': uid,
      }, SetOptions(merge: true));
    });

    await firestore.collection('admin_notifications').add({
      'title': 'Refund recorded',
      'message':
          '$staffName refunded $quantity x $itemLabel for ₱${amount.toStringAsFixed(2)}. Cash drawer was deducted.',
      'category': 'Refunds',
      'type': 'refund',
      'salesId': refundId,
      'staffId': uid,
      'staffName': staffName,
      'branchId': drawerId,
      'amount': amount,
      'quantity': quantity,
      'reason': reason,
      'itemName': option['name'] ?? '',
      'variant': option['variant'] ?? '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _showRefundDialog() async {
    final options = await _loadRefundOptions();
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No refundable items found')),
      );
      return;
    }

    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    var source = options.first['source']?.toString() ?? 'Categories';
    var selected = options.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final sourceOptions = options
                .map((item) => item['source']?.toString() ?? 'Categories')
                .toSet()
                .toList();
            final filtered = options
                .where((item) => (item['source']?.toString() ?? '') == source)
                .toList();
            if (!filtered.contains(selected)) selected = filtered.first;
            final maxQty = _parseStockValue(selected['maxQty']);
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 18,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.of(context).size.height * 0.80,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
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
                                color: _C.primaryDark,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                            color: _C.primaryDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: source,
                        decoration: _refundInputDecoration(
                          'Refund source',
                          Icons.compare_arrows_rounded,
                        ),
                        items: sourceOptions
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            source = value;
                            selected = options.firstWhere(
                              (item) => item['source'] == source,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        initialValue: selected,
                        decoration: _refundInputDecoration(
                          '$source item',
                          Icons.category_rounded,
                        ),
                        items: filtered
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  '${item['name']} (${item['variant']})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selected = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<int>(
                        future: _soldQuantityForRefundOption(selected),
                        builder: (context, snapshot) {
                          final soldQty = snapshot.data ?? 0;
                          final maxRefundable = soldQty < maxQty
                              ? soldQty
                              : maxQty;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const Text(
                                  'Checking sold quantity...',
                                  style: TextStyle(
                                    color: _C.primaryDark,
                                    fontSize: 13,
                                  ),
                                )
                              else if (soldQty == 0)
                                const Text(
                                  'No sold quantity found for this item.',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                Text(
                                  'Sold quantity: $soldQty • Refundable: $maxRefundable',
                                  style: const TextStyle(
                                    color: _C.primaryDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      ),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: _refundInputDecoration(
                          'Returned quantity',
                          Icons.undo_rounded,
                        ).copyWith(helperText: 'Enter returned quantity'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _refundInputDecoration(
                          'Reason',
                          Icons.edit_note_rounded,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final qty = _parseStockValue(qtyController.text);
                          final reason = reasonController.text.trim();
                          final soldQty = await _soldQuantityForRefundOption(
                            selected,
                          );
                          final maxRefundable = soldQty < maxQty
                              ? soldQty
                              : maxQty;
                          if (soldQty == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cannot refund this item until it has been sold.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (qty <= 0 || qty > maxRefundable) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Enter quantity from 1 to $maxRefundable',
                                ),
                              ),
                            );
                            return;
                          }
                          if (reason.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter refund reason'),
                              ),
                            );
                            return;
                          }
                          try {
                            await _saveRefund(
                              option: selected,
                              quantity: qty,
                              reason: reason,
                            );
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Refund recorded')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Refund failed: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.assignment_return_rounded),
                        label: const Text('Confirm Refund'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _C.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
      prefixIcon: Icon(icon, color: _C.primary),
      filled: true,
      fillColor: const Color(0xFFFFF3F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFF8BBD0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFF8BBD0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _C.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 700;
    final contentMaxWidth = isTablet ? 980.0 : double.infinity;
    final inventoryMaxWidth = isTablet ? 980.0 : double.infinity;
    final horizontalPadding = isTablet ? 24.0 : 16.0;
    final headerHeight = isTablet ? 260.0 : 300.0;

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        // ── Header ────────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: headerHeight,
          collapsedHeight: 60,
          pinned: true,
          elevation: 0,
          backgroundColor: _C.primary,
          foregroundColor: Colors.white,
          centerTitle: false,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _Header(
              onMessage: widget.onMessage,
              onNotification: widget.onNotification,
              drawerIds: _staffInventoryIds,
              staffDocId: _staffDocId,
            ),
          ),
        ),

        // ── "Dashboard" label ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            color: _C.surface,
            padding: EdgeInsets.fromLTRB(
              isTablet ? 24 : 20,
              isTablet ? 10 : 14,
              isTablet ? 24 : 20,
              8,
            ),
            child: Align(
              alignment: isTablet ? Alignment.centerLeft : Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isTablet)
                      Row(
                        children: [
                          const _SectionLabel(title: 'Dashboard'),
                          const Spacer(),
                          SizedBox(
                            width: 280,
                            child: _buildViewAllItemsButton(),
                          ),
                        ],
                      )
                    else ...[
                      const Align(
                        alignment: Alignment.center,
                        child: _SectionLabel(title: 'Dashboard'),
                      ),
                      const SizedBox(height: 10),
                      _buildViewAllItemsButton(),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: isTablet
                          ? Alignment.centerLeft
                          : Alignment.center,
                      child: _InventoryViewSelector(
                        selected: _inventoryView,
                        onSelected: (value) => setState(() {
                          _inventoryView = value;
                          _inventoryPageByView[value] = 0;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Inventory list ────────────────────────────────────────────────
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: inventoryMaxWidth),
                child: _buildAdminInventoryList(),
              ),
            ),
          ),
        ),

        // ── "Performance" label + History ─────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            color: _C.surface,
            padding: EdgeInsets.fromLTRB(
              isTablet ? 24 : 20,
              isTablet ? 10 : 12,
              isTablet ? 24 : 20,
              10,
            ),
            child: Align(
              alignment: isTablet ? Alignment.centerLeft : Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  crossAxisAlignment: isTablet
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    const _SectionLabel(title: 'Performance'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [_HistoryButton(onTap: _showHistory)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Performance cards ─────────────────────────────────────────────
        SliverSafeArea(
          top: false,
          bottom: true,
          sliver: SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              18,
            ),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: _buildPerformanceData(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Admin inventory list ──────────────────────────────────────────────────
  Widget _buildAdminInventoryList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _staffInventoryStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorCard(message: 'Error loading inventory');
        }
        if (snapshot.hasData) {
          unawaited(
            LocalDatabaseSyncService().cacheCollectionDocs(
              'staff_inventory',
              snapshot.data!.docs.map((doc) {
                final data = doc.data();
                return {...data, '_localDocId': doc.id};
              }),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cachedStaffInventoryDocs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _C.primaryLight),
            ),
          );
        }

        final docs =
            snapshot.data?.docs.map(_CachedDoc.fromFirestore).toList() ??
            _cachedStaffInventoryDocs;
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.inventory_2_outlined,
            label: 'No inventory items found.',
          );
        }

        // ── Filter out sales transactions (status='completed') to show only inventory ──────────────────
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('sales_inventory')
              .snapshots(),
          builder: (context, rootSnapshot) {
            if (rootSnapshot.hasData) {
              unawaited(
                LocalDatabaseSyncService().cacheCollectionDocs(
                  'sales_inventory',
                  rootSnapshot.data!.docs.map((doc) {
                    final data = doc.data();
                    return {...data, '_localDocId': doc.id};
                  }),
                ),
              );
            }
            if (rootSnapshot.connectionState == ConnectionState.waiting &&
                _cachedSalesInventoryDocs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: _C.primaryLight),
                ),
              );
            }
            final activeRootById = <String, Map<String, dynamic>>{};
            final activeRootByName = <String, Map<String, dynamic>>{};
            final rootDocs =
                rootSnapshot.data?.docs
                    .map(_CachedDoc.fromFirestore)
                    .toList() ??
                _cachedSalesInventoryDocs;
            for (final rootDoc in rootDocs) {
              final rootData = rootDoc.data();
              if (rootData['isDeleted'] == true) continue;
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

            List<Map<String, dynamic>> activeStaffItems(
              Map<String, dynamic> staffData,
              Map<String, dynamic> rootData,
            ) {
              final rootKeys = ((rootData['items'] as List<dynamic>?) ?? [])
                  .whereType<Map>()
                  .map((item) => itemKey(Map<String, dynamic>.from(item)))
                  .toSet();
              return ((staffData['items'] as List<dynamic>?) ?? [])
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .where((item) {
                    final expirationDate =
                        item['expirationDate']?.toString() ?? '';
                    return !_isExpiredInventoryItem(expirationDate) &&
                        (rootKeys.isEmpty || rootKeys.contains(itemKey(item)));
                  })
                  .toList();
            }

            final inventoryDocs = <Map<String, dynamic>>[];
            for (final doc in docs) {
              final data = doc.data();
              if (data['isDeleted'] == true ||
                  data['status'] == 'completed' ||
                  data['salesId'] != null) {
                continue;
              }

              final sourceId = data['sourceInventoryId']?.toString() ?? '';
              final name = data['name']?.toString().trim().toLowerCase() ?? '';
              final isCoffee = data['isCoffee'] == true;
              final rootCandidate = activeRootById[sourceId];
              final bundleNameRoot = activeRootByName[name];
              final rootData = isCoffee
                  ? data
                  : data['isBundle'] == true
                  ? ((rootCandidate?['isBundle'] == true)
                        ? rootCandidate
                        : (bundleNameRoot?['isBundle'] == true)
                        ? bundleNameRoot
                        : null)
                  : (rootCandidate ?? activeRootByName[name]);
              if (rootData == null) continue;
              if (data['isBundle'] == true) {
                if (rootData['isBundle'] != true) continue;
                if (_hasExpiredRefundBundleItem(rootData)) continue;
                if (_hasExpiredRefundBundleItem(data)) continue;
                if (_availableRefundBundleCount(data) <= 0) continue;
              }

              final items = isCoffee
                  ? [
                      {
                        'name': data['name'] ?? 'Coffee',
                        'price': data['basePrice'] ?? 0,
                        'stock': 999,
                        'startingStock': 999,
                        'isCoffee': true,
                      },
                    ]
                  : data['isBundle'] == true
                  ? (data['items'] as List<dynamic>? ?? [])
                  : activeStaffItems(data, rootData);
              if (!isCoffee && data['isBundle'] != true && items.isEmpty) {
                continue;
              }

              inventoryDocs.add({
                ...data,
                'staffDocId': doc.id,
                'sourceInventoryId': sourceId,
                'name': rootData['name'] ?? data['name'],
                'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                'items': items,
                'isCoffee': isCoffee,
              });
            }

            if (inventoryDocs.isEmpty) {
              return const _EmptyState(
                icon: Icons.inventory_2_outlined,
                label: 'No inventory items found.',
              );
            }

            // ── Group documents by name to eliminate duplicates ──────────────────
            final Map<String, Map<String, dynamic>> uniqueItems = {};
            for (final data in inventoryDocs) {
              final name = (data['name']?.toString() ?? '').toLowerCase();
              final sourceId =
                  (data['sourceInventoryId']?.toString().trim().isNotEmpty ==
                      true)
                  ? data['sourceInventoryId'].toString()
                  : (data['staffDocId']?.toString() ?? name);
              final uniqueKey = data['isCoffee'] == true
                  ? 'coffee:$sourceId'
                  : data['isBundle'] == true
                  ? 'bundle:$sourceId'
                  : 'category:$sourceId';
              final items =
                  (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

              // Keep only active variants and ignore categories with none
              final activeVariants = items.where((item) {
                final expirationDate = item['expirationDate']?.toString() ?? '';
                return !_isExpiredInventoryItem(expirationDate);
              }).toList();

              if (activeVariants.isEmpty && data['isCoffee'] != true) continue;

              // Keep source inventory IDs separate even when categories share a name.
              if (!uniqueItems.containsKey(uniqueKey)) {
                uniqueItems[uniqueKey] = data;
              }
            }

            final sortedDocs = uniqueItems.values.toList();
            sortedDocs.sort((a, b) {
              final nameA = (a['name']?.toString() ?? '').toLowerCase();
              final nameB = (b['name']?.toString() ?? '').toLowerCase();
              return nameA.compareTo(nameB);
            });

            final filteredDocs = sortedDocs.where((data) {
              final isBundle = data['isBundle'] == true;
              final isCoffee = data['isCoffee'] == true;
              if (_inventoryView == 'bundle') return isBundle;
              if (_inventoryView == 'coffee') return isCoffee;
              return !isBundle && !isCoffee;
            }).toList();

            final pageCount = (filteredDocs.length / _itemsPerPage).ceil();
            final currentPage = (_inventoryPageByView[_inventoryView] ?? 0)
                .clamp(0, pageCount > 0 ? pageCount - 1 : 0)
                .toInt();
            final startIndex = currentPage * _itemsPerPage;
            final visibleDocs = filteredDocs
                .skip(startIndex)
                .take(_itemsPerPage)
                .toList();

            return Column(
              children: [
                if (filteredDocs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _EmptyState(
                      icon: _inventoryView == 'categories'
                          ? Icons.category_rounded
                          : Icons.inventory_2_rounded,
                      label: _inventoryView == 'bundle'
                          ? 'No bundles found.'
                          : _inventoryView == 'coffee'
                          ? 'No coffee items found.'
                          : 'No category items found.',
                    ),
                  )
                else
                  ...visibleDocs.map((data) {
                    final name = data['name']?.toString().trim() ?? '';
                    final rawSourceId =
                        data['sourceInventoryId']?.toString().trim() ?? '';
                    final sourceId = rawSourceId.isNotEmpty
                        ? rawSourceId
                        : data['staffDocId']?.toString().trim() ?? '';

                    // Skip if name is empty or it's "Unnamed Item"
                    if (name.isEmpty) return const SizedBox.shrink();

                    final isBundle = data['isBundle'] == true;
                    final items =
                        (data['items'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final imageUrls = _inventoryImageUrls(data);
                    final availableStock = isBundle
                        ? (data['bundleCount'] is num
                              ? (data['bundleCount'] as num).toInt()
                              : int.tryParse(
                                      data['bundleCount']?.toString() ?? '',
                                    ) ??
                                    0)
                        : items.fold<int>(0, (sum, item) {
                            if (_isExpiredInventoryItem(
                              item['expirationDate']?.toString() ?? '',
                            )) {
                              return sum;
                            }
                            final itemStock = _availableStockForInventoryItem(
                              item,
                            );
                            return sum + (itemStock > 0 ? itemStock : 0);
                          });
                    final isLocked = availableStock <= 0;

                    // Derive a friendly category label
                    final nameLower = name.toLowerCase();
                    final coffeeId = data['coffeeId']?.toString().trim() ?? '';
                    String category = 'Cupcakes';
                    if (data['isCoffee'] == true) {
                      category = coffeeId.isNotEmpty
                          ? 'Coffee - $coffeeId'
                          : 'Coffee';
                    } else if (nameLower.contains('cupcake') ||
                        nameLower.contains('cupcakes')) {
                      category = 'Cupcakes Set';
                    } else if (nameLower.contains('cake')) {
                      category = 'Cakes';
                    } else if (nameLower.contains('drink') ||
                        nameLower.contains('juice')) {
                      category = 'Beverages';
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ItemCard(
                        itemName: name,
                        category: category,
                        imageAsset: imageUrls.isNotEmpty
                            ? imageUrls.first
                            : 'Assets/Image/T.jpg',
                        imageAssets: imageUrls,
                        isLocked: isLocked,
                        onTap: () {
                          if (isLocked) {
                            _showLockedDialog();
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AllCategPage(
                                selectedCategoryName: name,
                                selectedSourceInventoryId: sourceId,
                                selectedIsBundle: data['isBundle'] == true,
                                selectedIsCoffee: data['isCoffee'] == true,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                if (pageCount > 1)
                  _PagerControls(
                    currentPage: currentPage,
                    pageCount: pageCount,
                    onPrevious: currentPage == 0
                        ? null
                        : () => setState(
                            () => _inventoryPageByView[_inventoryView] =
                                currentPage - 1,
                          ),
                    onNext: currentPage >= pageCount - 1
                        ? null
                        : () => setState(
                            () => _inventoryPageByView[_inventoryView] =
                                currentPage + 1,
                          ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildViewAllItemsButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AllCategPage()),
          );
        },
        icon: const Icon(Icons.view_list_rounded, color: _C.primaryDark),
        label: const Text(
          'View All Items',
          style: TextStyle(color: _C.primaryDark, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _C.primaryDark),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  void _showLockedDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF0E8), Color(0xFFFFE4CC)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: _C.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Item Unavailable',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _C.primaryDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFFFFF5EE),
                  border: Border.all(color: const Color(0xFFE8C5B0)),
                ),
                child: const Text(
                  'This item has no available stock. Staff cannot open unavailable items. Please contact admin.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFE91E63),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Got it',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Contact Admin',
                    style: TextStyle(
                      color: _C.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Performance data ───────────────────────────────────────────────────────
  Widget _buildPerformanceData() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: LocalDatabaseSyncService().watchLocalCompletedSales(),
      builder: (context, localSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _receiptStream(),
          builder: (context, snapshot) {
            final localSales = localSnapshot.data ?? const [];
            final firestoreSales = (snapshot.data?.docs ?? [])
                .map((doc) => doc.data())
                .toList();
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final tomorrow = today.add(const Duration(days: 1));
            final staffId = _staffDocId?.trim() ?? '';
            final bySalesId = <String, Map<String, dynamic>>{};

            bool isVisibleReceipt(Map<String, dynamic> data) {
              final timestamp = data['timestamp'];
              if (timestamp is! Timestamp) return false;
              final userId = data['userId']?.toString() ?? '';
              if (staffId.isNotEmpty && userId != staffId) return false;
              final dt = timestamp.toDate();
              final status = data['status']?.toString().toLowerCase() ?? '';
              final type = data['type']?.toString().toLowerCase() ?? '';
              return !dt.isBefore(today) &&
                  dt.isBefore(tomorrow) &&
                  status != 'refund' &&
                  type != 'refund';
            }

            for (final data in [...localSales, ...firestoreSales]) {
              if (!isVisibleReceipt(data)) continue;
              final salesId = data['salesId']?.toString() ?? '';
              final key = salesId.isNotEmpty
                  ? salesId
                  : 'local-${data['localId'] ?? bySalesId.length}';
              bySalesId[key] = data;
            }

            final receipts = bySalesId.values.toList()
              ..sort((a, b) {
                final at = a['timestamp'] as Timestamp?;
                final bt = b['timestamp'] as Timestamp?;
                return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                  at?.millisecondsSinceEpoch ?? 0,
                );
              });

            if (receipts.isEmpty &&
                snapshot.connectionState == ConnectionState.waiting &&
                localSnapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: CircularProgressIndicator(color: _C.primary),
                ),
              );
            }

            if (receipts.isEmpty) {
              return const _EmptyState(
                icon: Icons.receipt_long_rounded,
                label: 'No receipts today.',
                sublabel: 'Confirmed orders will appear here.',
              );
            }

            final pageCount = (receipts.length / _itemsPerPage).ceil();
            final currentPage = _performancePage
                .clamp(0, pageCount > 0 ? pageCount - 1 : 0)
                .toInt();
            final visibleReceipts = receipts
                .skip(currentPage * _itemsPerPage)
                .take(_itemsPerPage)
                .toList();

            return Column(
              children: [
                ...visibleReceipts.map(
                  (data) => _ReceiptCard(data: data, compact: false),
                ),
                if (pageCount > 1)
                  _PagerControls(
                    currentPage: currentPage,
                    pageCount: pageCount,
                    onPrevious: currentPage == 0
                        ? null
                        : () => setState(
                            () => _performancePage = currentPage - 1,
                          ),
                    onNext: currentPage >= pageCount - 1
                        ? null
                        : () => setState(
                            () => _performancePage = currentPage + 1,
                          ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Label
// ═══════════════════════════════════════════════════════════════════════════

class _PagerControls extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PagerControls({
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            color: _C.primaryDark,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withOpacity(0.55),
              fixedSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFF8BBD0)),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF8BBD0)),
            ),
            child: Text(
              '${currentPage + 1} / $pageCount',
              style: const TextStyle(
                color: _C.primaryDark,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            color: _C.primaryDark,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withOpacity(0.55),
              fixedSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFF8BBD0)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryViewSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _InventoryViewSelector({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      ('categories', Icons.category_outlined, 'Categories'),
      ('bundle', Icons.inventory_2_outlined, 'Bundle'),
      ('coffee', Icons.coffee_outlined, 'Coffee'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((option) {
          final isSelected = selected == option.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              selected: isSelected,
              avatar: Icon(
                option.$2,
                size: 18,
                color: isSelected ? Colors.white : _C.primaryDark,
              ),
              label: Text(option.$3),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : _C.primaryDark,
                fontWeight: FontWeight.w800,
              ),
              selectedColor: _C.primary,
              backgroundColor: Colors.white,
              side: const BorderSide(color: _C.primaryDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onSelected: (_) => onSelected(option.$1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_C.accent, Color(0xFFFF5722)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _C.primaryDark,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Button
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_C.primaryLight, _C.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _C.primary.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.history_rounded, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              'History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RefundButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE65100).withOpacity(0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_return_rounded,
              color: Color(0xFFE65100),
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'Refund',
              style: TextStyle(
                color: Color(0xFFE65100),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool compact;
  const _ReceiptCard({required this.data, this.compact = false});

  double _money(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _qty(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final salesId = data['salesId']?.toString() ?? 'Receipt';
    final timestamp = data['timestamp'] is Timestamp
        ? (data['timestamp'] as Timestamp).toDate()
        : DateTime.now();
    final paymentMode = data['paymentMode']?.toString() ?? 'Cash';
    final gcashId = data['gcashTransactionId']?.toString().trim() ?? '';
    final type = data['type']?.toString().toLowerCase() ?? '';
    final status = data['status']?.toString().toLowerCase() ?? '';
    final isRefund = type == 'refund' || status == 'refund';
    final total = _money(data['total']);
    final paid = _money(data['paidAmount']);
    final change = _money(data['change']);
    final items = (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      salesId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isRefund) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'REFUND',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _formatDateTime(timestamp),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ...items.map((item) {
                    final name = item['variant']?.toString().isNotEmpty == true
                        ? '${item['name']} (${item['variant']})'
                        : item['name']?.toString() ?? 'Item';
                    final itemKind = item['isBundle'] == true
                        ? 'Bundle'
                        : item['isCoffee'] == true
                        ? 'Coffee'
                        : '';
                    final displayName = itemKind.isNotEmpty
                        ? '$name • $itemKind'
                        : name;
                    final qty = _qty(item['quantity']);
                    final price = _money(item['price']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${qty}x $displayName',
                              style: const TextStyle(
                                color: _C.primaryDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '₱${(price * qty).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: _C.primaryDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 18),
                  _ReceiptLine(
                    'Mode of Payment',
                    paymentMode == 'GCash' && gcashId.isNotEmpty
                        ? 'GCash - $gcashId'
                        : paymentMode,
                  ),
                  if (!compact)
                    _ReceiptLine(
                      'Customer Paid',
                      '₱${paid.toStringAsFixed(2)}',
                    ),
                  if (!compact)
                    _ReceiptLine('Change', '₱${change.toStringAsFixed(2)}'),
                  _ReceiptLine(
                    'Total',
                    '₱${total.toStringAsFixed(2)}',
                    strong: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _ReceiptLine(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.pink.shade400,
                fontSize: strong ? 14 : 12,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: strong ? Colors.green.shade700 : _C.primaryDark,
              fontSize: strong ? 16 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER WIDGET  (upgraded — keeps all existing pictures)
// ═══════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final VoidCallback onMessage;
  final VoidCallback? onNotification;
  final List<String> drawerIds;
  final String? staffDocId;
  const _Header({
    required this.onMessage,
    this.onNotification,
    required this.drawerIds,
    this.staffDocId,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _cashDrawerStream() {
    final ids = drawerIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    final query = FirebaseFirestore.instance.collection('staff_cash_drawer');
    if (ids.isEmpty) {
      return query
          .where(FieldPath.documentId, isEqualTo: '__missing_drawer__')
          .snapshots();
    }
    return ids.length == 1
        ? query.where(FieldPath.documentId, isEqualTo: ids.first).snapshots()
        : query.where(FieldPath.documentId, whereIn: ids).snapshots();
  }

  String _chatId(String meId, String otherId) {
    final ids = [meId, otherId]..sort();
    return ids.join('_');
  }

  static String _displayName(Map<String, dynamic> data) {
    final first = data['firstName']?.toString().trim() ?? '';
    final last = data['lastName']?.toString().trim() ?? '';
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? (data['name']?.toString() ?? 'User') : full;
  }

  static bool _isOnline(Map<String, dynamic> data) {
    if (data['isOnline'] == true) return true;
    final lastLogin = data['lastLoginAt'];
    if (lastLogin is! Timestamp) return false;
    return DateTime.now().difference(lastLogin.toDate()) <
        const Duration(minutes: 15);
  }

  void _openFullMessages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MessagePage()),
    );
  }

  void _openThread(
    BuildContext context, {
    required Map<String, String> me,
    required String otherId,
    required String otherName,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatThreadPage(
          chatId: _chatId(me['id']!, otherId),
          me: me,
          otherId: otherId,
          otherName: otherName,
        ),
      ),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuideSheet(),
    );
  }

  void _showMessagePreview(BuildContext context, Map<String, String> me) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.56,
          child: Container(
            decoration: const BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SafeArea(
              top: false,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('staff_requests')
                    .snapshots(),
                builder: (context, accountSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('messages')
                        .where('participantIds', arrayContains: me['id'])
                        .snapshots(),
                    builder: (context, chatSnapshot) {
                      final rows = <String, Map<String, dynamic>>{};
                      if (me['role'] != 'admin') {
                        rows['ADM-0001'] = {
                          'id': 'ADM-0001',
                          'name': 'Admin User',
                          'role': 'admin',
                          'online': true,
                          'unread': 0,
                          'lastMessage': '',
                          'updatedAt': 0,
                        };
                      }

                      for (final doc
                          in accountSnapshot.data?.docs ??
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                        final data = doc.data();
                        final status =
                            data['status']?.toString().toLowerCase() ?? '';
                        if (doc.id == me['id'] || status == 'rejected') {
                          continue;
                        }
                        rows[doc.id] = {
                          'id': doc.id,
                          'name': _displayName(data),
                          'role': data['role']?.toString() ?? 'staff',
                          'online': _isOnline(data),
                          'unread': 0,
                          'lastMessage': '',
                          'updatedAt': 0,
                        };
                      }

                      for (final doc
                          in chatSnapshot.data?.docs ??
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                        final chat = doc.data();
                        final ids = (chat['participantIds'] as List? ?? [])
                            .map((id) => id.toString())
                            .toList();
                        final otherId = ids.firstWhere(
                          (id) => id != me['id'],
                          orElse: () => '',
                        );
                        if (otherId.isEmpty) continue;
                        final names = chat['participantNames'];
                        final unreadBy = chat['unreadBy'];
                        final updatedAt = chat['updatedAt'];
                        final unread = unreadBy is Map
                            ? _parseStockValue(unreadBy[me['id']])
                            : 0;
                        rows[otherId] = {
                          ...?rows[otherId],
                          'id': otherId,
                          'name': names is Map
                              ? names[otherId]?.toString() ?? 'Admin User'
                              : rows[otherId]?['name'] ?? 'Admin User',
                          'role':
                              rows[otherId]?['role'] ??
                              (otherId.startsWith('ADM-') ? 'admin' : 'staff'),
                          'online': rows[otherId]?['online'] ?? false,
                          'unread': unread,
                          'lastMessage': chat['lastMessage']?.toString() ?? '',
                          'updatedAt': updatedAt is Timestamp
                              ? updatedAt.millisecondsSinceEpoch
                              : 0,
                        };
                      }

                      final items = rows.values.toList()
                        ..sort((a, b) {
                          final timeCompare = (b['updatedAt'] as int).compareTo(
                            a['updatedAt'] as int,
                          );
                          if (timeCompare != 0) return timeCompare;
                          final unreadCompare = (b['unread'] as int).compareTo(
                            a['unread'] as int,
                          );
                          if (unreadCompare != 0) return unreadCompare;
                          return (a['name']?.toString() ?? '').compareTo(
                            b['name']?.toString() ?? '',
                          );
                        });
                      final preview = items.take(5).toList();

                      return Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 10, bottom: 8),
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _C.primaryLight.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 14, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _C.primary.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: const Icon(
                                    Icons.mail_outline_rounded,
                                    color: _C.primaryDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Messages',
                                    style: TextStyle(
                                      color: _C.primaryDark,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(Icons.close_rounded),
                                  color: _C.primary,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: preview.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No people available.',
                                      style: TextStyle(
                                        color: _C.primaryDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      2,
                                      20,
                                      10,
                                    ),
                                    itemCount: preview.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final row = preview[index];
                                      return _MessagePreviewTile(
                                        name: row['name']?.toString() ?? 'User',
                                        role:
                                            row['role']?.toString() ?? 'staff',
                                        lastMessage:
                                            row['lastMessage']?.toString() ??
                                            '',
                                        online: row['online'] == true,
                                        unread: row['unread'] as int? ?? 0,
                                        onTap: () {
                                          Navigator.pop(sheetContext);
                                          _openThread(
                                            context,
                                            me: me,
                                            otherId:
                                                row['id']?.toString() ?? '',
                                            otherName:
                                                row['name']?.toString() ??
                                                'User',
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _openFullMessages(context);
                                },
                                icon: const Icon(Icons.forum_rounded),
                                label: const Text('View all messages'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _C.primaryDark,
                                  side: const BorderSide(
                                    color: _C.primaryLight,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? staffDocId;

    return StreamBuilder<DocumentSnapshot>(
      stream: uid == null || uid.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance
                .collection('staff_requests')
                .doc(uid)
                .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final firstName = data['firstName']?.toString().trim();
        final lastName = data['lastName']?.toString().trim();
        final name =
            ((firstName?.isNotEmpty ?? false) ||
                (lastName?.isNotEmpty ?? false))
            ? '${firstName ?? ''} ${lastName ?? ''}'.trim()
            : data['name']?.toString().trim() ?? 'Staff Name';
        final staffId = data['staffId']?.toString().trim() ?? '#0000';
        final role = data['role']?.toString().trim() ?? 'Staff Member';
        final photoUrl =
            data['photoUrl']?.toString() ?? data['profileImageUrl']?.toString();

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image (unchanged — your existing asset) ────────
            Image.asset(
              'Assets/Image/Bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: _C.primaryDark),
            ),

            // ── Rich layered overlay ──────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromARGB(221, 75, 0, 40),
                    Color.fromARGB(185, 255, 152, 217),
                    Color.fromARGB(235, 116, 1, 64),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),

            // ── Subtle diagonal stripe texture ────────────────────────────
            Opacity(
              opacity: 0.05,
              child: CustomPaint(
                painter: _StripePainter(),
                size: Size.infinite,
              ),
            ),

            // ── Decorative bottom arc ─────────────────────────────────────
            Positioned(
              bottom: -1,
              left: 0,
              right: 0,
              child: CustomPaint(
                painter: _ArcPainter(),
                child: const SizedBox(height: 15),
              ),
            ),

            // ── Main content ──────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top bar ─────────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo (unchanged picture, upgraded frame)
                        _LogoFrame(),

                        const SizedBox(width: 14),

                        // Brand name + tagline
                        Expanded(child: _BrandTitle()),

                        // Notification + Message buttons
                        Row(
                          children: [
                            _HelpButton(onTap: () => _showHelpSheet(context)),
                            const SizedBox(width: 8),
                            if ((uid ?? '').isEmpty)
                              _MessageButton(onTap: onMessage)
                            else
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: FirebaseFirestore.instance
                                    .collection('messages')
                                    .where('participantIds', arrayContains: uid)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  var unread = 0;
                                  for (final doc
                                      in snapshot.data?.docs ??
                                          <
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >[]) {
                                    final unreadBy = doc.data()['unreadBy'];
                                    if (unreadBy is Map) {
                                      final value = unreadBy[uid];
                                      unread += value is num
                                          ? value.toInt()
                                          : int.tryParse(
                                                  value?.toString() ?? '',
                                                ) ??
                                                0;
                                    }
                                  }
                                  final me = {
                                    'id': uid!,
                                    'name': name,
                                    'role': role.toLowerCase(),
                                  };
                                  return _MessageButton(
                                    onTap: () =>
                                        _showMessagePreview(context, me),
                                    badgeCount: unread,
                                  );
                                },
                              ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),

                    // ── Staff Profile Card ───────────────────────────────
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _cashDrawerStream(),
                      builder: (context, cashDrawerSnapshot) {
                        final cashDrawerBalance =
                            cashDrawerSnapshot.data?.docs.fold<double>(0.0, (
                              sum,
                              doc,
                            ) {
                              final data = doc.data();
                              Future.microtask(
                                () => CashDrawerService.zeroIfPast24Hours(
                                  doc.id,
                                  data,
                                ),
                              );
                              return sum +
                                  ((data['balance'] as num?)?.toDouble() ??
                                      0.0);
                            }) ??
                            0.0;
                        final gcashDrawerBalance =
                            cashDrawerSnapshot.data?.docs.fold<double>(
                              0.0,
                              (sum, doc) =>
                                  sum +
                                  ((doc.data()['gcashBalance'] as num?)
                                          ?.toDouble() ??
                                      0.0),
                            ) ??
                            0.0;
                        return _StaffProfileCard(
                          name: name,
                          staffId: staffId,
                          role: role,
                          photoUrl: photoUrl,
                          cashDrawerBalance: cashDrawerBalance,
                          gcashDrawerBalance: gcashDrawerBalance,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Logo frame ───────────────────────────────────────────────────────────────
class _LogoFrame extends StatelessWidget {
  const _LogoFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD166), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _C.accent.withOpacity(0.55),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipOval(
        child: Image.asset(
          'Assets/Image/ob.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: _C.primaryLight,
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Brand title ───────────────────────────────────────────────────────────────
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFFD166), Color(0xFFFF8C42)],
          ).createShader(bounds),
          child: const Text(
            "Angel Bite'z",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _C.accent,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Cupcakes',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFFFD8B5),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Message button ────────────────────────────────────────────────────────────
class _NotificationButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.notifications_none_rounded,
          color: Colors.white,
          size: 19,
        ),
      ),
    );
  }
}

// ── Message button ────────────────────────────────────────────────────────────
class _MessageButton extends StatelessWidget {
  final VoidCallback onTap;
  final int badgeCount;
  const _MessageButton({required this.onTap, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.28),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.mail_outline_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAFF PROFILE CARD  ← KEY UPGRADE
// ═══════════════════════════════════════════════════════════════════════════

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HelpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.help_outline_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet();

  @override
  Widget build(BuildContext context) {
    final guides = const [
      (
        Icons.inventory_2_rounded,
        'Assigned inventory',
        'Check Categories, Bundles, and Coffee. Only allocated and available items should appear.',
      ),
      (
        Icons.point_of_sale_rounded,
        'Selling items',
        'Tap an available item, select quantity, then confirm the order. Stock decreases after checkout.',
      ),
      (
        Icons.assignment_return_rounded,
        'Refunds',
        'Refund only items that were already sold. Returned quantity cannot exceed refundable quantity.',
      ),
      (
        Icons.history_rounded,
        'Sales history',
        'Use the History button to review today or previous receipt records by payment type.',
      ),
      (
        Icons.mail_outline_rounded,
        'Messages',
        'Open Messages to contact admin or another staff account about stock, refunds, or requests.',
      ),
    ];

    return FractionallySizedBox(
      heightFactor: 0.62,
      child: Container(
        decoration: const BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: _C.primaryLight.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_C.primary, _C.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.help_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Guide',
                            style: TextStyle(
                              color: _C.primaryDark,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'For first-time staff users',
                            style: TextStyle(
                              color: _C.primaryLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: _C.primary,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                  itemCount: guides.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final guide = guides[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _C.primaryLight.withOpacity(0.22),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _C.primary.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _C.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(guide.$1, color: _C.primaryDark),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  guide.$2,
                                  style: const TextStyle(
                                    color: _C.primaryDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  guide.$3,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}

class _MessagePreviewTile extends StatelessWidget {
  final String name;
  final String role;
  final String lastMessage;
  final bool online;
  final int unread;
  final VoidCallback onTap;

  const _MessagePreviewTile({
    required this.name,
    required this.role,
    required this.lastMessage,
    required this.online,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _C.primaryLight.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _C.primary.withOpacity(0.10),
                    child: Text(
                      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: _C.primaryDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: online ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _C.primaryDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lastMessage.isNotEmpty
                          ? lastMessage
                          : '${role.toUpperCase()} - ${online ? 'Online' : 'Offline'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              unread > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: const BoxDecoration(
                        color: _C.primary,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    )
                  : const Icon(Icons.chevron_right_rounded, color: _C.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffProfileCard extends StatefulWidget {
  final String name;
  final String staffId;
  final String role;
  final String? photoUrl;
  final double cashDrawerBalance;
  final double gcashDrawerBalance;

  const _StaffProfileCard({
    required this.name,
    required this.staffId,
    required this.role,
    this.photoUrl,
    required this.cashDrawerBalance,
    required this.gcashDrawerBalance,
  });

  @override
  State<_StaffProfileCard> createState() => _StaffProfileCardState();
}

class _StaffProfileCardState extends State<_StaffProfileCard> {
  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final staffId = widget.staffId;
    final role = widget.role;
    final photoUrl = widget.photoUrl;
    final cashDrawerBalance = widget.cashDrawerBalance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.11),
            border: Border.all(
              color: Colors.white.withOpacity(0.20),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _StaffAvatar(photoUrl: photoUrl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoleBadge(role: role),
                              const SizedBox(height: 6),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                  height: 1.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StaffIdChip(staffId: staffId),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cash Drawer',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₱${cashDrawerBalance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    // ── Avatar (picture unchanged, frame upgraded) ───────────────
                    _StaffAvatar(photoUrl: photoUrl),

                    const SizedBox(width: 16),

                    // ── Staff info ───────────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Role / Title badge
                          _RoleBadge(role: role),

                          const SizedBox(height: 7),

                          // Staff name  ← UPGRADED
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.4,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 8),

                          // Staff ID chip  ← UPGRADED
                          _StaffIdChip(staffId: staffId),
                        ],
                      ),
                    ),

                    Container(
                      width: 136,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Cash Drawer',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '₱${cashDrawerBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
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
  }
}

// ── Staff avatar ──────────────────────────────────────────────────────────────

class _StaffAvatar extends StatelessWidget {
  final String? photoUrl;
  const _StaffAvatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Gold gradient ring
        Container(
          width: 74,
          height: 74,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFFD166), Color(0xFFFF8C42)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x77FF8C42),
                blurRadius: 18,
                spreadRadius: 3,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClipOval(child: _buildPhoto()),
        ),
        // Online status dot
        Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: const Color(0xFF43A047),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(color: Colors.green.withOpacity(0.55), blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoto() {
    final url = photoUrl?.trim() ?? '';
    if (url.startsWith('data:image/')) {
      final bytes = _bytesFromDataUrl(url);
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    }
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
    color: const Color(0xFFC2105C),
    child: const Icon(Icons.person_rounded, color: Color(0xFFFFD8B5), size: 38),
  );

  Uint8List? _bytesFromDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || commaIndex == -1) return null;
    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }
}

// ── Role badge ────────────────────────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _C.gold.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.gold.withOpacity(0.50), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded, color: _C.gold, size: 12),
          const SizedBox(width: 5),
          Text(
            role.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _C.gold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Staff ID chip ─────────────────────────────────────────────────────────────
class _StaffIdChip extends StatelessWidget {
  final String staffId;
  const _StaffIdChip({required this.staffId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, color: Color(0xFFFFD8B5), size: 14),
          const SizedBox(width: 6),
          // "ID" label
          const Text(
            'ID',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFB380),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 5),
          // Thin divider
          Container(
            width: 1,
            height: 12,
            color: Colors.white.withOpacity(0.25),
          ),
          const SizedBox(width: 5),
          // Actual ID value
          Text(
            staffId,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFD8B5),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM CARD WIDGET  (upgraded — keeps picture unchanged)
// ═══════════════════════════════════════════════════════════════════════════

class _ItemCard extends StatefulWidget {
  final String imageAsset;
  final List<String> imageAssets;
  final String itemName;
  final String category;
  final bool isLocked;
  final VoidCallback onTap;

  const _ItemCard({
    required this.imageAsset,
    this.imageAssets = const [],
    required this.itemName,
    required this.category,
    required this.isLocked,
    required this.onTap,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _pressed = false;
  late final PageController _imageController;
  Timer? _imageTimer;
  int _imageIndex = 0;

  List<String> get _imageSources {
    final sources = widget.imageAssets
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (sources.isEmpty) sources.add(widget.imageAsset);
    return sources;
  }

  @override
  void initState() {
    super.initState();
    _imageController = PageController();
    _startImageTimer();
  }

  @override
  void didUpdateWidget(covariant _ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageAssets.length != widget.imageAssets.length ||
        oldWidget.imageAsset != widget.imageAsset) {
      _imageIndex = 0;
      _imageTimer?.cancel();
      if (_imageController.hasClients) _imageController.jumpToPage(0);
      _startImageTimer();
    }
  }

  void _startImageTimer() {
    if (_imageSources.length < 2) return;
    _imageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_imageController.hasClients) return;
      _imageIndex = (_imageIndex + 1) % _imageSources.length;
      _imageController.animateToPage(
        _imageIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withOpacity(widget.isLocked ? 0.06 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 118,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Left accent bar (gradient) ────────────────────────
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: widget.isLocked
                            ? [Colors.grey.shade300, Colors.grey.shade200]
                            : [_C.gold, _C.accent, _C.primary],
                        stops: widget.isLocked ? null : const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),

                  // ── Item image (picture unchanged) ────────────────────
                  Container(
                    width: 84,
                    height: 84,
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _C.primary.withOpacity(0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _buildImageCarousel(),
                    ),
                  ),

                  // ── Text section ──────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 13, 4, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Category label
                          Text(
                            widget.category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: widget.isLocked
                                  ? Colors.grey.shade400
                                  : _C.accent.withOpacity(0.9),
                              letterSpacing: 1.2,
                            ),
                          ),

                          const SizedBox(height: 3),

                          // Item name  ← UPGRADED
                          Text(
                            widget.itemName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: widget.isLocked
                                  ? Colors.grey.shade500
                                  : _C.primaryDark,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 8),

                          // Status badge
                          _ItemStatusBadge(isLocked: widget.isLocked),
                        ],
                      ),
                    ),
                  ),

                  // ── Arrow / Lock button ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: widget.isLocked
                              ? LinearGradient(
                                  colors: [
                                    Colors.grey.shade200,
                                    Colors.grey.shade300,
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFC2105C),
                                    Color(0xFFF48FB1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: widget.isLocked
                              ? []
                              : [
                                  BoxShadow(
                                    color: _C.primary.withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Icon(
                          widget.isLocked
                              ? Icons.block_rounded
                              : Icons.chevron_right_rounded,
                          color: widget.isLocked
                              ? Colors.grey.shade500
                              : Colors.white,
                          size: 20,
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
  }

  Widget _buildItemImage() {
    return _buildImageSource(widget.imageAsset);
  }

  Widget _buildImageCarousel() {
    final sources = _imageSources;
    if (sources.length < 2) return _buildImageSource(sources.first);
    return PageView.builder(
      controller: _imageController,
      physics: const BouncingScrollPhysics(),
      itemCount: sources.length,
      onPageChanged: (page) => _imageIndex = page,
      itemBuilder: (context, index) => _buildImageSource(sources[index]),
    );
  }

  Widget _buildImageSource(String src) {
    if (src.startsWith('data:image/')) {
      final commaIndex = src.indexOf(',');
      if (commaIndex != -1) {
        try {
          return Image.memory(
            base64Decode(src.substring(commaIndex + 1)),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _imageFallback(),
          );
        } catch (_) {
          return _imageFallback();
        }
      }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    }
    return Image.asset(
      src,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _imageFallback(),
    );
  }

  Widget _imageFallback() => Container(
    color: const Color(0xFFFFF0E4),
    child: const Icon(Icons.cake_rounded, color: _C.accent, size: 34),
  );
}

// ── Item status badge ─────────────────────────────────────────────────────────
class _ItemStatusBadge extends StatelessWidget {
  final bool isLocked;
  const _ItemStatusBadge({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isLocked ? Colors.grey.shade100 : const Color(0xFFFFF0E4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLocked ? Colors.grey.shade300 : _C.accent.withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocked ? Icons.block_rounded : Icons.edit_note_rounded,
            size: 11,
            color: isLocked ? Colors.grey.shade500 : _C.primaryLight,
          ),
          const SizedBox(width: 4),
          Text(
            isLocked ? 'Unavailable' : 'Tap to view',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isLocked ? Colors.grey.shade500 : _C.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════════

class _HistorySheet extends StatefulWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> receiptStream;
  final Stream<List<Map<String, dynamic>>> localReceiptStream;
  const _HistorySheet({
    required this.receiptStream,
    required this.localReceiptStream,
  });

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  String _selectedDate = _formatDate(DateTime.now());
  String _selectedPaymentMode = 'Cash';

  Map<String, List<Map<String, dynamic>>> _groupByDate(
    Iterable<Map<String, dynamic>> receipts,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final data in receipts) {
      final timestamp = data['timestamp'];
      if (timestamp is! Timestamp) continue;
      final dt = timestamp.toDate().toLocal();
      grouped.putIfAbsent(_formatDate(dt), () => []).add(data);
    }
    for (final values in grouped.values) {
      values.sort((a, b) {
        final at = a['timestamp'] as Timestamp?;
        final bt = b['timestamp'] as Timestamp?;
        return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
          at?.millisecondsSinceEpoch ?? 0,
        );
      });
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8F5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.pink.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: _C.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Sales History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Filter date',
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = _formatDate(picked));
                      }
                    },
                    icon: const Icon(
                      Icons.calendar_today_rounded,
                      color: _C.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _C.primary),
                  ),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: widget.localReceiptStream,
                builder: (context, localSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: widget.receiptStream,
                    builder: (context, snapshot) {
                      final localReceipts = localSnapshot.data ?? const [];
                      final cloudReceipts = (snapshot.data?.docs ?? [])
                          .map((doc) => doc.data())
                          .toList();
                      final bySalesId = <String, Map<String, dynamic>>{};
                      for (final receipt in [
                        ...localReceipts,
                        ...cloudReceipts,
                      ]) {
                        final salesId = receipt['salesId']?.toString() ?? '';
                        final key = salesId.isNotEmpty
                            ? salesId
                            : 'local-${receipt['localId'] ?? bySalesId.length}';
                        bySalesId[key] = receipt;
                      }
                      if (bySalesId.isEmpty &&
                          snapshot.connectionState == ConnectionState.waiting &&
                          localSnapshot.connectionState ==
                              ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: _C.primary),
                        );
                      }
                      final grouped = _groupByDate(bySalesId.values);
                      final today = _formatDate(DateTime.now());
                      final dates = {today, ...grouped.keys}.toList()
                        ..sort((a, b) {
                          DateTime parseDate(String value) {
                            try {
                              return DateTime.parse(value);
                            } catch (_) {
                              final parts = value.split(' ');
                              if (parts.length < 3) return DateTime(1970);
                              const months = [
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
                              final month = months.indexOf(parts[0]) + 1;
                              final day =
                                  int.tryParse(parts[1].replaceAll(',', '')) ??
                                  1;
                              final year = int.tryParse(parts[2]) ?? 1970;
                              return DateTime(year, month, day);
                            }
                          }

                          return parseDate(b).compareTo(parseDate(a));
                        });
                      if (!dates.contains(_selectedDate)) {
                        _selectedDate = today;
                      }
                      final receipts = grouped[_selectedDate] ?? [];
                      final filteredReceipts = receipts.where((receipt) {
                        final mode =
                            receipt['paymentMode']?.toString() ?? 'Cash';
                        return mode == _selectedPaymentMode;
                      }).toList();
                      double gcashTotal = 0;
                      double cashTotal = 0;
                      for (final receipt in receipts) {
                        final total =
                            (receipt['total'] as num?)?.toDouble() ?? 0;
                        final mode =
                            receipt['paymentMode']?.toString() ?? 'Cash';
                        if (mode == 'GCash') {
                          gcashTotal += total;
                        } else {
                          cashTotal += total;
                        }
                      }

                      if (grouped.isEmpty) {
                        return Center(
                          child: Text(
                            'No receipt history yet.',
                            style: TextStyle(
                              color: Colors.pink.shade400,
                              fontSize: 15,
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: dates.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final d = dates[i];
                                final selected = d == _selectedDate;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedDate = d),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? _C.primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: selected
                                            ? _C.primary
                                            : Colors.pink.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      d,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? Colors.white
                                            : Colors.pink.shade600,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _HistoryPaymentChip(
                                    label: 'Cash',
                                    value: cashTotal,
                                    color: Colors.green.shade700,
                                    selected: _selectedPaymentMode == 'Cash',
                                    onTap: () => setState(() {
                                      _selectedPaymentMode = 'Cash';
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _HistoryPaymentChip(
                                    label: 'GCash',
                                    value: gcashTotal,
                                    color: Colors.blue.shade700,
                                    selected: _selectedPaymentMode == 'GCash',
                                    onTap: () => setState(() {
                                      _selectedPaymentMode = 'GCash';
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFEDD9C8),
                          ),
                          Expanded(
                            child: filteredReceipts.isEmpty
                                ? Center(
                                    child: Text(
                                      'No receipt record',
                                      style: TextStyle(
                                        color: Colors.pink.shade400,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : ListView(
                                    controller: scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      40,
                                    ),
                                    children: filteredReceipts
                                        .map(
                                          (data) => _ReceiptCard(
                                            data: data,
                                            compact: false,
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
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

class _HistoryPaymentChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _HistoryPaymentChip({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.18),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF1B5E20) : color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              '₱${value.toStringAsFixed(2)}',
              style: TextStyle(
                color: selected ? const Color(0xFF1B5E20) : color,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Entry Card
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryEntryCard extends StatelessWidget {
  final dynamic inv;
  const _HistoryEntryCard({required this.inv});

  int _startingAt(int index, int startA, int startB, int startC) {
    if (index == 0) return startA;
    if (index == 1) return startB;
    if (index == 2) return startC;
    return 0;
  }

  int _remainingAt(int index, int remA, int remB, int remC) {
    if (index == 0) return remA;
    if (index == 1) return remB;
    if (index == 2) return remC;
    return 0;
  }

  bool _isCoffeePerformanceEntry(
    List<Map<String, dynamic>> items,
    String title,
  ) {
    final titleLower = title.toLowerCase();
    return titleLower.contains('coffee') ||
        titleLower.contains('smoothie') ||
        titleLower.contains('latte') ||
        titleLower.contains('espresso') ||
        items.any((item) {
          return item['isCoffee'] == true ||
              (item['coffeeId']?.toString().trim().isNotEmpty ?? false) ||
              (item['coffeeSize']?.toString().trim().isNotEmpty ?? false) ||
              (item['addonName']?.toString().trim().isNotEmpty ?? false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final String item = inv is Map
        ? (inv['item']?.toString() ?? 'Unknown')
        : (inv.safeItem.isNotEmpty ? inv.safeItem : 'Unknown');

    DateTime dt;
    try {
      dt = inv is Map
          ? (inv['timestamp']?.toDate() ?? DateTime.now()).toLocal()
          : inv.timestamp.toLocal();
    } catch (_) {
      dt = DateTime.now();
    }
    final timeStr = _formatTime(dt);
    final int startA = inv is Map
        ? (inv['startingA'] ?? 0) as int
        : inv.safeStartingA;
    final int startB = inv is Map
        ? (inv['startingB'] ?? 0) as int
        : inv.safeStartingB;
    final int startC = inv is Map
        ? (inv['startingC'] ?? 0) as int
        : inv.safeStartingC;
    final int remA = inv is Map
        ? (inv['remainingA'] ?? 0) as int
        : inv.safeRemainingA;
    final int remB = inv is Map
        ? (inv['remainingB'] ?? 0) as int
        : inv.safeRemainingB;
    final int remC = inv is Map
        ? (inv['remainingC'] ?? 0) as int
        : inv.safeRemainingC;

    final int totalStart = startA + startB + startC;
    final int totalRemaining = remA + remB + remC;
    final List<Map<String, dynamic>> itemsList = inv is Map
        ? (inv['items'] as List?)?.cast<Map<String, dynamic>>() ?? []
        : inv.safeItems;
    final isBundle = itemsList.any((item) => item['isBundle'] == true);
    final isCoffee = itemsList.any((item) => item['isCoffee'] == true);
    final salesOnly = _isCoffeePerformanceEntry(itemsList, item);
    final coffeeId = itemsList
        .map((item) => item['coffeeId']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final totalReduced = itemsList.fold<int>(
      0,
      (sum, item) =>
          sum + (int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0),
    );
    final int totalSold = (totalStart - totalRemaining - totalReduced)
        .clamp(0, totalStart)
        .toInt();

    final double storedRevenue = inv is Map
        ? (inv['totalSalesRevenue'] as num?)?.toDouble() ?? 0.0
        : inv.safeTotalSalesRevenue;
    double totalSoldValue = storedRevenue;

    if (totalSoldValue <= 0) {
      for (var i = 0; i < itemsList.length; i++) {
        final d = itemsList[i];
        final startQty = _startingAt(i, startA, startB, startC);
        final remQty = _remainingAt(i, remA, remB, remC);
        final price = double.tryParse(d['price']?.toString() ?? '0') ?? 0;
        final reducedQty =
            int.tryParse(d['reducedQuantity']?.toString() ?? '') ?? 0;
        final soldQty = (startQty - remQty - reducedQty)
            .clamp(0, startQty)
            .toInt();
        totalSoldValue += soldQty * price;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _C.primary.withOpacity(0.08),
                  _C.primary.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryDark,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _C.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stats + breakdown
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    _StatChip(
                      label: 'Starting',
                      value: '$totalStart',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Remaining',
                      value: '$totalRemaining',
                      icon: Icons.layers_outlined,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Sold',
                      value: '$totalSold',
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.green.shade700,
                    ),
                  ],
                ),
                if (totalSoldValue > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Total Sales',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₱${totalSoldValue.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (itemsList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0E0D6)),
                  const SizedBox(height: 8),
                  ...itemsList.asMap().entries.map((entry) {
                    final index = entry.key;
                    final d = entry.value;
                    final iName = d['name'] ?? 'Unknown';
                    final startQty = _startingAt(index, startA, startB, startC);
                    final remQty = _remainingAt(index, remA, remB, remC);
                    final reducedQty =
                        int.tryParse(d['reducedQuantity']?.toString() ?? '') ??
                        0;
                    final soldQty = (startQty - remQty - reducedQty)
                        .clamp(0, startQty)
                        .toInt();
                    final progress = startQty > 0 ? soldQty / startQty : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  iName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFE91E63),
                                  ),
                                ),
                              ),
                              Text(
                                '$soldQty / $startQty sold',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.pink.shade400,
                                ),
                              ),
                            ],
                          ),
                          if (reducedQty > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              '$reducedQty reduced',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.toDouble(),
                              minHeight: 6,
                              backgroundColor: Colors.pink.shade100,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress > 0.7
                                    ? Colors.green.shade500
                                    : progress > 0.3
                                    ? _C.accent
                                    : Colors.red.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Card
// ═══════════════════════════════════════════════════════════════════════════

class _PerformanceCard extends StatelessWidget {
  final dynamic inv;
  const _PerformanceCard({required this.inv});

  bool _isCoffeePerformanceEntry(
    List<Map<String, dynamic>> items,
    String title,
  ) {
    final titleLower = title.toLowerCase();
    return titleLower.contains('coffee') ||
        titleLower.contains('smoothie') ||
        titleLower.contains('latte') ||
        titleLower.contains('espresso') ||
        items.any((item) {
          return item['isCoffee'] == true ||
              (item['coffeeId']?.toString().trim().isNotEmpty ?? false) ||
              (item['coffeeSize']?.toString().trim().isNotEmpty ?? false) ||
              (item['addonName']?.toString().trim().isNotEmpty ?? false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final String item = inv is Map
        ? (inv['item']?.toString() ?? 'Unknown')
        : (inv.safeItem.isNotEmpty ? inv.safeItem : 'Unknown');

    DateTime dt;
    try {
      dt = inv is Map
          ? (inv['timestamp']?.toDate() ?? DateTime.now()).toLocal()
          : inv.timestamp.toLocal();
    } catch (_) {
      dt = DateTime.now();
    }
    final timestamp = _formatDateTime(dt);

    final int startA = inv is Map
        ? (inv['startingA'] ?? 0) as int
        : inv.safeStartingA;
    final int startB = inv is Map
        ? (inv['startingB'] ?? 0) as int
        : inv.safeStartingB;
    final int startC = inv is Map
        ? (inv['startingC'] ?? 0) as int
        : inv.safeStartingC;
    final int remA = inv is Map
        ? (inv['remainingA'] ?? 0) as int
        : inv.safeRemainingA;
    final int remB = inv is Map
        ? (inv['remainingB'] ?? 0) as int
        : inv.safeRemainingB;
    final int remC = inv is Map
        ? (inv['remainingC'] ?? 0) as int
        : inv.safeRemainingC;

    final int totalStart = startA + startB + startC;
    final int totalRemaining = remA + remB + remC;

    final List<Map<String, dynamic>> itemsList = inv is Map
        ? (inv['items'] as List?)?.cast<Map<String, dynamic>>() ?? []
        : inv.safeItems;
    final isBundle = itemsList.any((item) => item['isBundle'] == true);
    final isCoffee = itemsList.any((item) => item['isCoffee'] == true);
    final salesOnly = _isCoffeePerformanceEntry(itemsList, item);
    final coffeeId = itemsList
        .map((item) => item['coffeeId']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final double storedRevenue = inv is Map
        ? (inv['totalSalesRevenue'] as num?)?.toDouble() ?? 0.0
        : inv.safeTotalSalesRevenue;
    double totalSoldValue = storedRevenue;
    if (totalSoldValue <= 0) {
      for (var i = 0; i < itemsList.length; i++) {
        final d = itemsList[i];
        final startQty = i == 0
            ? startA
            : i == 1
            ? startB
            : i == 2
            ? startC
            : 0;
        final remQty = i == 0
            ? remA
            : i == 1
            ? remB
            : i == 2
            ? remC
            : 0;
        final price = double.tryParse(d['price']?.toString() ?? '0') ?? 0;
        final reducedQty =
            int.tryParse(d['reducedQuantity']?.toString() ?? '') ?? 0;
        final soldQty = (startQty - remQty - reducedQty)
            .clamp(0, startQty)
            .toInt();
        totalSoldValue += soldQty * price;
      }
    }

    final totalReduced = itemsList.fold<int>(
      0,
      (sum, item) =>
          sum + (int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0),
    );
    final int totalSold = (totalStart - totalRemaining - totalReduced)
        .clamp(0, totalStart)
        .toInt();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gradient header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBundle) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Bundle',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isCoffee) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_cafe_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  coffeeId.isNotEmpty ? coffeeId : 'Coffee',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timestamp,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (itemsList.isNotEmpty) ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Item',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE91E63),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Text(
                          salesOnly ? 'Sold' : 'Start',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: salesOnly
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                          ),
                        ),
                        if (!salesOnly) ...[
                          const SizedBox(width: 20),
                          Text(
                            'Rem.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(height: 1, color: const Color(0xFFF0E0D6)),
                    const SizedBox(height: 8),
                    ...itemsList.asMap().entries.map((entry) {
                      final index = entry.key;
                      final d = entry.value;
                      final iName = d['name'] ?? 'Unknown';
                      final startQty = index == 0
                          ? startA
                          : index == 1
                          ? startB
                          : index == 2
                          ? startC
                          : 0;
                      final remQty = index == 0
                          ? remA
                          : index == 1
                          ? remB
                          : index == 2
                          ? remC
                          : 0;
                      final reducedQty =
                          int.tryParse(
                            d['reducedQuantity']?.toString() ?? '',
                          ) ??
                          0;
                      final soldQty = (startQty - remQty - reducedQty)
                          .clamp(0, startQty)
                          .toInt();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    iName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFC2105C),
                                    ),
                                  ),
                                ),
                                if (salesOnly)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${soldQty == 0 ? 1 : soldQty} sold',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  )
                                else ...[
                                  Text(
                                    '$startQty',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '$remQty',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (reducedQty > 0)
                              Text(
                                '$reducedQty reduced',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(height: 1, color: const Color(0xFFF0E0D6)),
                    const SizedBox(height: 12),

                    if (totalStart > 0 ||
                        totalRemaining > 0 ||
                        totalSoldValue > 0) ...[
                      if (!salesOnly) ...[
                        _SummaryRow(
                          label: 'Total Stock',
                          value: '$totalStart',
                          valueColor: Colors.blue.shade700,
                        ),
                        const SizedBox(height: 4),
                        _SummaryRow(
                          label: 'Total Remaining',
                          value: '$totalRemaining',
                          valueColor: Colors.orange.shade700,
                        ),
                        const SizedBox(height: 4),
                      ],
                      _SummaryRow(
                        label: 'Total Sold',
                        value: salesOnly && totalSold == 0 ? '1' : '$totalSold',
                        valueColor: Colors.green.shade700,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.payments_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Total Sales',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '₱${totalSoldValue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.hourglass_empty_rounded,
                              color: Colors.orange.shade600,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Remaining not yet recorded.',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable small widgets
// ═══════════════════════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFFE91E63),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          const SizedBox(width: 10),
          Text(
            message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;

  const _EmptyState({required this.icon, required this.label, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.pink.shade200),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: Colors.pink.shade400,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (sublabel != null) ...[
              const SizedBox(height: 4),
              Text(
                sublabel!,
                style: TextStyle(color: Colors.pink.shade300, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Custom Painters
// ═══════════════════════════════════════════════════════════════════════════

/// Subtle diagonal stripe pattern for header background texture
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2;
    const spacing = 22.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soft arc at bottom of header to blend into content area
class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFF8F5)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width / 2,
        -size.height * 0.5,
        size.width,
        size.height,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
