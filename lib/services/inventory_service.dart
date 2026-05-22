import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory.dart';

/// Singleton service for inventory management.
class InventoryService extends ChangeNotifier {
  InventoryService._internal();

  static final InventoryService _instance = InventoryService._internal();

  factory InventoryService() => _instance;

  final List<Inventory> _entries = [];
  bool _initialized = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adjustmentsSub;

  String? get _currentOwnerId => FirebaseAuth.instance.currentUser?.uid;

  bool _matchesCurrentOwner(Inventory entry) {
    final ownerId = _currentOwnerId;
    if (ownerId == null) {
      return entry.ownerId == null;
    }
    return entry.ownerId == ownerId;
  }

  List<Inventory> get entries => List.unmodifiable(_entries);

  List<Inventory> get currentUserEntries =>
      _entries.where(_matchesCurrentOwner).toList();

  static const String _prefsKey = 'inventory_history_json';
  static const String _reportsCollection = 'inventory_reports';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFromDisk();
    _startCloudListeners();
    await refreshFromCloud();
  }

  Future<void> refreshFromCloud() async {
    await _loadFromFirestore();
  }

  void clear() {
    _entries.clear();
    _saveToDisk();
    notifyListeners();
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    _adjustmentsSub?.cancel();
    super.dispose();
  }

  void _startCloudListeners() {
    _reportsSub ??= FirebaseFirestore.instance
        .collection(_reportsCollection)
        .snapshots()
        .listen((_) => unawaited(refreshFromCloud()));
    _adjustmentsSub ??= FirebaseFirestore.instance
        .collection('stock_adjustments')
        .snapshots()
        .listen((_) => unawaited(refreshFromCloud()));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameInventoryIdentity(
    Inventory entry,
    String itemName,
    String? sourceInventoryId,
  ) {
    final key = itemName.trim().toLowerCase();
    final sourceKey = sourceInventoryId?.trim();
    if (sourceKey != null && sourceKey.isNotEmpty) {
      return entry.sourceInventoryId == sourceKey;
    }
    return entry.safeItem.trim().toLowerCase() == key;
  }

  Inventory? _getEntryForItemToday(String itemName, {String? sourceInventoryId}) {
    final now = DateTime.now();

    try {
      return _entries.firstWhere(
        (entry) =>
            _sameInventoryIdentity(entry, itemName, sourceInventoryId) &&
            _sameDay(entry.timestamp, now) &&
            _matchesCurrentOwner(entry),
      );
    } catch (e) {
      return null;
    }
  }

  Inventory? _getAnyEntryForItemToday(String itemName, {String? sourceInventoryId}) {
    final now = DateTime.now();

    try {
      return _entries.firstWhere(
        (entry) =>
            _sameInventoryIdentity(entry, itemName, sourceInventoryId) &&
            _sameDay(entry.timestamp, now),
      );
    } catch (e) {
      return null;
    }
  }

  bool hasEntryForItemToday(String itemName, {String? sourceInventoryId}) =>
      _getEntryForItemToday(itemName, sourceInventoryId: sourceInventoryId) != null;

  Inventory? getEntryForItemToday(String itemName, {String? sourceInventoryId}) =>
      _getEntryForItemToday(itemName, sourceInventoryId: sourceInventoryId);

  bool hasAnyEntryForItemToday(String itemName, {String? sourceInventoryId}) =>
      _getAnyEntryForItemToday(itemName, sourceInventoryId: sourceInventoryId) != null;

  Inventory? getAnyEntryForItemToday(String itemName, {String? sourceInventoryId}) =>
      _getAnyEntryForItemToday(itemName, sourceInventoryId: sourceInventoryId);

  void _persistUpdatedEntries() {
    _saveToDisk();
    notifyListeners();
  }

  void addInventory(Inventory newEntry) {
    final existing = _getEntryForItemToday(
      newEntry.safeItem,
      sourceInventoryId: newEntry.sourceInventoryId,
    );

    if (existing != null) {
      final index = _entries.indexOf(existing);
      if (index != -1) {
        _entries[index] = Inventory(
          item: newEntry.item,
          ownerId: existing.ownerId,
          sourceInventoryId: existing.sourceInventoryId,
          items: newEntry.items,
          totalSalesRevenue:
              existing.safeTotalSalesRevenue + newEntry.safeTotalSalesRevenue,
          startingA: newEntry.safeStartingA,
          startingB: newEntry.safeStartingB,
          startingC: newEntry.safeStartingC,
          remainingA: existing.safeRemainingA,
          remainingB: existing.safeRemainingB,
          remainingC: existing.safeRemainingC,
          timestamp: existing.timestamp,
        );
      }
    } else {
      _entries.add(
        Inventory(
          item: newEntry.item,
          ownerId: newEntry.ownerId ?? _currentOwnerId,
          sourceInventoryId: newEntry.sourceInventoryId,
          items: newEntry.items,
          startingA: newEntry.safeStartingA,
          startingB: newEntry.safeStartingB,
          startingC: newEntry.safeStartingC,
          remainingA: newEntry.safeRemainingA,
          remainingB: newEntry.safeRemainingB,
          remainingC: newEntry.safeRemainingC,
          totalSalesRevenue: newEntry.safeTotalSalesRevenue,
          timestamp: newEntry.timestamp,
        ),
      );
    }

    _persistUpdatedEntries();
    _saveEntryToFirestore(_entries.firstWhere(
      (entry) =>
          _sameInventoryIdentity(
            entry,
            newEntry.safeItem,
            newEntry.sourceInventoryId,
          ) &&
          _sameDay(entry.timestamp, newEntry.timestamp) &&
          (entry.ownerId ?? '') == (newEntry.ownerId ?? _currentOwnerId ?? ''),
      orElse: () => newEntry,
    ));
  }

  void addRemainingStockForItem({
    required String itemName,
    required int quantityA,
    required int quantityB,
    required int quantityC,
    int? startingA,
    int? startingB,
    int? startingC,
    List<Map<String, dynamic>>? items,
    double saleRevenue = 0.0,
    String? sourceInventoryId,
  }) {
    final existing = _getEntryForItemToday(
      itemName,
      sourceInventoryId: sourceInventoryId,
    );

    if (existing != null) {
      final index = _entries.indexOf(existing);
      if (index != -1) {
        final existingRevenue = existing.totalSalesRevenue ?? 0.0;
        _entries[index] = Inventory(
          item: existing.item,
          ownerId: existing.ownerId,
          sourceInventoryId: existing.sourceInventoryId,
          items: items ?? existing.items,
          totalSalesRevenue: existingRevenue + saleRevenue,
          startingA: startingA ?? existing.safeStartingA,
          startingB: startingB ?? existing.safeStartingB,
          startingC: startingC ?? existing.safeStartingC,
          remainingA: quantityA,
          remainingB: quantityB,
          remainingC: quantityC,
          timestamp: existing.timestamp,
        );
      }
    } else {
      _entries.add(
        Inventory(
          item: itemName,
          sourceInventoryId: sourceInventoryId,
          startingA: startingA ?? 0,
          startingB: startingB ?? 0,
          startingC: startingC ?? 0,
          remainingA: quantityA,
          remainingB: quantityB,
          remainingC: quantityC,
          items: items,
          totalSalesRevenue: saleRevenue,
          ownerId: _currentOwnerId,
        ),
      );
    }

    _persistUpdatedEntries();
    final updated = _getEntryForItemToday(
      itemName,
      sourceInventoryId: sourceInventoryId,
    );
    if (updated != null) {
      _saveEntryToFirestore(updated);
    }
  }

  /// Subtract sold quantities from remaining stock for an item
  void subtractSoldQuantities({
    required String itemName,
    int quantityA = 0,
    int quantityB = 0,
    int quantityC = 0,
    double saleRevenue = 0.0,
    String? sourceInventoryId,
  }) {
    final existing = _getEntryForItemToday(
      itemName,
      sourceInventoryId: sourceInventoryId,
    );
    if (existing != null) {
      final index = _entries.indexOf(existing);
      if (index != -1) {
        final newRemainingA = max(0, existing.safeRemainingA - quantityA);
        final newRemainingB = max(0, existing.safeRemainingB - quantityB);
        final newRemainingC = max(0, existing.safeRemainingC - quantityC);
        final existingRevenue = existing.totalSalesRevenue ?? 0.0;

        _entries[index] = Inventory(
          item: existing.item,
          ownerId: existing.ownerId,
          sourceInventoryId: existing.sourceInventoryId,
          items: existing.items,
          totalSalesRevenue: existingRevenue + saleRevenue,
          startingA: existing.safeStartingA,
          startingB: existing.safeStartingB,
          startingC: existing.safeStartingC,
          remainingA: newRemainingA,
          remainingB: newRemainingB,
          remainingC: newRemainingC,
          timestamp: existing.timestamp,
        );
        
        _persistUpdatedEntries();
        _saveEntryToFirestore(_entries[index]);
      }
    }
  }

  void recordStockReduction({
    required String itemName,
    required String variantName,
    required int quantity,
    String? sourceInventoryId,
  }) {
    if (quantity <= 0) return;
    final existing = _getEntryForItemToday(
      itemName,
      sourceInventoryId: sourceInventoryId,
    );
    if (existing == null) return;

    final index = _entries.indexOf(existing);
    if (index == -1) return;

    final updatedItems = List<Map<String, dynamic>>.from(existing.safeItems);
    final variantKey = variantName.trim().toLowerCase();
    for (var i = 0; i < updatedItems.length; i++) {
      final item = Map<String, dynamic>.from(updatedItems[i]);
      final savedId = item['id']?.toString().trim().toLowerCase() ?? '';
      final savedName = item['name']?.toString().trim().toLowerCase() ?? '';
      final savedVariant =
          item['variant']?.toString().trim().toLowerCase() ?? '';
      if (savedId != variantKey &&
          savedName != variantKey &&
          savedVariant != variantKey) {
        continue;
      }
      final currentReduced =
          int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0;
      final newRemainingA = i == 0
          ? max(0, existing.safeRemainingA - quantity)
          : existing.safeRemainingA;
      final newRemainingB = i == 1
          ? max(0, existing.safeRemainingB - quantity)
          : existing.safeRemainingB;
      final newRemainingC = i == 2
          ? max(0, existing.safeRemainingC - quantity)
          : existing.safeRemainingC;
      updatedItems[i] = {
        ...item,
        'reducedQuantity': currentReduced + quantity,
      };
      _entries[index] = Inventory(
        item: existing.item,
        ownerId: existing.ownerId,
        sourceInventoryId: existing.sourceInventoryId,
        items: updatedItems,
        totalSalesRevenue: existing.safeTotalSalesRevenue,
        startingA: existing.safeStartingA,
        startingB: existing.safeStartingB,
        startingC: existing.safeStartingC,
        remainingA: newRemainingA,
        remainingB: newRemainingB,
        remainingC: newRemainingC,
        timestamp: existing.timestamp,
      );
      _persistUpdatedEntries();
      _saveEntryToFirestore(_entries[index]);
      return;
    }
  }

  String _entryDocId(Inventory entry) {
    final owner = (entry.ownerId ?? 'unknown').replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final identity = (entry.sourceInventoryId?.trim().isNotEmpty == true
            ? entry.sourceInventoryId!
            : entry.safeItem)
        .trim()
        .toLowerCase();
    final item = identity.replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    final dt = entry.timestamp;
    final date =
        '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
    return '$owner-$date-$item';
  }

  void _mergeEntry(Inventory entry) {
    final index = _entries.indexWhere(
      (existing) =>
          _sameInventoryIdentity(existing, entry.safeItem, entry.sourceInventoryId) &&
          (existing.ownerId ?? '') == (entry.ownerId ?? '') &&
          _sameDay(existing.timestamp, entry.timestamp),
    );
    if (index == -1) {
      _entries.add(entry);
    } else {
      final existing = _entries[index];
      _entries[index] = Inventory(
        item: entry.item,
        ownerId: entry.ownerId,
        sourceInventoryId: entry.sourceInventoryId,
        items: entry.items,
        totalSalesRevenue: max(
          entry.safeTotalSalesRevenue,
          existing.safeTotalSalesRevenue,
        ).toDouble(),
        startingA: entry.safeStartingA,
        startingB: entry.safeStartingB,
        startingC: entry.safeStartingC,
        remainingA: entry.safeRemainingA,
        remainingB: entry.safeRemainingB,
        remainingC: entry.safeRemainingC,
        timestamp: entry.timestamp,
      );
    }
  }

  Future<void> _saveEntryToFirestore(Inventory entry) async {
    try {
      await FirebaseFirestore.instance
          .collection(_reportsCollection)
          .doc(_entryDocId(entry))
          .set({
        ...entry.toJson(),
        'timestamp': Timestamp.fromDate(entry.timestamp),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to save inventory report to Firestore: $e');
      }
    }
  }

  Future<void> _loadFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_reportsCollection)
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();

      for (final doc in snapshot.docs) {
        _mergeEntry(Inventory.fromJson(doc.data()));
      }
      await _mergeAssignedInventoryItemsFromFirestore();
      await _mergeStockAdjustmentsFromFirestore();
      await _saveToDisk();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load inventory reports from Firestore: $e');
      }
    }
  }

  Future<void> _mergeAssignedInventoryItemsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staff_inventory')
          .limit(1000)
          .get();

      for (var entryIndex = 0; entryIndex < _entries.length; entryIndex++) {
        final entry = _entries[entryIndex];
        final sourceId = entry.sourceInventoryId?.trim() ?? '';
        final entryName = entry.safeItem.trim().toLowerCase();
        if (sourceId.isEmpty && entryName.isEmpty) continue;

        Map<String, dynamic>? assignedData;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data['isDeleted'] == true) continue;
          final assignedSource =
              data['sourceInventoryId']?.toString().trim() ?? doc.id;
          final assignedName = data['name']?.toString().trim().toLowerCase() ?? '';
          final sourceMatches = sourceId.isNotEmpty && assignedSource == sourceId;
          final nameMatches = entryName.isNotEmpty && assignedName == entryName;
          if (sourceMatches || nameMatches) {
            assignedData = data;
            break;
          }
        }
        if (assignedData == null || assignedData['isBundle'] == true) continue;

        final assignedItems = (assignedData['items'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        if (assignedItems.isEmpty) continue;

        final existingItems = List<Map<String, dynamic>>.from(entry.safeItems);
        final mergedItems = <Map<String, dynamic>>[];
        final starts = [entry.safeStartingA, entry.safeStartingB, entry.safeStartingC];
        final rems = [entry.safeRemainingA, entry.safeRemainingB, entry.safeRemainingC];
        var changed = assignedItems.length > existingItems.length;

        for (var i = 0; i < assignedItems.length && i < 3; i++) {
          final assigned = assignedItems[i];
          final assignedName = assigned['name']?.toString() ?? '';
          final assignedId = assigned['id']?.toString() ?? '';
          final existingIndex = existingItems.indexWhere((item) {
            final savedId = item['id']?.toString() ?? '';
            if (assignedId.isNotEmpty && savedId.isNotEmpty) {
              return savedId == assignedId;
            }
            final savedName = item['name']?.toString() ?? '';
            final savedVariant = item['variant']?.toString() ?? '';
            return savedName == assignedName || savedVariant == assignedName;
          });
          final existing = existingIndex >= 0
              ? Map<String, dynamic>.from(existingItems[existingIndex])
              : <String, dynamic>{};

          final assignedStart =
              int.tryParse(assigned['startingStock']?.toString() ?? '') ??
              int.tryParse(assigned['quantity']?.toString() ?? '') ??
              0;
          final assignedRemaining =
              int.tryParse(assigned['stock']?.toString() ?? '') ?? assignedStart;
          final price = existing['price'] ?? assigned['price'] ?? 0;
          final existingName = existing['name']?.toString() ?? '';
          final merged = {
            ...assigned,
            ...existing,
            'name': existingName.isNotEmpty ? existingName : assignedName,
            'variant': existing['variant'] ?? assigned['variant'] ?? '',
            'price': price,
            'quantity': existing['quantity'] ?? assignedStart,
            'reducedQuantity': existing['reducedQuantity'] ?? 0,
          };
          mergedItems.add(merged);

          if (starts[i] == 0 && assignedStart > 0) {
            starts[i] = assignedStart;
            changed = true;
          }
          if (rems[i] == 0 && existing.isEmpty && assignedRemaining > 0) {
            rems[i] = assignedRemaining;
            changed = true;
          }
        }

        if (!changed) continue;
        _entries[entryIndex] = Inventory(
          item: entry.item,
          ownerId: entry.ownerId,
          sourceInventoryId: entry.sourceInventoryId,
          items: mergedItems,
          totalSalesRevenue: entry.safeTotalSalesRevenue,
          startingA: starts[0],
          startingB: starts[1],
          startingC: starts[2],
          remainingA: rems[0],
          remainingB: rems[1],
          remainingC: rems[2],
          timestamp: entry.timestamp,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to merge assigned inventory items: $e');
      }
    }
  }

  Future<void> _mergeStockAdjustmentsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stock_adjustments')
          .orderBy('createdAt', descending: true)
          .limit(1000)
          .get();

      final totals = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        final createdDate = createdAt is Timestamp
            ? createdAt.toDate()
            : DateTime.tryParse(createdAt?.toString() ?? '');
        if (createdDate == null) continue;

        final categoryId = data['categoryId']?.toString().trim() ?? '';
        final categoryName = data['categoryName']?.toString().trim() ?? '';
        final variantName = data['itemName']?.toString().trim() ?? '';
        final adjustmentStaffId = data['staffId']?.toString().trim() ?? '';
        final adjustmentUserId = data['userId']?.toString().trim() ?? '';
        final quantity = int.tryParse(data['quantity']?.toString() ?? '') ?? 0;
        if (variantName.isEmpty || quantity <= 0) continue;

        for (final entry in _entries) {
          if (!_sameDay(entry.timestamp, createdDate)) continue;
          final ownerId = entry.ownerId?.trim() ?? '';
          if (ownerId.isNotEmpty &&
              adjustmentStaffId != ownerId &&
              adjustmentUserId != ownerId) {
            continue;
          }
          final sourceMatches =
              categoryId.isNotEmpty && entry.sourceInventoryId == categoryId;
          final nameMatches =
              categoryName.isNotEmpty &&
              entry.safeItem.trim().toLowerCase() ==
                  categoryName.toLowerCase();
          if (!sourceMatches && !nameMatches) continue;

          final key =
              '${_entryDocId(entry)}|${variantName.toLowerCase()}';
          totals[key] = (totals[key] ?? 0) + quantity;
        }
      }

      if (totals.isEmpty) return;

      for (var entryIndex = 0; entryIndex < _entries.length; entryIndex++) {
        final entry = _entries[entryIndex];
        final updatedItems = List<Map<String, dynamic>>.from(entry.safeItems);
        final rems = [
          entry.safeRemainingA,
          entry.safeRemainingB,
          entry.safeRemainingC,
        ];
        var changed = false;

        for (var itemIndex = 0; itemIndex < updatedItems.length; itemIndex++) {
          final item = Map<String, dynamic>.from(updatedItems[itemIndex]);
          final names = [
            item['name']?.toString().trim().toLowerCase() ?? '',
            item['variant']?.toString().trim().toLowerCase() ?? '',
          ].where((name) => name.isNotEmpty).toSet();

          var adjustmentQty = 0;
          for (final name in names) {
            adjustmentQty = max(
              adjustmentQty,
              totals['${_entryDocId(entry)}|$name'] ?? 0,
            ).toInt();
          }
          if (adjustmentQty <= 0) continue;

          final currentReduced =
              int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0;
          final nextReduced = max(currentReduced, adjustmentQty).toInt();
          final addedReduction = max(0, nextReduced - currentReduced).toInt();
          if (nextReduced == currentReduced) continue;

          updatedItems[itemIndex] = {
            ...item,
            'reducedQuantity': nextReduced,
          };
          if (itemIndex >= 0 && itemIndex < rems.length) {
            rems[itemIndex] = max(0, rems[itemIndex] - addedReduction).toInt();
          }
          changed = true;
        }

        if (!changed) continue;
        _entries[entryIndex] = Inventory(
          item: entry.item,
          ownerId: entry.ownerId,
          sourceInventoryId: entry.sourceInventoryId,
          items: updatedItems,
          totalSalesRevenue: entry.safeTotalSalesRevenue,
          startingA: entry.safeStartingA,
          startingB: entry.safeStartingB,
          startingC: entry.safeStartingC,
          remainingA: rems[0],
          remainingB: rems[1],
          remainingC: rems[2],
          timestamp: entry.timestamp,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to merge stock adjustments: $e');
      }
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKey);
      if (jsonString == null || jsonString.isEmpty) return;

      final data = jsonDecode(jsonString);
      if (data is! List) return;

      _entries.clear();
      _entries.addAll(
        data
            .whereType<Map<String, dynamic>>()
            .map((e) => Inventory.fromJson(e))
            .toList(),
      );

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load inventory history: $e');
      }
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to save inventory history: $e');
      }
    }
  }
}
