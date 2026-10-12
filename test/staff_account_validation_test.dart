import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Admin_pages/Admin/StaffPage.dart';

void main() {
  test('staff names allow letters and spaces only', () {
    expect(validateStaffName('Angel Marie'), isNull);
    expect(validateStaffName('Angel1'), isNotNull);
    expect(validateStaffName('Angel!'), isNotNull);
    expect(validateStaffName(''), isNotNull);
    expect(validateStaffName('', isRequired: false), isNull);
  });

  test('staff age must be between 20 and 50 inclusive', () {
    expect(validateStaffAge('20'), isNull);
    expect(validateStaffAge('50'), isNull);
    expect(validateStaffAge('19'), isNotNull);
    expect(validateStaffAge('51'), isNotNull);
  });

  test('staff phone and email formats are validated', () {
    expect(validateStaffPhone('09123456789'), isNull);
    expect(validateStaffPhone('0912345678'), isNotNull);
    expect(validateStaffEmail('staff@example.com'), isNull);
    expect(validateStaffEmail('staff.example.com'), isNotNull);
  });

  test('password needs seven characters and number plus uppercase or symbol', () {
    expect(validateStaffPassword('Pass123'), isNull);
    expect(validateStaffPassword('pass!23'), isNull);
    expect(validateStaffPassword('Pass12'), isNotNull);
    expect(validateStaffPassword('Password'), isNotNull);
    expect(validateStaffPassword('password1'), isNotNull);
    expect(validateStaffPassword('password 1'), isNotNull);
  });

  test('confirmation rejects a password mismatch', () {
    expect(validateStaffPasswordConfirmation('Pass123', 'Pass123'), isNull);
    expect(
      validateStaffPasswordConfirmation('Other123', 'Pass123'),
      isNotNull,
    );
  });
}
