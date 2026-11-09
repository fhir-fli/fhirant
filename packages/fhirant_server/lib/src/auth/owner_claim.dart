import 'dart:convert';
import 'dart:math';

import 'package:fhirant_server/src/utils/password_hasher.dart';

/// How an account an administrator created, or whose password it reset,
/// gets a password nobody but its owner knows (OWASP ASVS 5.0.0, official
/// flat JSON of release v5.0.0_release, verbatim). V6.4.1, L1: "system
/// generated initial passwords or activation codes are securely randomly
/// generated, follow the existing password policy, and expire after a
/// short period of time or after they are initially used. These initial
/// secrets must not be permitted to become the long term password."
/// V6.4.6, L3: "administrative users can initiate the password reset
/// process for the user, but that this does not allow them to change or
/// choose the user's password. This prevents a situation where they know
/// the user's password."
///
/// 1. The administrator creates the account or resets its password. The
///    account's password becomes one nobody holds ([unusablePassword]),
///    every session from before ends, and the account waits for its owner
///    for [ownerWaitLifetime]. The administrator is handed no secret.
/// 2. The owner, on their own device, sends the password they chose to
///    `POST /auth/claim`. The server holds its hash and shows the owner a
///    code ([newClaimCode]).
/// 3. The administrator types the code the owner shows them into
///    `POST /admin/users/<id>/approve`. On a match the held password is the
///    account's; a wrong code drops it, so each code gets one try.
///
/// The code plays the part of the user code in the OAuth 2.0 Device
/// Authorization Grant (RFC 8628): a short code that ties what one device
/// sent to an approval made elsewhere. A first version (2026-11-03) handed
/// the administrator a one-time password instead; holding it, the
/// administrator could set a password of its own choosing.
///
/// What this does not stop: an administrator who sends a password for the
/// account itself and then approves its own code. Only a channel the
/// administrator does not control (Keycloak mails the owner a link) closes
/// that, and fhirant runs on a phone with no such channel. Both steps are
/// in the audit trail, and the owner then cannot sign in. Grey accepted
/// this on 2026-11-09 as part of running on a mobile device.

/// How long an account waits for its owner: Keycloak's default for an
/// action an administrator sends a user (Server Administration Guide, read
/// 2026-11-03, verbatim): "the realm's Default Admin-Initiated Action
/// Lifespan setting, which is 12 hours by default"; "Keep this value long
/// to allow administrators to send e-mails to offline users."
const Duration ownerWaitLifetime = Duration(hours: 12);

/// RFC 8628 §6.1 (rfc-editor.org/rfc/rfc8628.txt, verbatim): "Further
/// removing vowels to avoid randomly creating words results in the base 20
/// character set "BCDFGHJKLMNPQRSTVWXZ"." Typed on a phone with no case or
/// number keys.
const String _alphabet = 'BCDFGHJKLMNPQRSTVWXZ';

/// Significant characters in a code. RFC 8628 §5.1: "an 8-character base
/// 20 user code (with roughly 34.5 bits of entropy)" needs a limit of 5
/// attempts "to get the same 2^-32 probability of success by random
/// guessing"; here each code gets one.
const int _codeLength = 8;

final Random _random = Random.secure();

/// A fresh code, shown as two groups of four, e.g. `WDJB-MJHT` (RFC 8628
/// §6.1's own example shape).
String newClaimCode() {
  final chars = String.fromCharCodes([
    for (var i = 0; i < _codeLength; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);
  return '${chars.substring(0, 4)}-${chars.substring(4)}';
}

/// The code as stored and compared: RFC 8628 §6.1 (verbatim), "the server
/// should strip dashes and other punctuation that it added for readability
/// (making the inclusion of such punctuation by the user optional). For
/// codes using only characters in the A-Z range, as with the base 20
/// charset defined above, the user's input should be uppercased". Null
/// when what is left is not a code.
String? canonicalClaimCode(String input) {
  final kept = input.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
  if (kept.length != _codeLength) return null;
  for (final c in kept.codeUnits) {
    if (!_alphabet.codeUnits.contains(c)) return null;
  }
  return kept;
}

/// A hash and salt of a random secret that is thrown away: what an account
/// waiting for its owner has for a password, so that no password opens it.
Future<({String hash, String salt})> unusablePassword() async {
  final secret = base64Url.encode([
    for (var i = 0; i < 32; i++) _random.nextInt(256),
  ]);
  final salt = PasswordHasher.generateSalt();
  return (hash: await PasswordHasher.hashPassword(secret, salt), salt: salt);
}
