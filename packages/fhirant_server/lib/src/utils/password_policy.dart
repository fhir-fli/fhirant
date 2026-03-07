/// Password policy based on NIST 800-63B guidelines.
///
/// Emphasizes length over complexity — no mandatory uppercase, digits, or
/// symbols. Rejects a small set of common long passwords.
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 12;
  static const int maxLength = 128;

  /// Common passwords that are 12+ characters. Checked case-insensitively.
  static const _commonPasswords = {
    'password1234',
    'password12345',
    'password123456',
    'passwordpassword',
    'qwertyuiop12',
    'qwerty123456',
    '123456789012',
    '1234567890123',
    'iloveyou1234',
    'changeme1234',
    'letmein12345',
    'welcome12345',
    'admin1234567',
    'trustno12345',
    'monkey1234567',
    'dragon1234567',
    'master1234567',
    'abc123456789',
    'passw0rd1234',
    'aaaaaaaaaaaa',
  };

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
      return 'This password is too common. Please choose a less predictable password.';
    }
    return null;
  }
}
