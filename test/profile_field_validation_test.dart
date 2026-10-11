import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/profile_field_validation.dart';

void main() {
  group('ProfileFieldValidation', () {
    test('rejects numbers and special characters in names', () {
      expect(ProfileFieldValidation.name('Warren2'), isNotNull);
      expect(ProfileFieldValidation.name('Warren-Soniega'), isNotNull);
      expect(ProfileFieldValidation.name('Warren )'), isNotNull);
      expect(ProfileFieldValidation.name('José Soniega'), isNull);
      expect(ProfileFieldValidation.name('', required: false), isNull);
    });

    test('limits free-text fields to 20 words', () {
      expect(
        ProfileFieldValidation.wordLimit(List.filled(20, 'word').join(' ')),
        isNull,
      );
      expect(
        ProfileFieldValidation.wordLimit(List.filled(21, 'word').join(' ')),
        isNotNull,
      );
    });

    test('requires a Gmail address', () {
      expect(ProfileFieldValidation.gmail('person@gmail.com'), isNull);
      expect(ProfileFieldValidation.gmail('person@example.com'), isNotNull);
    });

    test('accepts ages from 21 through 50 only', () {
      expect(ProfileFieldValidation.age('21'), isNull);
      expect(ProfileFieldValidation.age('50'), isNull);
      expect(ProfileFieldValidation.age('20'), isNotNull);
      expect(ProfileFieldValidation.age('51'), isNotNull);
    });

    test('requires an 11-digit staff phone number', () {
      expect(ProfileFieldValidation.phone('09123456789'), isNull);
      expect(ProfileFieldValidation.phone('0912345678'), isNotNull);
    });
  });
}
