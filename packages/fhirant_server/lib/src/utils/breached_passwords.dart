import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:http/http.dart' as http;

/// Whether a password is listed in a set of breached passwords
/// (OWASP ASVS 5.0.0 V6.2.12, L2: "passwords submitted during account
/// registration or password changes are checked against a set of breached
/// passwords"; REVIEW-2026-10-17).
///
/// `true` listed, `false` not listed, `null` no answer (offline, a timeout,
/// an error). No answer never refuses a password: the password policy's
/// own list still applies (Grey 2026-11-21).
typedef BreachedPasswordLookup = Future<bool?> Function(String password);

/// Have I Been Pwned's Pwned Passwords range API.
const hibpRangeBase = 'https://api.pwnedpasswords.com/range/';

/// How long the lookup waits for an answer.
const hibpTimeout = Duration(seconds: 3);

/// Asks Have I Been Pwned whether [password] is in its breach corpus.
///
/// Only the first 5 hex characters of the password's SHA-1 leave this
/// process (`GET /range/<prefix>`); the answer lists every hash suffix with
/// that prefix and its count, and the match is made here. `Add-Padding:
/// true` makes every answer 800-1,000 rows, so its size says nothing about
/// the prefix; padded rows have count 0 and are not matches. The API needs
/// no key and attribution is not required; the user agent names the
/// application, as the API asks (haveibeenpwned.com/API/v3, read
/// 2026-11-21).
Future<bool?> hibpBreachLookup(
  String password, {
  http.Client? client,
  Duration timeout = hibpTimeout,
}) async {
  final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
  final prefix = hash.substring(0, 5);
  final suffix = hash.substring(5);
  final c = client ?? http.Client();
  try {
    final response = await c.get(
      Uri.parse('$hibpRangeBase$prefix'),
      headers: const {
        'Add-Padding': 'true',
        'User-Agent': 'fhirant-password-check',
      },
    ).timeout(timeout);
    if (response.statusCode != 200) {
      FhirantLogging().logWarning(
        'Breached-password lookup answered ${response.statusCode}; '
        'the local list alone was checked',
      );
      return null;
    }
    return listsSuffix(response.body, suffix);
  } on Object catch (e) {
    FhirantLogging().logWarning(
      'Breached-password lookup unavailable (${e.runtimeType}); '
      'the local list alone was checked',
    );
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Whether a range answer ([body]: `SUFFIX:COUNT` lines) lists [suffix]
/// with a count above 0. A row with count 0 is padding.
bool listsSuffix(String body, String suffix) {
  for (final line in const LineSplitter().convert(body)) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.substring(0, colon).trim().toUpperCase() != suffix) continue;
    final count = int.tryParse(line.substring(colon + 1).trim()) ?? 0;
    return count > 0;
  }
  return false;
}
