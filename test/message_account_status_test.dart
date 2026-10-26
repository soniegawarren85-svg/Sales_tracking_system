import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/message_account_status.dart';

void main() {
  test('deactivated and disabled accounts are excluded from messaging', () {
    for (final account in [
      {'status': 'deactivated'},
      {'status': 'DEACTIVATED'},
      {'status': 'inactive'},
      {'status': 'disabled'},
      {'status': 'voided'},
      {'isDeactivated': true},
      {'isDeleted': true},
      {'isVoided': true},
      {'isSuspended': true},
      {'isDisabled': true},
    ]) {
      expect(isMessageAccountAvailable(account), isFalse, reason: '$account');
    }
  });

  test('accepted and pending accounts remain available for messaging', () {
    expect(isMessageAccountAvailable({'status': 'accepted'}), isTrue);
    expect(isMessageAccountAvailable({'status': 'pending'}), isTrue);
    expect(isMessageAccountAvailable({}), isTrue);
  });
}
