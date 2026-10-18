import 'package:fhirant_server/src/utils/common_passwords.g.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordPolicy', () {
    test('accepts 12-character password', () {
      expect(PasswordPolicy.validate(r'k7#Lm2$qZx9!'), isNull);
    });

    // REVIEW-2026-10-17 finding 18: these three were accepted when the list
    // held 20 entries (measured over HTTP, asvs_probes.tsv); they are in
    // the NCSC and Pwdb lists (common_passwords.g.dart).
    for (final common in [
      'qwertyuiopasdfgh',
      '1qaz2wsx3edc4rfv',
      'Q1W2E3R4T5Y6',
    ]) {
      test('rejects the common password $common', () {
        expect(PasswordPolicy.validate(common), contains('too common'));
      });
    }

    test('the list holds at least the 3000 ASVS V6.2.4 asks for', () {
      expect(commonPasswordList.length, greaterThanOrEqualTo(3000));
      expect(
        commonPasswordList.every((p) => p.length >= 12 && p.length <= 128),
        isTrue,
      );
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
