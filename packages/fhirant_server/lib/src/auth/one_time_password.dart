import 'dart:math';

import 'package:fhirant_server/src/utils/password_policy.dart';

/// One-time passwords: what an administrator hands a user whose account it
/// created or whose password it reset (OWASP ASVS 5.0.0 V6.4.1, L1, and
/// V6.4.6, L3; asvs 5.0.0 JSON, verbatim): "system generated initial
/// passwords or activation codes are securely randomly generated, follow
/// the existing password policy, and expire after a short period of time
/// or after they are initially used. These initial secrets must not be
/// permitted to become the long term password", and "administrative users
/// can initiate the password reset process for the user, but that this
/// does not allow them to change or choose the user's password".
///
/// The administrator used to choose both, and the user kept what it chose.
/// Now the server makes the password, the administrator reads it once in
/// the reply, and it opens no session: login and authorize refuse it with
/// `password_change_required`, and `POST /auth/password` takes it once to
/// set the user's own. Keycloak does the same (Server Administration
/// Guide, "Setting a password for a user", read 2026-11-03, verbatim): "If
/// Temporary is ON, the user must change the password at the first login."
/// The first administrator still chooses its own: nobody else knows it.

/// How long a one-time password is good for: Keycloak's default for an
/// action an administrator sends a user (Server Administration Guide, read
/// 2026-11-03, verbatim): "the realm's Default Admin-Initiated Action
/// Lifespan setting, which is 12 hours by default"; "Keep this value long
/// to allow administrators to send e-mails to offline users."
const Duration oneTimePasswordLifetime = Duration(hours: 12);

/// Crockford's Base32 alphabet (crockford.com/base32.html): digits and
/// capitals without I, L, O and U, so a password read aloud or copied by
/// hand is not mistaken. 32 symbols, 5 bits each.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

final Random _random = Random.secure();

/// A fresh one-time password: 16 symbols from [_alphabet] (80 random bits),
/// in four groups of four, e.g. `7KQ2-M9XD-4TRB-H0WE`. 19 characters, so it
/// meets [PasswordPolicy]; the check below makes that a fact, not a hope.
String newOneTimePassword() {
  final groups = [
    for (var g = 0; g < 4; g++)
      String.fromCharCodes([
        for (var i = 0; i < 4; i++)
          _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
      ]),
  ];
  final password = groups.join('-');
  final refused = PasswordPolicy.validate(password);
  if (refused != null) throw StateError('one-time password: $refused');
  return password;
}
