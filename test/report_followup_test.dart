import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/admin_message_preview.dart';

void main() {
  test('preview lists five real contacts even with no conversations', () {
    final contacts = messagePreviewContacts('admin', [
      {'_id': 'admin', 'name': 'Admin'},
      {'_id': 'rejected', 'status': 'rejected'},
      for (var i = 0; i < 8; i++)
        {
          '_id': 's$i',
          'firstName': 'Staff',
          'lastName': '$i',
          'status': 'accepted',
        },
    ], []);
    expect(contacts, hasLength(5));
    expect(contacts.first['name'], 'Staff 0');
    expect(contacts.first['lastMessage'], 'Start a conversation');
  });
  test(
    'closing remains unavailable before 7 PM and opens exactly at closing',
    () {
      final start = DateTime(2026, 9, 27), end = DateTime(2026, 9, 28);
      expect(
        reportClosingAvailable(start, end, DateTime(2026, 9, 27, 18, 59)),
        isFalse,
      );
      expect(
        reportClosingAvailable(start, end, DateTime(2026, 9, 27, 19)),
        isTrue,
      );
      expect(
        reportClosingAvailable(start, end, DateTime(2026, 9, 28, 10)),
        isTrue,
      );
      expect(
        reportClosingAvailable(
          start,
          DateTime(2026, 10),
          DateTime(2026, 9, 27, 18),
        ),
        isFalse,
      );
    },
  );
  test(
    'current inventory excludes old expiry, old removals and zero assignment records',
    () {
      final data = BranchReportData({
        'staff_inventory': [
          {
            'staffId': 'b',
            'assignedAt': '2026-09-01',
            'items': [
              {
                'id': 'old',
                'name': 'Old expired',
                'stock': 4,
                'expirationDate': '2026-09-10',
              },
              {
                'id': 'active',
                'name': 'Carry-over',
                'stock': 8,
                'assignedStartingStock': 10,
                'expirationDate': '2026-10-10',
              },
              {'id': 'sold-out', 'name': 'Empty', 'stock': 0},
            ],
          },
          {
            'staffId': 'b',
            'assignedAt': '2026-09-01',
            'isDeleted': true,
            'deletedAt': '2026-09-12',
            'items': [
              {'id': 'removed', 'stock': 3},
            ],
          },
        ],
        'staff_inventory_history': [
          {
            'staffId': 'b',
            'createdAt': '2026-09-27',
            'quantities': {'cat::ghost': 0},
          },
        ],
      });
      final today = data.items(
        'b',
        DateTime(2026, 9, 27),
        DateTime(2026, 9, 28),
      );
      expect(today.map((row) => row['id']), ['active']);
      expect(today.single['allocated'], 10);
      final past = data.items(
        'b',
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 11),
      );
      expect(past.any((row) => row['id'] == 'old'), isTrue);
      expect(past.firstWhere((row) => row['id'] == 'old')['status'], 'Expired');
    },
  );
  test(
    'removed inventory variants still resolve their original public code in history',
    () {
      final data = BranchReportData({
        'sales_inventory': [
          {
            '_id': 'cat',
            'items': [],
            'removedItems': [
              {
                'id': 'old',
                'publicId': 'CO-010',
                'name': 'Cookie',
                'removedAt': '2026-09-11',
              },
            ],
          },
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': '2026-09-10',
            'items': [
              {'itemId': 'old', 'quantity': 2},
            ],
          },
        ],
      });
      expect(
        data
            .items('b', DateTime(2026, 9, 10), DateTime(2026, 9, 11))
            .single['id'],
        'CO-010',
      );
      expect(
        data.items('b', DateTime(2026, 9, 27), DateTime(2026, 9, 28)),
        isEmpty,
      );
    },
  );
}
