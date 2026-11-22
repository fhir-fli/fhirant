import 'dart:async';

import 'package:fhirant_server/src/utils/breached_passwords.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// The Have I Been Pwned range lookup (OWASP ASVS 5.0.0 V6.2.12), against
/// a stand-in for the service shaped like its documented answer
/// (haveibeenpwned.com/API/v3, read 2026-11-21): `SUFFIX:COUNT` lines,
/// CRLF, padding rows with count 0.
void main() {
  // SHA-1 of 'Summer2024!!' is 450FC709DF13DBCC5B1E30C250C467E17CB64D66
  // (sha1sum, 2026-11-21); the live range listed it with count 936.
  const prefix = '450FC';
  const suffix = '709DF13DBCC5B1E30C250C467E17CB64D66';

  test('the stand-in is the password this file says', () async {
    late Uri seen;
    final client = MockClient((r) async {
      seen = r.url;
      return http.Response('', 200);
    });
    await hibpBreachLookup('Summer2024!!', client: client);
    expect(seen.path, '/range/$prefix');
  });

  test('sends 5 characters of the hash, padding asked, a named agent',
      () async {
    late http.Request sent;
    final client = MockClient((r) async {
      sent = r;
      return http.Response('$suffix:936\r\n', 200);
    });
    expect(await hibpBreachLookup('Summer2024!!', client: client), isTrue);
    expect(sent.method, 'GET');
    expect(sent.url.toString(), '$hibpRangeBase$prefix');
    expect(sent.url.toString(), isNot(contains(suffix)));
    expect(sent.url.toString(), isNot(contains('Summer')));
    expect(sent.headers['Add-Padding'], 'true');
    expect(sent.headers['User-Agent'], 'fhirant-password-check');
    expect(sent.body, isEmpty);
  });

  test('a suffix not in the answer is not listed', () async {
    final client = MockClient(
      (_) async =>
          http.Response('0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n', 200),
    );
    expect(await hibpBreachLookup('Summer2024!!', client: client), isFalse);
  });

  test('a padding row (count 0) is not a match', () {
    expect(listsSuffix('$suffix:0\r\nAAAA:3\r\n', suffix), isFalse);
    expect(listsSuffix('AAAA:3\r\n$suffix:2\r\n', suffix), isTrue);
    expect(listsSuffix('${suffix.toLowerCase()}:2', suffix), isTrue);
  });

  group('no answer is null, never a refusal', () {
    test('a non-200 status', () async {
      final client = MockClient((_) async => http.Response('', 503));
      expect(await hibpBreachLookup('Summer2024!!', client: client), isNull);
    });

    test('a network error', () async {
      final client = MockClient((_) async => throw http.ClientException('x'));
      expect(await hibpBreachLookup('Summer2024!!', client: client), isNull);
    });

    test('no answer within the deadline', () async {
      final never = Completer<http.Response>();
      final client = MockClient((_) => never.future);
      final started = DateTime.now();
      expect(
        await hibpBreachLookup(
          'Summer2024!!',
          client: client,
          timeout: const Duration(milliseconds: 50),
        ),
        isNull,
      );
      expect(DateTime.now().difference(started).inSeconds, lessThan(2));
    });
  });

  group('PasswordPolicy.check', () {
    test('refuses what the lookup lists', () async {
      expect(
        await PasswordPolicy.check('Summer2024!!', breached: (_) async => true),
        PasswordPolicy.breachedMessage,
      );
    });

    test('accepts on no answer or no lookup', () async {
      expect(
        await PasswordPolicy.check('Summer2024!!', breached: (_) async => null),
        isNull,
      );
      expect(await PasswordPolicy.check('Summer2024!!'), isNull);
    });

    test('the local rules come first and the lookup is not asked', () async {
      var asked = false;
      final error = await PasswordPolicy.check(
        'password1234',
        breached: (_) async => asked = true,
      );
      expect(error, contains('too common'));
      expect(asked, isFalse);
    });
  });
}
