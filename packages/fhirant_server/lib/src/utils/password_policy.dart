import 'package:fhirant_server/src/utils/common_passwords.g.dart';

/// Password policy based on NIST 800-63B guidelines.
///
/// Emphasizes length over complexity — no mandatory uppercase, digits, or
/// symbols. Rejects the common passwords of the policy's length
/// ([_commonPasswords]).
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 12;
  static const int maxLength = 128;

  /// Common passwords of 12-128 characters, lowercased: the NCSC 100k and
  /// Pwdb top-1M lists (SecLists, MIT) with the 20 this class listed by hand
  /// before, 30,407 in all (common_passwords.g.dart, from
  /// tool/generate_common_passwords.py). OWASP ASVS 5.0.0 V6.2.4 (L1): "at
  /// least, the top 3000 passwords which match the application's password
  /// policy"; the list here held 20 (REVIEW-2026-10-17 finding 18).
  static final Set<String> _commonPasswords = commonPasswordList.toSet();

  /// Validate a password against the policy.
  ///
  /// Returns `null` if the password is valid, or a human-readable error
  /// string explaining why it was rejected.
  static String? validate(String password) {
    if (password.length < minLength) {
      return 'Password must be at least $minLength characters. '
          'Longer passwords are more secure than complex ones.';
    }
    if (password.length > maxLength) {
      return 'Password must be at most $maxLength characters.';
    }
    if (_commonPasswords.contains(password.toLowerCase())) {
      return 'This password is too common. Please choose a less '
          'predictable password.';
    }
    return null;
  }
}
