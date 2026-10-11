import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/login_validation.dart';

void main() {
  group('login input validation', () {
    test('requires credentials with the requested messages', () {
      expect(loginInputError('', ''), 'Please enter your email and password.');
      expect(loginInputError('', 'secret'), 'Email address is required.');
      expect(loginInputError('admin@example.com', ''), 'Password is required.');
      expect(loginInputError('   ', '   '), 'This field cannot be empty.');
    });

    test('validates email addresses and keeps account ID login compatible', () {
      expect(
        loginInputError('not-an-email', 'secret'),
        'Please enter a valid email address.',
      );
      expect(loginInputError('person@example.com', 'secret'), isNull);
      expect(loginInputError('STF-123', 'secret'), isNull);
      expect(loginInputError('ADM-0001', 'secret'), isNull);
    });
  });

  group('login account status messages', () {
    test('returns exact deactivated and suspended messages', () {
      expect(
        loginAccountStatusError({'status': 'deactivated'}),
        'Your account has been deactivated. Please contact your administrator.',
      );
      expect(
        loginAccountStatusError({'status': 'temporarily_suspended'}),
        'Your account is temporarily suspended. Please contact your administrator.',
      );
      expect(loginAccountStatusError({'status': 'accepted'}), isNull);
      expect(invalidLoginCredentialsMessage(), 'Invalid email or password.');
    });
  });
}
