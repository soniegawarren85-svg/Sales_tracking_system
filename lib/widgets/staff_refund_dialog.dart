import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/bundle_stock_service.dart';
import '../services/local_database_sync_service.dart';
import '../services/report_current_allocations.dart';

String staffRefundItemKey(Map item) {
  final source = item['sourceInventoryId']?.toString() ?? '';
  if (item['isBundle'] == true) return 'bundle|$source';
  if (item['isCoffee'] == true) {
    final size = (item['coffeeSize'] ?? item['variant'])?.toString() ?? '';
    return 'beverage|$source|$size';
  }
  final itemId = (item['itemId'] ?? item['id'])?.toString() ?? '';
  return 'category|$source|$itemId';
}

Map<String, Map<String, dynamic>> activeStaffRefundChoices(
  Iterable<Map<String, dynamic>> inventory, {
  DateTime? now,
}) {
  final date = now ?? DateTime.now();
  final choices = <String, Map<String, dynamic>>{};
  for (final allocation in inventory) {
    if (!currentAllocationAvailable(allocation, date)) continue;
    final source =
        allocation['sourceInventoryId']?.toString().trim().isNotEmpty == true
        ? allocation['sourceInventoryId'].toString()
        : allocation['_localDocId']?.toString() ?? '';
    if (source.isEmpty) continue;
    if (allocation['isBundle'] == true) {
      if (availableBundleStock(allocation, now: date) > 0) {
        final choice = {...allocation, 'sourceInventoryId': source};
        choices[staffRefundItemKey(choice)] = choice;
      }
      continue;
    }
    if (allocation['isCoffee'] == true) {
      final configuredSizes = (allocation['sizes'] as List? ?? [])
          .whereType<Map>()
          .map((size) => Map<String, dynamic>.from(size))
          .toList();
      final availableSizes = configuredSizes.isEmpty
          ? [
              <String, dynamic>{'name': 'Regular'},
            ]
          : configuredSizes
                .where(
                  (size) =>
                      (size['name']?.toString().trim() ?? '').isNotEmpty &&
                      currentAllocationAvailable(size, date),
                )
                .toList();
      for (final size in availableSizes) {
        final choice = {
          ...allocation,
          'sourceInventoryId': source,
          'coffeeId': allocation['coffeeId'] ?? source,
          'coffeeSize': size['name'] ?? 'Regular',
          'variant': size['name'] ?? 'Regular',
          'isCoffee': true,
        };
        choices[staffRefundItemKey(choice)] = choice;
      }
      continue;
    }

    final removedIds = (allocation['removedItems'] as List? ?? [])
        .whereType<Map>()
        .map((item) => item['id']?.toString())
        .whereType<String>()
        .toSet();
    for (final raw in (allocation['items'] as List? ?? []).whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final itemId = (item['id'] ?? item['itemId'])?.toString() ?? '';
      final stock = item['stock'] ?? item['startingStock'];
      if (!currentAllocationAvailable(item, date) ||
          itemId.isEmpty ||
          removedIds.contains(itemId) ||
          (stock is num ? stock : num.tryParse('$stock') ?? 0) <= 0) {
        continue;
      }
      final choice = {
        ...item,
        'sourceInventoryId': source,
        'staffInventoryDocId':
            allocation['_localDocId'] ?? allocation['staffDocId'] ?? '',
        'inventoryOwnerId': allocation['staffId'] ?? '',
        'itemId': itemId,
        'name': allocation['name'] ?? item['categoryName'] ?? 'Item',
        'variant': item['name'] ?? item['variant'] ?? 'Item',
        'isCoffee': false,
        'isBundle': false,
      };
      choices[staffRefundItemKey(choice)] = choice;
    }
  }
  return choices;
}

Set<String> activeStaffRefundItemKeys(
  Iterable<Map<String, dynamic>> inventory, {
  DateTime? now,
}) => activeStaffRefundChoices(inventory, now: now).keys.toSet();

DateTime? staffRefundSaleDate(Map<String, dynamic> sale) {
  final raw = sale['timestamp'] ?? sale['createdAt'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw?.toString() ?? '');
}

bool staffRefundWindowOpen(Map<String, dynamic> sale, {DateTime? now}) {
  final soldAt = staffRefundSaleDate(sale);
  if (soldAt == null) return false;
  final age = (now ?? DateTime.now()).difference(soldAt);
  return !age.isNegative && age < const Duration(hours: 5);
}

bool staffRefundAllowedByWindow(
  Map<String, dynamic> sale, {
  required bool byReceiptId,
  DateTime? now,
}) => byReceiptId || staffRefundWindowOpen(sale, now: now);

double staffRefundAmount(List<Map<String, dynamic>> lines, int quantity) {
  var remaining = quantity;
  var amount = 0.0;
  for (final line in lines) {
    if (remaining <= 0) break;
    final available = line['available'] as int;
    final count = remaining < available ? remaining : available;
    amount += (line['unit'] as num).toDouble() * count;
    remaining -= count;
  }
  return amount;
}

List<Map<String, dynamic>> staffRefundReceiptDetails(
  Map<String, dynamic> sale,
  List<Map<String, dynamic>> refundableLines,
  Set<String> activeInventoryKeys, {
  DateTime? now,
  bool allowOlderSale = false,
}) {
  final linesByIndex = <int, Map<String, dynamic>>{
    for (final line in refundableLines)
      if (line['index'] is int) line['index'] as int: line,
  };
  final items = (sale['items'] as List? ?? []).whereType<Map>().toList();
  final subtotal = (sale['subtotal'] as num?)?.toDouble() ?? 0;
  final total = (sale['total'] as num?)?.toDouble() ?? subtotal;
  final ratio = subtotal > 0 ? total / subtotal : 1.0;
  final withinRefundWindow =
      allowOlderSale || staffRefundWindowOpen(sale, now: now);
  return [
    for (var index = 0; index < items.length; index++)
      () {
        final item = Map<String, dynamic>.from(items[index]);
        final line = linesByIndex[index];
        final active = activeInventoryKeys.contains(staffRefundItemKey(item));
        final refundableQuantity = active && line != null
            ? (line['available'] ?? 0)
            : 0;
        return {
          'item': item,
          'quantity': item['quantity'] ?? 0,
          'unit': ((item['price'] as num?)?.toDouble() ?? 0) * ratio,
          'refundableQuantity': refundableQuantity,
          'status': !active
              ? 'No longer currently allocated'
              : !withinRefundWindow
              ? 'Outside refund window'
              : line == null
              ? 'Already refunded'
              : 'Refundable',
        };
      }(),
  ];
}

Future<void> showStaffRefundDialog(
  BuildContext context,
  String uid, {
  List<String> inventoryOwnerIds = const [],
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _StaffRefundDialog(uid: uid, inventoryOwnerIds: inventoryOwnerIds),
);

class _StaffRefundDialog extends StatefulWidget {
  const _StaffRefundDialog({
    required this.uid,
    required this.inventoryOwnerIds,
  });
  final String uid;
  final List<String> inventoryOwnerIds;
  @override
  State<_StaffRefundDialog> createState() => _StaffRefundDialogState();
}

class _StaffRefundDialogState extends State<_StaffRefundDialog> {
  final _receipt = TextEditingController(),
      _reason = TextEditingController(),
      _qty = TextEditingController(text: '1');
  final _service = LocalDatabaseSyncService();
  List<Map<String, dynamic>> _records = [];
  String _source = 'Categories', _error = '';
  String? _selected, _refundMethod;
  Set<String> _activeInventoryKeys = {};
  Map<String, Map<String, dynamic>> _activeInventoryChoices = {};
  bool _loading = true, _saving = false;
  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _kind(Map item) => item['isBundle'] == true
      ? 'Bundle'
      : item['isCoffee'] == true
      ? 'Beverages'
      : 'Categories';
  String _key(Map item) => staffRefundItemKey(item);
  String _label(Map item) => [
    item['name'],
    item['variant'],
    item['coffeeSize'],
  ].where((v) => v != null && '$v'.isNotEmpty).join(' / ');
  bool _refund(Map row) =>
      '${row['type']}'.toLowerCase() == 'refund' ||
      '${row['status']}'.toLowerCase() == 'refund';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _service.getCachedCollection('completed_sales');
    final activeChoices = await _loadActiveInventoryChoices();
    if (mounted) {
      setState(() {
        _records = cached.where((r) => r['userId'] == widget.uid).toList();
        _activeInventoryChoices = activeChoices;
        _activeInventoryKeys = activeChoices.keys.toSet();
        _loading = false;
      });
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('completed_sales')
          .where('userId', isEqualTo: widget.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      await _service.mergeCompletedSales(
        snapshot.docs.map((d) => {...d.data(), '_localDocId': d.id}),
      );
      final records = await _service.getCachedCollection('completed_sales');
      if (mounted && !_saving)
        setState(
          () => _records = records
              .where((r) => r['userId'] == widget.uid)
              .toList(),
        );
    } catch (_) {
      /* Cached receipts remain usable offline. */
    }
  }

  Future<Map<String, Map<String, dynamic>>>
  _loadActiveInventoryChoices() async {
    final owners = <String>{
      widget.uid,
      ...widget.inventoryOwnerIds,
    }.where((id) => id.trim().isNotEmpty).toList();
    final cached = await _service.getCachedCollection('staff_inventory');
    final cachedRows = cached
        .where((row) => owners.contains(row['staffId']?.toString()))
        .toList();
    try {
      final rows = <Map<String, dynamic>>[];
      for (var start = 0; start < owners.length; start += 10) {
        final batch = owners.skip(start).take(10).toList();
        final snapshot = await FirebaseFirestore.instance
            .collection('staff_inventory')
            .where('staffId', whereIn: batch)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
        rows.addAll(
          snapshot.docs.map((doc) => {...doc.data(), '_localDocId': doc.id}),
        );
      }
      await _service.cacheStaffInventorySnapshot(owners, rows);
      return activeStaffRefundChoices(rows);
    } catch (_) {
      return activeStaffRefundChoices(cachedRows);
    }
  }

  List<Map<String, dynamic>> _lines({bool allowOlderSales = false}) {
    final lines = <Map<String, dynamic>>[];
    for (final sale in _records.where(
      (r) =>
          !_refund(r) &&
          r['fullyRefunded'] != true &&
          staffRefundAllowedByWindow(r, byReceiptId: allowOlderSales),
    )) {
      final items = (sale['items'] as List? ?? []).whereType<Map>().toList();
      for (var i = 0; i < items.length; i++) {
        final item = Map<String, dynamic>.from(items[i]);
        var refunded = 0;
        for (final refund in _records.where(_refund)) {
          if (refund['source'] == 'Receipt ${sale['salesId']}') {
            refunded = _num(item['quantity']).toInt();
            break;
          }
          if (refund['originalSalesId'] != sale['salesId']) continue;
          for (final returned
              in (refund['items'] as List? ?? []).whereType<Map>()) {
            if (returned['originalItemIndex'] == i)
              refunded += _num(returned['quantity']).toInt();
          }
        }
        final available = _num(item['quantity']).toInt() - refunded;
        if (available <= 0) continue;
        final subtotal = _num(sale['subtotal']);
        final ratio = subtotal > 0 ? _num(sale['total']) / subtotal : 1.0;
        lines.add({
          'sale': sale,
          'item': item,
          'index': i,
          'available': available,
          'unit': _num(item['price']) * ratio,
        });
      }
    }
    return lines;
  }

  String _receiptDateTime(Map<String, dynamic> sale) {
    final soldAt = staffRefundSaleDate(sale);
    if (soldAt == null) return 'Date and time not recorded';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(soldAt)} • ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(soldAt), alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat)}';
  }

  bool _validateRefund(List<Map<String, dynamic>> lines, bool byReceipt) {
    if (lines.isEmpty) {
      setState(() {
        _error = byReceipt
            ? 'Receipt not found, already refunded, or no longer currently allocated.'
            : 'No purchases found for this allocated item.';
      });
      return false;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a refund reason.');
      return false;
    }
    if (_refundMethod == null) {
      setState(() => _error = 'Choose a refund method.');
      return false;
    }
    final requested = byReceipt
        ? lines.fold<int>(0, (sum, line) => sum + (line['available'] as int))
        : int.tryParse(_qty.text) ?? 0;
    final available = lines.fold<int>(
      0,
      (sum, line) => sum + (line['available'] as int),
    );
    if (requested <= 0 || requested > available) {
      setState(() => _error = 'Enter quantity from 1 to $available.');
      return false;
    }
    return true;
  }

  Future<void> _consumeReplacementInventory(
    List<Map<String, dynamic>> lines,
    int requested,
  ) async {
    var remaining = requested;
    final operations = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (remaining <= 0) break;
      final available = line['available'] as int;
      final count = remaining < available ? remaining : available;
      if (count <= 0) continue;
      final item = line['item'] as Map<String, dynamic>;
      final choice = _activeInventoryChoices[_key(item)];
      final docId =
          '${item['staffInventoryDocId'] ?? choice?['staffInventoryDocId'] ?? choice?['_localDocId'] ?? ''}';
      if (docId.isEmpty) {
        throw StateError('Could not find the current staff inventory item.');
      }
      operations.add({
        'docId': docId,
        'item': item,
        'count': count,
        'kind': _kind(item),
      });
      remaining -= count;
    }
    if (remaining > 0) {
      throw StateError('The selected replacement quantity is not available.');
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final operation in operations) {
      grouped
          .putIfAbsent(operation['docId'] as String, () => [])
          .add(operation);
    }
    final db = FirebaseFirestore.instance;
    final refs = {
      for (final id in grouped.keys)
        id: db.collection('staff_inventory').doc(id),
    };
    await db.runTransaction((transaction) async {
      final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in refs.entries) {
        snapshots[entry.key] = await transaction.get(entry.value);
      }
      final updates = <String, Map<String, dynamic>>{};
      for (final entry in grouped.entries) {
        final snapshot = snapshots[entry.key]!;
        final data = snapshot.data();
        if (data == null || data['isDeleted'] == true) {
          throw StateError('A replacement item is no longer available.');
        }
        final updated = Map<String, dynamic>.from(data);
        for (final operation in entry.value) {
          final item = operation['item'] as Map<String, dynamic>;
          final count = operation['count'] as int;
          final kind = operation['kind'] as String;
          if (kind == 'Bundle') {
            final bundleCount = _num(updated['bundleCount']).toInt();
            final instances = (updated['bundleInstances'] as List? ?? [])
                .whereType<Map>()
                .map((instance) => Map<String, dynamic>.from(instance))
                .toList();
            if (availableBundleStock(updated) < count || bundleCount < count) {
              throw StateError('Not enough bundle stock for replacement.');
            }
            var marked = 0;
            for (
              var index = 0;
              index < instances.length && marked < count;
              index++
            ) {
              if (!bundleInstanceAvailable(instances[index], updated)) continue;
              instances[index] = {
                ...instances[index],
                'status': 'replacement',
                'replacementAt': Timestamp.now(),
              };
              marked++;
            }
            if (instances.isNotEmpty && marked < count) {
              throw StateError('Not enough available bundle instances.');
            }
            updated['bundleCount'] = bundleCount - count;
            if (instances.isNotEmpty) updated['bundleInstances'] = instances;
          } else if (kind == 'Beverages') {
            final sizes = (updated['sizes'] as List? ?? [])
                .whereType<Map>()
                .map((size) => Map<String, dynamic>.from(size))
                .toList();
            final sizeName = '${item['coffeeSize'] ?? item['variant'] ?? ''}';
            final sizeIndex = sizes.indexWhere(
              (size) => '${size['name'] ?? ''}' == sizeName,
            );
            if (sizeIndex >= 0 && sizes[sizeIndex].containsKey('stock')) {
              final stock = _num(sizes[sizeIndex]['stock']).toInt();
              if (stock < count) {
                throw StateError('Not enough beverage stock for replacement.');
              }
              sizes[sizeIndex]['stock'] = stock - count;
              updated['sizes'] = sizes;
            } else if (updated['stock'] != null ||
                updated['startingStock'] != null) {
              final stock = _num(
                updated['stock'] ?? updated['startingStock'],
              ).toInt();
              if (stock < count) {
                throw StateError('Not enough beverage stock for replacement.');
              }
              updated['stock'] = stock - count;
            } else {
              throw StateError(
                'This beverage has no tracked stock. Choose Cash refund instead.',
              );
            }
          } else {
            final itemId = '${item['itemId'] ?? item['id'] ?? ''}';
            final stockItems = (updated['items'] as List? ?? [])
                .map((raw) => raw is Map ? Map<String, dynamic>.from(raw) : raw)
                .toList();
            final index = stockItems.indexWhere(
              (raw) =>
                  raw is Map &&
                  '${raw['id'] ?? raw['itemId'] ?? raw['variantId'] ?? ''}' ==
                      itemId,
            );
            if (index < 0 || stockItems[index] is! Map) {
              throw StateError('The replacement item is no longer allocated.');
            }
            final stockItem = Map<String, dynamic>.from(
              stockItems[index] as Map,
            );
            final stock = _num(
              stockItem['stock'] ?? stockItem['startingStock'],
            ).toInt();
            if (stock < count) {
              throw StateError('Not enough item stock for replacement.');
            }
            stockItems[index] = {...stockItem, 'stock': stock - count};
            updated['items'] = stockItems;
          }
        }
        updates[entry.key] = updated;
      }
      for (final entry in updates.entries) {
        transaction.update(refs[entry.key]!, {
          ...entry.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    final cached = await _service.getCachedCollection('staff_inventory');
    for (final id in refs.keys) {
      final current = (await refs[id]!.get()).data();
      if (current == null) continue;
      final index = cached.indexWhere((row) => row['_localDocId'] == id);
      final updated = {...current, '_localDocId': id};
      if (index >= 0) {
        cached[index] = updated;
      } else {
        cached.add(updated);
      }
    }
    await _service.cacheCollectionDocs('staff_inventory', cached);
  }

  Future<void> _confirmRefund(
    List<Map<String, dynamic>> lines,
    bool byReceipt,
  ) async {
    if (_saving || !_validateRefund(lines, byReceipt)) return;
    final quantity = byReceipt
        ? lines.fold<int>(0, (sum, line) => sum + (line['available'] as int))
        : int.parse(_qty.text);
    final amount = staffRefundAmount(lines, quantity);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm refund?'),
        content: Text(
          _refundMethod == 'inventory'
              ? 'Replace $quantity item${quantity == 1 ? '' : 's'} from current staff inventory?'
              : 'Return ₱${amount.toStringAsFixed(2)} for $quantity item${quantity == 1 ? '' : 's'}? This amount will be deducted from the staff cash drawer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Proceed refund'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save(lines, byReceipt);
  }

  Future<void> _save(List<Map<String, dynamic>> lines, bool byReceipt) async {
    if (_saving) return;
    if (!_validateRefund(lines, byReceipt)) return;
    final requested = byReceipt
        ? lines.fold<int>(0, (sum, l) => sum + (l['available'] as int))
        : int.tryParse(_qty.text) ?? 0;
    final available = lines.fold<int>(
      0,
      (sum, l) => sum + (l['available'] as int),
    );
    if (requested <= 0 || requested > available) {
      setState(() => _error = 'Enter quantity from 1 to $available.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      if (_refundMethod == 'inventory') {
        await _consumeReplacementInventory(lines, requested);
      }
      var remaining = requested;
      for (final line in lines) {
        if (remaining == 0) break;
        final count = remaining < (line['available'] as int)
            ? remaining
            : line['available'] as int;
        final sale = line['sale'] as Map<String, dynamic>;
        final item = line['item'] as Map<String, dynamic>;
        final amount = (line['unit'] as double) * count;
        final id =
            'R-${DateTime.now().microsecondsSinceEpoch}-${line['index']}';
        final cashRefund = _refundMethod == 'cash';
        final refundValue = cashRefund ? amount : 0.0;
        await _service.recordCompletedSale({
          'salesId': id,
          'userId': widget.uid,
          'branchId': sale['branchId'],
          'originalSalesId': sale['salesId'],
          'source': 'Receipt item',
          'type': 'refund',
          'status': 'Refund',
          'refundMethod': _refundMethod,
          'reason': _reason.text.trim(),
          'subtotal': -refundValue,
          'total': -refundValue,
          if (!cashRefund) 'replacementValue': amount,
          'discount': 0.0,
          'discountType': 'None',
          'paidAmount': 0.0,
          'change': 0.0,
          'paymentMode': cashRefund ? 'Cash' : 'Inventory replacement',
          'cashDrawerDelta': cashRefund ? -amount : 0.0,
          'timestamp': DateTime.now(),
          'items': [
            {
              ...item,
              'quantity': count,
              'price': line['unit'],
              'originalItemIndex': line['index'],
            },
          ],
        });
        remaining -= count;
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final message = _refundMethod == 'inventory'
            ? 'Item replacement recorded successfully.'
            : 'Cash refund recorded successfully.';
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      final saved = await _service.getCachedCollection('completed_sales');
      if (mounted)
        setState(() {
          _records = saved.where((row) => row['userId'] == widget.uid).toList();
          _error = 'Unable to save refund: $e';
          _saving = false;
        });
    }
  }

  @override
  void dispose() {
    _receipt.dispose();
    _reason.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byReceipt = _receipt.text.trim().isNotEmpty;
    final searchedReceiptId = _receipt.text.trim().toLowerCase();
    final all = _lines(allowOlderSales: byReceipt)
        .where(
          (line) => _activeInventoryKeys.contains(_key(line['item'] as Map)),
        )
        .toList();
    Map<String, dynamic>? searchedSale;
    if (byReceipt) {
      for (final record in _records) {
        if ('${record['salesId'] ?? ''}'.trim().toLowerCase() ==
            searchedReceiptId) {
          searchedSale = record;
          break;
        }
      }
    }
    final searchedReceiptLines = searchedSale == null
        ? <Map<String, dynamic>>[]
        : _lines(allowOlderSales: true)
              .where(
                (line) =>
                    '${(line['sale'] as Map)['salesId'] ?? ''}'
                        .trim()
                        .toLowerCase() ==
                    searchedReceiptId,
              )
              .toList();
    final choices = Map<String, Map<String, dynamic>>.fromEntries(
      _activeInventoryChoices.entries.where(
        (entry) => _kind(entry.value) == _source,
      ),
    );
    if (!choices.containsKey(_selected)) _selected = null;
    final lines = all
        .where(
          (line) => byReceipt
              ? (line['sale'] as Map)['salesId'].toString().toLowerCase() ==
                    _receipt.text.trim().toLowerCase()
              : _selected != null && _key(line['item'] as Map) == _selected,
        )
        .toList();
    final showItemSelector = !byReceipt;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF791637),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_return_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Refund',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _receipt,
                enabled: !_saving,
                onChanged: (_) => setState(() => _error = ''),
                decoration: const InputDecoration(
                  labelText: 'Search receipt ID',
                  hintText: 'Paste receipt ID to fill items and quantities',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              if (byReceipt && searchedSale != null) ...[
                const SizedBox(height: 14),
                _receiptDetailsCard(
                  searchedSale,
                  staffRefundReceiptDetails(
                    searchedSale,
                    searchedReceiptLines,
                    _activeInventoryKeys,
                    allowOlderSale: true,
                  ),
                ),
              ],
              if (byReceipt &&
                  searchedReceiptId.isNotEmpty &&
                  searchedSale == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _loading
                        ? 'Searching saved receipts...'
                        : 'No receipt found with that ID.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (!byReceipt) ...[
                DropdownButtonFormField<String>(
                  value: _source,
                  decoration: const InputDecoration(labelText: 'Source'),
                  items: ['Categories', 'Bundle', 'Beverages']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _source = v!;
                          _selected = null;
                          _error = '';
                        }),
                ),
                if (showItemSelector) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: switch (_source) {
                        'Beverages' => 'Beverage size',
                        'Bundle' => 'Bundle items',
                        _ => 'Item',
                      },
                    ),
                    items: choices.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              _label(e.value),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                            _selected = v;
                            _error = '';
                          }),
                  ),
                ],
                TextField(
                  controller: _qty,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF2C2C8)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFFB3263E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error,
                          style: const TextStyle(color: Color(0xFF9E1B32)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _refundMethod,
                decoration: const InputDecoration(
                  labelText: 'Refund method',
                  prefixIcon: Icon(Icons.swap_horiz_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'inventory',
                    child: Text('Replace from inventory'),
                  ),
                  DropdownMenuItem(value: 'cash', child: Text('Cash refund')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _refundMethod = value;
                        _error = '';
                      }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed:
              _saving ||
                  (!byReceipt && _selected == null) ||
                  _refundMethod == null
              ? null
              : () => _confirmRefund(lines, byReceipt),
          icon: const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Saving...' : 'Confirm refund'),
        ),
      ],
    );
  }

  Widget _receiptMetaRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _receiptDetailsCard(
    Map<String, dynamic> sale,
    List<Map<String, dynamic>> details,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF9FA),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF0CDD6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 19,
              color: Color(0xFFB7194B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${sale['salesId']}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '₱${_num(sale['total']).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const Divider(height: 18),
        _receiptMetaRow('Purchased', _receiptDateTime(sale)),
        _receiptMetaRow(
          'Payment method',
          '${sale['paymentMode'] ?? sale['paymentMethod'] ?? 'Not recorded'}',
        ),
        _receiptMetaRow(
          'Customer paid',
          '₱${_num(sale['paidAmount']).toStringAsFixed(2)}',
        ),
        _receiptMetaRow(
          'Change',
          '₱${_num(sale['change']).toStringAsFixed(2)}',
        ),
        _receiptMetaRow(
          'Discount',
          _num(sale['discount']) > 0
              ? '${sale['discountType'] ?? 'Discount'} • ₱${_num(sale['discount']).toStringAsFixed(2)}'
              : 'None',
        ),
        for (final detail in details) ...[
          const Divider(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(detail['item'] as Map),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Bought: ${detail['quantity']}  •  ₱${(detail['unit'] as double).toStringAsFixed(2)} each',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${detail['status']}',
                    style: TextStyle(
                      color: detail['status'] == 'Refundable'
                          ? const Color(0xFF25824A)
                          : Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if ((detail['refundableQuantity'] as int) > 0)
                    Text('Qty: ${detail['refundableQuantity']}'),
                ],
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
