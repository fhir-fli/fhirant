import 'dart:convert';

import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every route that sets a password refuses one listed in a breach
/// (OWASP ASVS 5.0.0 V6.2.12; REVIEW-2026-10-17), and accepts it as before
/// when the lookup has no answer.
///
/// The two listed passwords are the two the review found accepted, both
/// in Have I Been Pwned (counts 936 and 6,590 on 2026-11-21) and neither
/// in the local list. The lookup here is a stand-in: no test asks Have I
/// Been Pwned (`every_test_server_stays_offline_test.dart`); the real one
/// is `breached_passwords_test.dart`'s.
void main() {
  const listed = {'Summer2024!!', 'Welcome2024!'};
  var answer = true;
  final asked = <String>[];
  Future<bool?> lookup(String password) async {
    asked.add(password);
    return answer ? listed.contains(password) : null;
  }

  late Handler handler;
  late Future<void> Function() close;

  setUp(() async {
    answer = true;
    asked.clear();
    final s = await createTestServer(breachedPasswords: lookup);
    handler = s.handler;
    close = s.db.close;
  });
  tearDown(() => close());

  Future<(int, Map<String, dynamic>)> send(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final r = await handler(
      testRequest(
        'POST',
        path,
        authToken: token,
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>
    );
  }

  Future<(int, Map<String, dynamic>)> registerFirst(String password) =>
      send('/auth/register', {'username': 'first-admin', 'password': password});

  group('the first registration', () {
    for (final p in listed) {
      test('refuses $p', () async {
        final (s, body) = await registerFirst(p);
        expect(s, 400, reason: '$body');
        expect(body['error'], PasswordPolicy.breachedMessage);
      });
    }

    test('accepts a password the lookup does not list', () async {
      final (s, body) = await registerFirst('k7#Lm2qZx9!w');
      expect(s, anyOf(200, 201), reason: '$body');
      expect(asked, ['k7#Lm2qZx9!w']);
    });

    test('accepts a listed one when the lookup has no answer', () async {
      answer = false;
      final (s, body) = await registerFirst('Summer2024!!');
      expect(s, anyOf(200, 201), reason: '$body');
    });

    test('never asks about a password the local rules refuse', () async {
      final (s, _) = await registerFirst('short');
      expect(s, 400);
      expect(asked, isEmpty);
    });
  });

  test('the owner claim refuses a listed password', () async {
    final (s, body) = await send(
      '/auth/claim',
      {'username': 'anyone', 'new_password': 'Welcome2024!'},
    );
    expect(s, 400, reason: '$body');
    expect(body['error'], PasswordPolicy.breachedMessage);
  });

  test('the password change refuses a listed password', () async {
    const own = 'first-admin-own-1';
    final (s0, first) = await registerFirst(own);
    expect(s0, anyOf(200, 201), reason: '$first');
    final token = (first['token'] ?? first['access_token']) as String;
    final (s, body) = await send(
      '/auth/password',
      {'current_password': own, 'new_password': 'Summer2024!!'},
      token: token,
    );
    expect(s, 400, reason: '$body');
    expect(body['error'], PasswordPolicy.breachedMessage);
    final (ok, changed) = await send(
      '/auth/password',
      {'current_password': own, 'new_password': 'k7#Lm2qZx9!w'},
      token: token,
    );
    expect(ok, 200, reason: '$changed');
  });
}
