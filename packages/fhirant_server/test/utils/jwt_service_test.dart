import 'dart:convert';

import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'a-strong-test-secret-value-000000000000000000';
  final service = JwtService(secret);

  group('JwtService round-trip', () {
    test('a token it signs verifies and carries its claims', () {
      final token = service.generateToken(
        userId: 7,
        username: 'operator',
        role: 'admin',
        scopes: ['system/*.*'],
      );
      final payload = service.verifyToken(token);
      expect(payload, isNotNull);
      expect(payload!['userId'], 7);
      expect(payload['username'], 'operator');
      expect(payload['role'], 'admin');
    });

    test('a token signed with a different secret is rejected', () {
      final token = JwtService('some-other-secret').generateToken(
        userId: 1,
        username: 'x',
        role: 'admin',
      );
      expect(service.verifyToken(token), isNull);
    });
  });

  group('algorithm pinning (HS256 only)', () {
    // Builds a token header.payload with the given alg and signature segment,
    // without going through the library's signer.
    String forge(String alg, String signature) {
      String seg(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final header = seg({'alg': alg, 'typ': 'JWT'});
      final payload = seg({'userId': 1, 'role': 'admin'});
      return '$header.$payload.$signature';
    }

    test('an alg:none token is rejected (no signature)', () {
      // The classic forgery: alg none, empty signature.
      expect(service.verifyToken(forge('none', '')), isNull);
    });

    test('a token declaring a non-HS256 algorithm is rejected', () {
      // Even with a plausible-looking signature segment, the header alg is
      // checked and rejected before verification.
      expect(service.verifyToken(forge('HS512', 'AAAA')), isNull);
      expect(service.verifyToken(forge('RS256', 'AAAA')), isNull);
    });

    test('malformed tokens are rejected, not thrown', () {
      expect(service.verifyToken('not-a-jwt'), isNull);
      expect(service.verifyToken('only.two'), isNull);
      expect(service.verifyToken(''), isNull);
    });
  });

  group('refresh tokens', () {
    test('a refresh token is recognised, an access token is not', () {
      final refresh = service.generateRefreshToken(
        userId: 3,
        username: 'operator',
        role: 'admin',
      );
      final access = service.generateToken(
        userId: 3,
        username: 'operator',
        role: 'admin',
      );
      expect(service.verifyRefreshToken(refresh), isNotNull);
      expect(service.verifyRefreshToken(access), isNull);
    });
  });
}
