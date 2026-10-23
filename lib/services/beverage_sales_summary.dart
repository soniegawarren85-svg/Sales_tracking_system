import 'package:cloud_firestore/cloud_firestore.dart';

int beverageSalesToday({
  required Iterable<Map<String, dynamic>> sales,
  required DateTime now,
  required Set<String> branchIds,
  required String coffeeId,
  required String coffeeName,
  required String publicId,
}) {
  final today = DateTime(now.year, now.month, now.day);
  var total = 0;

  for (final sale in sales) {
    final explicitBranchId = sale['branchId']?.toString().trim() ?? '';
    final branchId = explicitBranchId.isNotEmpty
        ? explicitBranchId
        : sale['staffId']?.toString().trim() ?? '';
    if (branchIds.isEmpty || !branchIds.contains(branchId)) continue;

    final timestamp = sale['timestamp'];
    final saleDate = switch (timestamp) {
      Timestamp value => value.toDate().toLocal(),
      DateTime value => value.toLocal(),
      String value => DateTime.tryParse(value)?.toLocal(),
      _ => null,
    };
    if (saleDate == null ||
        saleDate.isBefore(today) ||
        !saleDate.isBefore(today.add(const Duration(days: 1)))) {
      continue;
    }

    final type = sale['type']?.toString().trim().toLowerCase() ?? 'sale';
    final status = sale['status']?.toString().trim().toLowerCase() ?? '';
    if (status.isNotEmpty &&
        status != 'completed' &&
        status != 'refund' &&
        type != 'refund') {
      continue;
    }
    final sign = type == 'refund' || status == 'refund' ? -1 : 1;
    final items = sale['items'];
    if (items is! Iterable) continue;

    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (item['isCoffee'] != true) continue;

      final soldCoffeeId = item['coffeeId']?.toString().trim() ?? '';
      final soldPublicId = item['publicId']?.toString().trim() ?? '';
      final soldName = item['name']?.toString().trim().toLowerCase() ?? '';
      final matches = coffeeId.isNotEmpty
          ? soldCoffeeId == coffeeId ||
                (publicId.isNotEmpty && soldPublicId == publicId)
          : soldName == coffeeName.trim().toLowerCase();
      if (!matches) continue;

      final quantity = item['quantity'] is num
          ? (item['quantity'] as num).toInt()
          : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
      total += sign * quantity;
    }
  }

  return total < 0 ? 0 : total;
}

double beverageSizeSellingPrice(Map<String, dynamic> item) {
  double parse(Object? value) {
    if (value is num) return value.toDouble();
    final normalized = value
        ?.toString()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.-]'), '');
    return double.tryParse(normalized ?? '') ?? 0;
  }

  final price = parse(item['price']);
  if (price > 0) return price;

  final basePrice = parse(item['basePrice']);
  final sizeDelta = parse(item['sizePriceDelta']);
  return basePrice + sizeDelta;
}
