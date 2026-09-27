int stockNumber(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

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
      (sum, line) => sum + stockNumber(line['quantity']),
    );
    result['bundleCount'] = (stockNumber(data['bundleCount']) - quantity).clamp(
      0,
      1 << 31,
    );
    var remaining = quantity;
    result['bundleInstances'] = (data['bundleInstances'] as List? ?? [])
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, dynamic>.from(raw);
          if (remaining > 0 && (item['status'] ?? 'available') == 'available') {
            remaining--;
            item['status'] = 'sold';
            item['salesId'] = saleId;
          }
          return item;
        })
        .toList();
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
        items[index]['stock'] =
            (stockNumber(
                      items[index]['stock'] ?? items[index]['startingStock'],
                    ) -
                    stockNumber(line['quantity']))
                .clamp(0, 1 << 31);
      } else if (data['isCoffee'] == true && data.containsKey('stock')) {
        result['stock'] =
            (stockNumber(result['stock']) - stockNumber(line['quantity']))
                .clamp(0, 1 << 31);
      }
    }
    result['items'] = items;
  }
  result['appliedSaleIds'] = [...applied, saleId];
  return result;
}
