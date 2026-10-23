import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:sales_tracking/services/profile_email.dart';

void main() {
  test('confirmed address stays visible while the new address is pending', () {
    final data = <String, dynamic>{
      'email': 'new@example.com',
      'authEmail': 'old@example.com',
      'pendingAuthEmail': 'new@example.com',
    };
    expect(confirmedProfileEmail(data), 'old@example.com');
    data['email'] = data['authEmail'] = 'new@example.com';
    data.remove('pendingAuthEmail');
    expect(confirmedProfileEmail(data), 'new@example.com');
    expect(
      confirmedProfileEmail({'email': 'legacy@example.com'}),
      'legacy@example.com',
    );
  });
  test('linked accounts bypass stale stored-password authentication', () {
    for (final data in [
      {'passwordAuthMode': 'firebase'},
      {'authEmail': 'a@example.com', 'passwordAuthMode': 'firestore'},
      {'pendingAuthEmail': 'b@example.com', 'password': 'old'},
    ]) {
      expect(usesLinkedAuthentication(data), isTrue);
    }
    expect(
      usesLinkedAuthentication({'passwordAuthMode': 'firestore'}),
      isFalse,
    );
  });
  test(
    'email collision checks exclude own and removed records, include other roles',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/self').set({'email': 'own@example.com'});
      await db.doc('staff_requests/removed').set({
        'email': 'free@example.com',
        'isVoided': true,
      });
      await db.doc('staff_requests/admin').set({
        'email': 'ADMIN@example.com',
        'role': 'admin',
      });
      await db.doc('staff_requests/staff').set({
        'pendingAuthEmail': 'pending@example.com',
      });
      await db.doc('super_admin_profiles/Spr-001').set({
        'email': 'owner@example.com',
      });
      expect(await profileEmailTaken(db, 'own@example.com', 'self'), isFalse);
      expect(
        await profileEmailTaken(
          db,
          'owner@example.com',
          'Spr-001',
          ownCollection: 'super_admin_profiles',
        ),
        isFalse,
      );
      expect(await profileEmailTaken(db, 'free@example.com', 'self'), isFalse);
      for (final email in [
        'admin@example.com',
        'pending@example.com',
        'owner@example.com',
      ]) {
        expect(await profileEmailTaken(db, email, 'self'), isTrue);
      }
    },
  );
}
