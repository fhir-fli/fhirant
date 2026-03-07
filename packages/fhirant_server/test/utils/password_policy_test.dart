import 'package:test/test.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('accepts 12-character password', () {
      expect(PasswordPolicy.validate('abcdefghijkl'), isNull);
    });

    test('rejects 11-character password', () {
      final error = PasswordPolicy.validate('abcdefghijk');
      expect(error, isNotNull);
      expect(error, contains('at least 12'));
    });

    test('rejects empty password', () {
      expect(PasswordPolicy.validate(''), isNotNull);
    });

    test('rejects 129-character password', () {
      final longPassword = 'a' * 129;
      final error = PasswordPolicy.validate(longPassword);
      expect(error, isNotNull);
      expect(error, contains('at most 128'));
    });

    test('accepts 128-character password', () {
      final maxPassword = 'a' * 128;
      expect(PasswordPolicy.validate(maxPassword), isNull);
    });

    test('rejects common password', () {
      final error = PasswordPolicy.validate('password1234');
      expect(error, isNotNull);
      expect(error, contains('too common'));
    });

    test('rejects common password case-insensitively', () {
      final error = PasswordPolicy.validate('PASSWORD1234');
      expect(error, isNotNull);
      expect(error, contains('too common'));
    });

    test('accepts valid non-common 12-char password', () {
      expect(PasswordPolicy.validate('myS3cur3Pass'), isNull);
    });
  });
}
