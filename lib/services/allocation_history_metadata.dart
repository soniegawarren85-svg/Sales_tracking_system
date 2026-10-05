import 'package:cloud_firestore/cloud_firestore.dart';
import 'allocation_checklist_service.dart';
import 'session_actor.dart';

/// Reads legacy assignment quantities without replacing them with current stock.
class AllocationHistoryMetadata {
  AllocationHistoryMetadata(this.db);
  final FirebaseFirestore db;
  final _documents = <String, Future<Map<String, dynamic>>>{};
  final _names = <String, Future<String>>{};
  final _adminIdsByName = <String, Future<String>>{};

  Future<Map<String, dynamic>> _document(String path) => _documents.putIfAbsent(
    path,
    () async => (await db.doc(path).get()).data() ?? {},
  );

  Future<Map<String, dynamic>> resolve(Map<String, dynamic> record) async {
    final result = Map<String, dynamic>.from(record);
    var savedName = _first(record, [
      'allocatedByName',
      'assignedByName',
      'adminName',
      'createdByName',
    ]);
    var identity = _first(record, [
      'allocatedBy',
      'assignedBy',
      'adminId',
      'createdBy',
    ]);
    var adminId = _first(record, [
      'allocatedByAdminId',
      'allocatedByPublicId',
      'adminPublicId',
    ]);
    var branchCode = _first(record, ['branchCode', 'branchPublicId']);
    // A history row may only reference the original delivery's allocator.
    final allocationId = '${record['allocationId'] ?? ''}'.trim();
    if (identity.isEmpty &&
        allocationId.isNotEmpty &&
        !allocationId.contains('/')) {
      final delivery = await _document('allocation_checklist/$allocationId');
      if (delivery['staffId'] == record['staffId'] &&
          delivery['kind'] != 'return') {
        identity = _first(delivery, [
          'allocatedBy',
          'assignedBy',
          'adminId',
          'createdBy',
        ]);
        if (adminId.isEmpty) {
          adminId = _first(delivery, [
            'allocatedByAdminId',
            'allocatedByPublicId',
            'adminPublicId',
          ]);
        }
        if (savedName.isEmpty) {
          savedName = _first(delivery, [
            'allocatedByName',
            'assignedByName',
            'adminName',
            'createdByName',
          ]);
        }
      }
    }
    if (identity.isEmpty && adminId.isEmpty && savedName.isNotEmpty) {
      final normalizedName = savedName.toLowerCase();
      adminId = await _adminIdsByName.putIfAbsent(normalizedName, () async {
        final profiles = await db
            .collection('staff_requests')
            .where('role', isEqualTo: 'admin')
            .get();
        final matches = profiles.docs
            .where(
              (profile) =>
                  accountFullName(profile.data()).toLowerCase() ==
                  normalizedName,
            )
            .toList();
        if (matches.length != 1) return '';
        return _first(matches.single.data(), ['adminId', 'publicId']);
      });
    }
    final branchIdentity = _first(record, ['branchId', 'staffId']);
    if (branchCode.isEmpty && branchIdentity.isNotEmpty) {
      final branch = await _document('branches/$branchIdentity');
      branchCode = _first(branch, ['branchCode', 'publicId']);
    }
    if (branchCode.isNotEmpty) result['branchCode'] = branchCode;
    final profileIdentity = identity.isNotEmpty ? identity : adminId;
    if (profileIdentity.isNotEmpty) {
      final profile = await findAccountProfile(db, profileIdentity);
      final profileData = profile?.data() ?? {};
      final name = await _names.putIfAbsent(profileIdentity, () async {
        return accountFullName(profileData);
      });
      if (identity.isNotEmpty) result['allocatedBy'] = identity;
      result['allocatedByName'] = name.isNotEmpty
          ? name
          : (savedName.isNotEmpty ? savedName : profileIdentity);
      adminId = adminId.isNotEmpty
          ? adminId
          : _first(profileData, ['adminId', 'publicId']);
      if (adminId.isNotEmpty) result['allocatedByAdminId'] = adminId;
    } else if (savedName.isNotEmpty) {
      result['allocatedByName'] = savedName;
    } else {
      result.remove('allocatedByName');
    }
    if (AllocationChecklistService.rows(record['items']).isNotEmpty) {
      return result;
    }
    final quantities = record['quantities'] is Map
        ? record['quantities'] as Map
        : const {};
    final items = <Map<String, dynamic>>[];
    for (final entry in quantities.entries) {
      final count = AllocationChecklistService.quantity(entry.value);
      if (count <= 0) continue;
      final parts = '${entry.key}'.split('::');
      if (parts.length != 2 ||
          parts.first.isEmpty ||
          parts.first.contains('/')) {
        continue;
      }
      final parent = await _document('sales_inventory/${parts.first}');
      final variants = AllocationChecklistService.rows(parent['items']);
      final index = int.tryParse(parts.last);
      Map<String, dynamic> item = {};
      if (parts.last == 'bundle') {
        item = {...parent, 'isBundle': true};
      } else if (index != null && index >= 0 && index < variants.length) {
        item = variants[index];
      } else {
        for (final variant in variants) {
          if ([
            'id',
            'itemId',
            'variantId',
            'publicId',
          ].any((key) => '${variant[key]}' == parts.last)) {
            item = variant;
            break;
          }
        }
      }
      items.add({
        ...item,
        'name':
            item['name'] ??
            (parts.last == 'bundle' ? 'Bundle' : 'Item ${parts.last}'),
        if (parts.last != 'bundle') 'categoryName': parent['name'],
        'sourceInventoryId': parts.first,
        'quantity': count,
      });
    }
    // Older assignments store beverage permissions separately from quantities.
    for (final field in ['coffeeProductIds', 'addonIds']) {
      final ids = record[field];
      if (ids is! List) continue;
      for (final id in ids) {
        if ('$id'.isEmpty || '$id'.contains('/')) continue;
        final coffee = field == 'coffeeProductIds';
        final item = await _document(
          '${coffee ? 'coffee_products' : 'coffee_addons'}/$id',
        );
        items.add({
          ...item,
          'name': item['name'] ?? '$id',
          'isCoffee': coffee,
          'isAddon': !coffee,
        });
      }
    }
    if (items.isNotEmpty) result['items'] = items;
    return result;
  }

  String _first(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = '${data[key] ?? ''}'.trim();
      if (value.isNotEmpty &&
          !['not recorded', 'unknown', 'n/a'].contains(value.toLowerCase())) {
        return value;
      }
    }
    return '';
  }
}
