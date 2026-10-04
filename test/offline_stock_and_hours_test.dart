import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/sale_stock.dart';
import 'package:sales_tracking/services/analytics_hours.dart';
import 'package:sales_tracking/services/public_item_id.dart';
import 'package:sales_tracking/services/database_backup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sales_tracking/services/local_write_lock.dart';

void main() {
  test(
    'concurrent local saves preserve both records and recover after failure',
    () async {
      final lock = LocalWriteLock();
      var value = <int>[];
      Future<void> append(int id) => lock.run(() async {
        final copy = List<int>.from(value);
        await Future<void>.delayed(Duration.zero);
        copy.add(id);
        value = copy;
      });
      await Future.wait([append(1), append(2)]);
      expect(value, [1, 2]);
      await expectLater(
        lock.run<void>(() async {
          throw StateError('disk error');
        }),
        throwsStateError,
      );
      await append(3);
      expect(value, [1, 2, 3]);
    },
  );
  test('retrying a saved sale never consumes stock twice', () {
    final stock = <String, dynamic>{
      'items': [
        {'id': 'a', 'name': 'Cookie', 'stock': 10},
        {'id': 'b', 'stock': 7},
      ],
    };
    final lines = <Map<String, dynamic>>[
      {'itemId': 'a', 'quantity': 3},
    ];
    final updated = applySaleStock(stock, 'receipt-1', lines);
    expect((updated['items'] as List).first['stock'], 7);
    expect((updated['items'] as List).last['stock'], 7);
    expect(applySaleStock(updated, 'receipt-1', lines), updated);
    expect((stock['items'] as List).first['stock'], 10);
  });
  test('bundle sale marks only available instances and survives replay', () {
    final stock = <String, dynamic>{
      'isBundle': true,
      'bundleCount': 2,
      'bundleInstances': [
        {'status': 'sold'},
        {'status': 'available'},
        {'status': 'available'},
      ],
    };
    final lines = <Map<String, dynamic>>[
      {'quantity': 1},
    ];
    final updated = applySaleStock(stock, 'receipt-2', lines);
    expect(updated['bundleCount'], 1);
    expect((updated['bundleInstances'] as List)[1]['salesId'], 'receipt-2');
    expect((updated['bundleInstances'] as List)[2]['status'], 'available');
    expect(applySaleStock(updated, 'receipt-2', lines)['bundleCount'], 1);
  });
  test('no sale lines leave unrelated allocations unchanged', () {
    final stock = <String, dynamic>{'items': []};
    expect(applySaleStock(stock, 'receipt-1', []), stock);
  });
  test('all 24 hours remain visible on every selected date', () {
    final dates = [
      DateTime(2026, 9, 26, 9),
      DateTime(2026, 9, 26, 22),
      DateTime(2026, 9, 25, 7),
    ];
    expect(
      analyticsHours(DateTime(2026, 9, 26), dates),
      List.generate(24, (hour) => hour),
    );
    expect(
      analyticsHours(DateTime(2026, 9, 27), dates),
      List.generate(24, (hour) => hour),
    );
  });
  test(
    'staff display removes excess zero padding without changing receipt IDs',
    () {
      expect(publicItemId('STF-0001'), 'STF-001');
      expect(publicItemId('S-20260926-083012-123'), 'S-20260926-083012-123');
    },
  );
  test('backup preserves timestamp precision and nested values', () {
    final time = Timestamp(1700000000, 123456789);
    final encoded = DatabaseBackup.encode({
      'timestamp': time,
      'items': [
        {'quantity': 2},
      ],
      'deleted': false,
    });
    final decoded =
        DatabaseBackup.decode(jsonDecode(jsonEncode(encoded))) as Map;
    expect(decoded['timestamp'], time);
    expect(decoded['items'], [
      {'quantity': 2},
    ]);
    expect(decoded['deleted'], false);
  });
  test('restore validates the entire file before any write', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'sales-tracking-backup',
          'version': 1,
          'documents': {'unknown/document': {}},
        }),
      ),
    );
    expect(() => DatabaseBackup.validate(bytes), throwsFormatException);
  });
}
