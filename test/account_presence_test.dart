import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/account_presence.dart';

void main() {
  group('account presence labels', () {
    test('respects explicit offline state and elapsed time', () {
      final seenAt = DateTime(2026, 10, 25, 8);
      final account = {
        'isOnline': false,
        'lastLoginAt': DateTime(2026, 10, 25, 11),
        'lastSeenAt': seenAt,
      };

      expect(
        AccountPresenceService.isOnline(
          account,
          now: DateTime(2026, 10, 25, 10),
        ),
        isFalse,
      );
      expect(
        AccountPresenceService.offlineStatus(
          account,
          now: DateTime(2026, 10, 25, 10, 24),
        ),
        'Offline · 2 hours ago',
      );
    });

    test('expires stale online heartbeats', () {
      expect(
        AccountPresenceService.isOnline(
          {
            'isOnline': true,
            'lastSeenAt': DateTime(2026, 10, 25, 8),
          },
          now: DateTime(2026, 10, 25, 8, 4),
        ),
        isFalse,
      );
    });
  });
}
