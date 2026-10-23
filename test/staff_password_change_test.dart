import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/account_password_service.dart';
import 'package:sales_tracking/services/strong_password.dart';

void main() {
  test('suggested passwords include each character group and are unique', () {
    final suggestions = List.generate(20, (_) => generateStrongPassword());
    expect(suggestions.toSet().length, suggestions.length);
    for (final password in suggestions) {
      expect(password.length, 20);
      for (final pattern in [r'[A-Z]', r'[a-z]', r'[0-9]', r'[!@#%*\-_+]']) {
        expect(RegExp(pattern).hasMatch(password), isTrue);
      }
    }
  });
  test(
    'staff record password change rejects wrong password and replaces legacy credentials',
    () async {
      final db = FakeFirebaseFirestore();
      final account = db.collection('staff_requests').doc('staff-1');
      await account.set({'role': 'staff', 'password': 'old-secret'});
      await expectLater(
        changeFirestoreAccountPassword(
          account: account,
          currentPassword: 'incorrect',
          newPassword: 'new-secret',
        ),
        throwsStateError,
      );
      expect((await account.get()).data()!['password'], 'old-secret');
      await changeFirestoreAccountPassword(
        account: account,
        currentPassword: 'old-secret',
        newPassword: 'new-secret',
      );
      final saved = (await account.get()).data()!;
      expect(saved.containsKey('password'), isFalse);
      expect(saved['passwordAuthMode'], 'firestore');
      expect(saved['mustChangePassword'], isFalse);
      expect(saved['passwordChangedAt'], isNotNull);
      expect(await matchesAccountPassword(saved, 'old-secret'), isFalse);
      expect(await matchesAccountPassword(saved, 'new-secret'), isTrue);
    },
  );
}
