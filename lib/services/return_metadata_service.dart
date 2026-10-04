import 'package:cloud_firestore/cloud_firestore.dart';
import 'allocation_checklist_service.dart';
import 'public_item_id.dart';
import 'return_batch_service.dart';

/// Resolves historical records without changing their quantities or identity.
class ReturnMetadataService {
  ReturnMetadataService(this.db);
  final FirebaseFirestore db;
  final _profiles = <String, Future<Map<String, dynamic>>>{};
  final _documents = <String, Future<Map<String, dynamic>>>{};
  Future<List<Map<String, dynamic>>>? _catalog;

  Future<Map<String, dynamic>> document(String path) => _documents.putIfAbsent(
    path,
    () async => (await db.doc(path).get()).data() ?? {},
  );

  static String normalized(dynamic value) =>
      '$value'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static String displayCode(Map data) {
    for (final key in [
      'itemDisplayId',
      'publicId',
      'itemPublicId',
      'bundleId',
      'coffeeId',
      'addonId',
      'id',
      'itemId',
      'variantId',
    ]) {
      final value = '${data[key] ?? ''}'.trim();
      final match = RegExp(r'^([A-Z]{2,5})-(\d{1,4})$').firstMatch(value);
      if (match != null && match[1] != 'CAT') {
        return '${match[1]}-${int.parse(match[2]!).toString().padLeft(3, '0')}';
      }
    }
    return '';
  }

  Future<Map<String, dynamic>> profile(String identity) =>
      _profiles.putIfAbsent(identity, () async {
        if (identity.isEmpty) return {};
        final collection = db.collection('staff_requests');
        Map<String, dynamic>? data;
        if (!identity.contains('@')) {
          data = (await collection.doc(identity).get()).data();
        }
        if (data == null) {
          final results = await collection
              .where(
                identity.contains('@') ? 'email' : 'staffId',
                isEqualTo: identity,
              )
              .limit(2)
              .get();
          if (results.docs.length == 1) data = results.docs.single.data();
        }
        if (data == null) return {};
        final name = [
          data['firstName'],
          data['middleName'],
          data['lastName'],
        ].map((v) => '${v ?? ''}'.trim()).where((v) => v.isNotEmpty).join(' ');
        return {
          'name': returnText([name, data['fullName'], data['name']], ''),
          'staffId': publicItemId(
            returnText([data['staffId'], data['publicId']], ''),
          ),
        };
      });

  Future<List<Map<String, dynamic>>> catalog() => _catalog ??= () async {
    final result = <Map<String, dynamic>>[];
    await Future.wait(
      ['sales_inventory', 'coffee_products', 'coffee_addons'].map((
        collection,
      ) async {
        final docs = await db.collection(collection).get();
        for (final doc in docs.docs) {
          final data = doc.data();
          final bundle =
              data['isBundle'] == true ||
              '${data['bundleId'] ?? ''}'.isNotEmpty;
          final flags = {
            'isBundle': bundle,
            'isCoffee': collection == 'coffee_products',
            'isAddon': collection == 'coffee_addons',
            '_rootId': doc.id,
          };
          if (bundle || collection != 'sales_inventory') {
            result.add({...data, 'id': data['id'] ?? doc.id, ...flags});
          } else {
            for (final item in AllocationChecklistService.rows(data['items'])) {
              result.add({...item, ...flags});
            }
          }
        }
      }),
    );
    return result;
  }();

  Future<String> itemCode(Map<String, dynamic> item) async =>
      '${(await resolve(item))['itemDisplayId']}';

  Future<Map<String, dynamic>> resolve(Map<String, dynamic> record) async {
    final collection = record['returnSourceCollection'] ?? record['collection'];
    final sourceId = record['returnSourceId'] ?? record['id'];
    Map<String, dynamic> source = {};
    if ([
          'completed_sales',
          'stock_adjustments',
          'staff_inventory',
        ].contains(collection) &&
        sourceId != null) {
      try {
        source = await document('$collection/$sourceId');
      } catch (_) {}
    }
    final original = Map<String, dynamic>.from(
      record['sourceItem'] as Map? ?? {},
    );
    if (collection == 'completed_sales') {
      final rows = AllocationChecklistService.rows(source['items']);
      final line = int.tryParse('${record['returnLineKey'] ?? record['line']}');
      if (line != null && line >= 0 && line < rows.length)
        original.addAll(rows[line]);
    } else {
      original.addAll(source);
    }
    final product = {...record, ...original};
    // Document IDs belong to a return transaction, not a product.
    if (collection != null && original['id'] == null) product.remove('id');
    final inventoryId = returnText([
      original['categoryId'],
      record['sourceInventoryId'],
      original['sourceInventoryId'],
    ], '');
    Map<String, dynamic> allocation = {};
    if (inventoryId.isNotEmpty) {
      try {
        allocation = await document('staff_inventory/$inventoryId');
      } catch (_) {}
    }
    final name = returnItemName(product);
    final identities = [
      product['itemId'],
      product['variantId'],
      original['id'],
      product['publicId'],
      product['itemPublicId'],
    ].where((v) => v != null && '$v'.isNotEmpty).map((v) => '$v').toSet();
    List<Map<String, dynamic>> entries = [];
    try {
      entries = await catalog();
    } catch (_) {}
    bool identityMatch(Map entry) => [
      entry['id'],
      entry['itemId'],
      entry['variantId'],
      entry['publicId'],
    ].any((v) => v != null && identities.contains('$v'));
    var matches = entries.where(identityMatch).toList();
    if (matches.isEmpty)
      matches = entries
          .where((e) => normalized(returnItemName(e)) == normalized(name))
          .toList();
    final root =
        allocation['sourceInventoryId'] ?? original['sourceInventoryId'];
    final scoped = matches.where((e) => e['_rootId'] == root).toList();
    if (scoped.isNotEmpty) matches = scoped;
    final codes = matches.map(displayCode).where((v) => v.isNotEmpty).toSet();
    final resolved = codes.length == 1
        ? matches.firstWhere((e) => displayCode(e) == codes.single)
        : <String, dynamic>{};
    final stockMatches = AllocationChecklistService.rows(allocation['items'])
        .where(
          (e) =>
              identityMatch(e) ||
              normalized(returnItemName(e)) == normalized(name),
        )
        .toList();
    final stock = stockMatches.length == 1 ? stockMatches.single : allocation;
    final code = returnText([
      displayCode(resolved),
      displayCode(stock),
      displayCode(product),
      displayCode(record),
    ], '--');
    final expiry =
        product['expirationDate'] ??
        product['expiryDate'] ??
        stock['expirationDate'] ??
        resolved['expirationDate'];
    Map<String, dynamic> staff = {};
    for (final id in [
      source['userId'],
      original['userId'],
      source['staffId'],
      record['sourceStaffUid'],
      record['userId'],
      record['submittedBy'],
      record['sourceStaffName'],
      record['staffName'],
      record['submittedByName'],
    ]) {
      if (id == null || '$id'.isEmpty || '$id' == '${record['branchId']}')
        continue;
      try {
        staff = await profile('$id');
      } catch (_) {
        continue;
      }
      if (staff.isNotEmpty) break;
    }
    final typeData = {
      ...product,
      'isBundle':
          resolved['isBundle'] == true ||
          allocation['isBundle'] == true ||
          product['isBundle'] == true ||
          code.startsWith('BND-') ||
          '${source['type']}'.contains('bundle'),
      'isCoffee':
          resolved['isCoffee'] == true ||
          allocation['isCoffee'] == true ||
          product['isCoffee'] == true ||
          code.startsWith('CF-'),
      'isAddon':
          resolved['isAddon'] == true ||
          product['isAddon'] == true ||
          code.startsWith('AD-'),
    };
    return {
      ...record,
      'name': name,
      'itemDisplayId': code,
      'sourceStaffName': returnText([
        staff['name'],
        record['sourceStaffName'],
        record['staffName'],
        record['submittedByName'],
      ]),
      'sourceStaffId': returnText([
        staff['staffId'],
        record['sourceStaffId'],
        record['staffPublicId'],
        record['submittedByStaffId'],
      ]),
      'expirationDate': expiry,
      for (final flag in ['isBundle', 'isCoffee', 'isAddon'])
        flag: typeData[flag],
    };
  }
}
