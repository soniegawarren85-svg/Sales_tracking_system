import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/offline_login.dart';

void main() {
  final staff = <String, dynamic>{
    '_localDocId': 'uid-1',
    'staffId': 'STF-001',
    'role': 'staff',
    'status': 'accepted',
    'loginPassword': 'Secret123',
  };

  test('synced staff can authenticate without a prior online login', () {
    expect(offlineUsernameMatches(staff, 'stf-0001'), isTrue);
    expect(offlineAccountAllowed(staff), isTrue);
    expect(offlineStoredPasswordMatches(staff, 'Secret123'), isTrue);
    expect(offlineStoredPasswordMatches(staff, 'secret123'), isFalse);
    expect(offlineStoredPasswordMatches(staff, ''), isFalse);
    expect(offlineUsernameMatches(staff, 'STF-002'), isFalse);
  });

  test('synced account status prevents offline access', () {
    for (final status in ['pending', 'rejected', 'deactivated', '']) {
      expect(offlineAccountAllowed({...staff, 'status': status}), isFalse);
    }
    expect(offlineAccountAllowed({...staff, 'isVoided': true}), isFalse);
    expect(offlineAccountAllowed({...staff, '_localDocId': ''}), isFalse);
    expect(offlineAccountAllowed({...staff, 'role': 'unknown'}), isFalse);
  });

  test('admin IDs support legacy padding and require valid status', () {
    final admin = {
      ...staff,
      'role': 'admin',
      'adminId': 'ADM-0001',
      'status': '',
    };
    expect(offlineUsernameMatches(admin, 'ADM-001'), isTrue);
    expect(offlineAccountAllowed(admin), isTrue);
    expect(offlineAccountAllowed({...admin, 'status': 'deactivated'}), isFalse);
  });

  test('password changes invalidate legacy passwords and saved versions', () {
    final changed = {...staff, 'credentialsChangedAt': Timestamp(100, 0)};
    expect(offlineStoredPasswordMatches(changed, 'Secret123'), isFalse);
    expect(
      offlineCredentialVersion(changed),
      isNot(offlineCredentialVersion(staff)),
    );
    expect(
      offlineCredentialVersion(changed),
      isNot(
        offlineCredentialVersion({
          ...changed,
          'credentialsChangedAt': Timestamp(101, 0),
        }),
      ),
    );
  });
}
