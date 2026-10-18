import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';

AdminCatalogEntry entry(String type, int stock) => AdminCatalogEntry(
  id: '$type-$stock',
  name: type,
  type: type,
  source: const {},
  details: const {},
  images: const [],
  stock: stock,
);

void main() {
  test('low-stock threshold is 20 for bundles and 50 for categories', () {
    expect(catalogLowStock(entry('Bundle', 20)), isTrue);
    expect(catalogLowStock(entry('Bundle', 21)), isFalse);
    expect(catalogLowStock(entry('Categories', 50)), isTrue);
    expect(catalogLowStock(entry('Categories', 51)), isFalse);
    expect(inventoryLowStock(20, type: 'Bundle'), isTrue);
    expect(inventoryLowStock(21, type: 'Bundle'), isFalse);
    expect(inventoryLowStock(50, type: 'Categories'), isTrue);
    expect(inventoryLowStock(51, type: 'Categories'), isFalse);
  });
}
