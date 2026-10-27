import 'package:cloud_firestore/cloud_firestore.dart';

int stockNumber(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

List<Map<String, dynamic>> categorySaleLines(
  Map<String, dynamic> item,
  int quantity,
) {
  var remaining = quantity;
  final sources = (item['categoryInventorySources'] as List? ?? [])
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  if (sources.isEmpty)
    return [
      {...item, 'quantity': quantity},
    ];
  sources.sort((a, b) => '${a['assignedAt']}'.compareTo('${b['assignedAt']}'));
  final lines = <Map<String, dynamic>>[];
  for (final source in sources) {
    final available = stockNumber(source['stock']);
    final used = remaining < available ? remaining : available;
    if (used <= 0) continue;
    lines.add({
      ...item,
      'staffInventoryDocId': source['staffInventoryDocId'],
      'quantity': used,
    });
    remaining -= used;
  }
  if (remaining > 0)
    throw StateError('Stock changed. Refresh the sales screen.');
  return lines;
}

List<Map<String, dynamic>> expandSaleStockLines(
  Iterable<Map<String, dynamic>> lines,
) => lines.expand((line) {
  final allocations =
      (line['stockAllocations'] ?? line['bundleStockAllocations']) as List? ??
      [];
  if (allocations.isEmpty) return [line];
  return allocations.whereType<Map>().map(
    (allocation) => <String, dynamic>{
      ...line,
      ...Map<String, dynamic>.from(allocation),
    },
  );
}).toList();

List<Map<String, dynamic>> bundleSaleLines(
  Map<String, dynamic> item,
  int quantity,
) {
  if (quantity <= 0) return const [];
  final sources = (item['bundleInventorySources'] as List? ?? [])
      .whereType<Map>()
      .map((source) => Map<String, dynamic>.from(source))
      .toList();
  if (sources.isEmpty) {
    return [
      {...item, 'quantity': quantity},
    ];
  }

  DateTime date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value') ?? DateTime(1970);
  }

  final units = <Map<String, dynamic>>[];
  for (final source in sources) {
    final docId = '${source['staffInventoryDocId'] ?? ''}';
    final instances = (source['instances'] as List? ?? [])
        .whereType<Map>()
        .map((instance) => Map<String, dynamic>.from(instance))
        .toList();
    if (instances.isNotEmpty) {
      for (final instance in instances) {
        units.add({
          'docId': docId,
          'instanceId': instance['id'],
          'assignedAt': instance['fifoAt'] ?? instance['assignedAt'],
        });
      }
    } else {
      for (var i = 0; i < stockNumber(source['stock']); i++) {
        units.add({'docId': docId, 'assignedAt': source['assignedAt']});
      }
    }
  }
  units.sort((a, b) {
    final byDate = date(a['assignedAt']).compareTo(date(b['assignedAt']));
    if (byDate != 0) return byDate;
    final byDocument = '${a['docId']}'.compareTo('${b['docId']}');
    return byDocument != 0
        ? byDocument
        : '${a['instanceId']}'.compareTo('${b['instanceId']}');
  });
  if (units.length < quantity) {
    throw StateError('Bundle stock changed. Refresh the sales screen.');
  }

  final countsByDocument = <String, int>{};
  final idsByDocument = <String, List<dynamic>>{};
  for (final unit in units.take(quantity)) {
    final docId = '${unit['docId']}';
    countsByDocument[docId] = (countsByDocument[docId] ?? 0) + 1;
    if (unit['instanceId'] != null) {
      idsByDocument.putIfAbsent(docId, () => []).add(unit['instanceId']);
    }
  }
  return [
    for (final entry in countsByDocument.entries)
      {
        ...item,
        'staffInventoryDocId': entry.key,
        'quantity': entry.value,
        if (idsByDocument[entry.key]?.isNotEmpty == true)
          'bundleInstanceIds': idsByDocument[entry.key],
      },
  ];
}

Map<String, dynamic> applySaleStock(
  Map<String, dynamic> data,
  String saleId,
  List<Map<String, dynamic>> lines,
) {
  if (lines.isEmpty) return data;
  final applied = List<String>.from(data['appliedSaleIds'] as List? ?? []);
  if (applied.contains(saleId)) return data;
  final result = Map<String, dynamic>.from(data);
  if (data['isBundle'] == true) {
    final quantity = lines.fold<int>(
      0,
      (total, line) => total + stockNumber(line['quantity']),
    );
    result['bundleCount'] = (stockNumber(data['bundleCount']) - quantity).clamp(
      0,
      1 << 31,
    );
    final selectedInstances = lines
        .expand((line) => line['bundleInstanceIds'] as List? ?? const [])
        .map((id) => '$id')
        .toSet();
    final instances = (data['bundleInstances'] as List? ?? [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final selectedIndexes = <int>{};
    bool isAvailable(Map<String, dynamic> item) {
      final status = '${item['status'] ?? 'available'}'.toLowerCase();
      return item['isDeleted'] != true &&
          item['isVoided'] != true &&
          (status.isEmpty || status == 'available');
    }

    for (final selectedId in selectedInstances) {
      if (selectedIndexes.length >= quantity) break;
      for (var index = 0; index < instances.length; index++) {
        final item = instances[index];
        if ('${item['id']}' == selectedId &&
            isAvailable(item) &&
            selectedIndexes.add(index)) {
          break;
        }
      }
    }
    for (var index = 0;
        selectedIndexes.length < quantity && index < instances.length;
        index++) {
      if (isAvailable(instances[index])) selectedIndexes.add(index);
    }
    if (instances.isNotEmpty && selectedIndexes.length < quantity) {
      throw StateError('Bundle stock changed before this sale was applied.');
    }
    result['bundleInstances'] = [
      for (var index = 0; index < instances.length; index++)
        if (selectedIndexes.contains(index))
          {
            ...instances[index],
            'status': 'sold',
            'salesId': saleId,
          }
        else
          instances[index],
    ];
  } else {
    final items = (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    for (final line in lines) {
      final wantedId = '${line['itemId'] ?? ''}';
      final index = items.indexWhere(
        (item) => wantedId.isNotEmpty
            ? '${item['id'] ?? item['itemId'] ?? ''}' == wantedId
            : item['name'] == line['variant'] ||
                  item['variant'] == line['variant'],
      );
      if (index >= 0) {
        final available = stockNumber(
          items[index]['stock'] ?? items[index]['startingStock'],
        );
        final quantity = stockNumber(line['quantity']);
        items[index]['stock'] =
            (available - quantity).clamp(0, 1 << 31);
      } else if (data['isCoffee'] == true && data.containsKey('stock')) {
        final available = stockNumber(result['stock']);
        final quantity = stockNumber(line['quantity']);
        result['stock'] =
            (available - quantity).clamp(0, 1 << 31);
      }
    }
    result['items'] = items;
  }
  result['appliedSaleIds'] = [...applied, saleId];
  return result;
}
