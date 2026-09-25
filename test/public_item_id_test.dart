import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/public_item_id.dart';

void main() {
  test('numeric IDs remain unchanged', () {
    expect(
      publicItemId('VAR-1788168154682000-069154'),
      'VAR-1788168154682000-069154',
    );
    expect(publicItemId('COF-123'), 'COF-123');
  });
  test('legacy auto IDs receive stable case-sensitive numeric codes', () {
    final upper = publicItemId('VAR-Abcdefghijklmnopqrst');
    final lower = publicItemId('VAR-abcdefghijklmnopqrst');
    expect(upper, matches(RegExp(r'^VAR-\d+$')));
    expect(upper, isNot(lower));
    expect(upper, publicItemId('VAR-Abcdefghijklmnopqrst'));
  });
}
