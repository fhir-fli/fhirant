import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'a-strong-test-secret-value-000000000000000000';
  final service = JwtService(secret);

  group('JwtService round-trip', () {
    test('a token it signs verifies and carries its claims', () {
      final token = service.generateToken(
        subject: 'k7',
        scopes: ['system/*.*'],
        generation: 2,
      );
      final payload = service.verifyAccessToken(token);
      expect(payload, isNotNull);
      expect(payload!['sub'], 'k7');
      expect(payload['scope'], 'system/*.*');
      expect(payload['gen'], 2);
    });

    test('a token signed with a different secret is rejected', () {
      final token = JwtService('some-other-secret').generateToken(subject: 'k');
      expect(service.verifyToken(token), isNull);
    });
  });

  // RFC 9068 §2.2 (rfc-editor.org txt, read 2026-11-21) lists iss, exp,
  // aud, sub, client_id, iat and jti as REQUIRED; §4: the resource server
  // "MUST verify that the "typ" header value is "at+jwt"", the "iss" "MUST
  // exactly match", and a token whose "aud" does not contain this server
  // "MUST be rejected".
  group('RFC 9068 claims and checks', () {
    const base = 'https://fhirant.example:8080';
    final issuing = JwtService(secret, issuer: base);

    test('a token names its account by sub and says nothing else about it', () {
      final claims = JWT.decode(service.generateToken(subject: 'k')).payload
          as Map<String, dynamic>;
      expect(claims['sub'], 'k');
      for (final gone in ['userId', 'username', 'role', 'patient']) {
        expect(claims, isNot(contains(gone)), reason: gone);
      }
      expect(claims.keys, containsAll(<String>['exp', 'iat', 'jti']));
    });

    test('an access token is typ at+jwt, a refresh token is not', () {
      expect(
        JWT.decode(service.generateToken(subject: 'k')).header!['typ'],
        accessTokenType,
      );
      expect(
        JWT.decode(service.generateRefreshToken(subject: 'k')).header!['typ'],
        'JWT',
      );
    });

    test('a token without typ at+jwt is no access token', () {
      final plain = JWT({'sub': 'k', 'gen': 0})
          .sign(SecretKey(secret), expiresIn: const Duration(hours: 1));
      expect(service.verifyToken(plain), isNotNull, reason: 'control');
      expect(service.verifyAccessToken(plain), isNull);
    });

    test('a refresh-shaped token with typ at+jwt is no refresh token', () {
      final wrong = JWT(
        {'sub': 'k', 'gen': 0, 'token_type': 'refresh'},
        header: {'typ': accessTokenType},
      ).sign(SecretKey(secret), expiresIn: const Duration(hours: 1));
      expect(service.verifyRefreshToken(wrong), isNull);
    });

    test('a token with no sub is refused', () {
      final token = JWT({'gen': 0}, header: {'typ': accessTokenType})
          .sign(SecretKey(secret), expiresIn: const Duration(hours: 1));
      expect(service.verifyAccessToken(token), isNull);
    });

    test('with an issuer, iss and aud are it, and client_id is carried', () {
      final claims = JWT
          .decode(issuing.generateToken(subject: 'k', clientId: 'app'))
          .payload as Map<String, dynamic>;
      expect(claims['iss'], base);
      expect(claims['aud'], base);
      expect(claims['client_id'], 'app');
      expect(
        JWT.decode(issuing.generateRefreshToken(subject: 'k')).payload['iss'],
        base,
      );
    });

    test('with an issuer, its own tokens pass', () {
      expect(
        issuing.verifyAccessToken(issuing.generateToken(subject: 'k')),
        isNotNull,
      );
      expect(
        issuing.verifyRefreshToken(issuing.generateRefreshToken(subject: 'k')),
        isNotNull,
      );
    });

    test("with an issuer, another server's token is refused", () {
      final other = JwtService(secret, issuer: 'https://other.example');
      expect(
        issuing.verifyAccessToken(other.generateToken(subject: 'k')),
        isNull,
      );
      expect(
        issuing.verifyRefreshToken(other.generateRefreshToken(subject: 'k')),
        isNull,
      );
      // No iss at all: a server with no issuer signed it.
      expect(
        issuing.verifyAccessToken(service.generateToken(subject: 'k')),
        isNull,
      );
    });

    test('with an issuer, an aud list must contain it', () {
      String withAud(Object aud) => JWT(
            {'sub': 'k', 'gen': 0, 'iss': base, 'aud': aud},
            header: {'typ': accessTokenType},
          ).sign(SecretKey(secret), expiresIn: const Duration(hours: 1));
      expect(issuing.verifyAccessToken(withAud([base, 'x'])), isNotNull);
      expect(issuing.verifyAccessToken(withAud(['x'])), isNull);
      expect(issuing.verifyAccessToken(withAud('x')), isNull);
    });

    test('without an issuer, neither iss nor aud is written', () {
      final claims = JWT.decode(service.generateToken(subject: 'k')).payload
          as Map<String, dynamic>;
      expect(claims, isNot(contains('iss')));
      expect(claims, isNot(contains('aud')));
      expect(claims, isNot(contains('client_id')));
    });
  });

  group('algorithm pinning (HS256 only)', () {
    // Builds a token header.payload with the given alg and signature segment,
    // without going through the library's signer.
    String forge(String alg, String signature) {
      String seg(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final header = seg({'alg': alg, 'typ': accessTokenType});
      final payload = seg({'sub': 'k'});
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

  group('a token must carry exp (RFC 9068 §2.2, §4)', () {
    // Signed with the server's own secret, so only the claim differs.
    String signedWith(
      Map<String, dynamic> claims, {
      Duration? expiresIn,
      String typ = accessTokenType,
    }) =>
        JWT(claims, header: {'typ': typ})
            .sign(SecretKey(secret), expiresIn: expiresIn);
    final access = {'sub': 'k', 'gen': 0};
    final refresh = {...access, 'token_type': 'refresh'};

    test('control: the same claims with a future exp verify', () {
      final token = signedWith(access, expiresIn: const Duration(hours: 1));
      expect(service.verifyToken(token), isNotNull);
      expect(service.verifyAccessToken(token), isNotNull);
      expect(
        service.verifyRefreshToken(
          signedWith(
            refresh,
            expiresIn: const Duration(hours: 1),
            typ: 'JWT',
          ),
        ),
        isNotNull,
      );
    });

    test('an access token with no exp is refused', () {
      final token = signedWith(access);
      expect(JWT.decode(token).payload, isNot(contains('exp')));
      expect(service.verifyToken(token), isNull);
      expect(service.verifyAccessToken(token), isNull);
    });

    test('a refresh token with no exp is refused', () {
      expect(
        service.verifyRefreshToken(signedWith(refresh, typ: 'JWT')),
        isNull,
      );
    });

    test('a past exp is refused', () {
      final token = signedWith(access, expiresIn: const Duration(seconds: -5));
      expect(service.verifyToken(token), isNull);
    });

    test('every token the service mints carries exp', () {
      final t1 = service.generateToken(subject: 'k');
      final t2 = service.generateRefreshToken(subject: 'k');
      for (final t in [t1, t2]) {
        expect(JWT.decode(t).payload['exp'], isA<int>());
      }
    });
  });

  group('refresh tokens', () {
    test('a refresh token is recognised, an access token is not', () {
      final refresh = service.generateRefreshToken(subject: 'k3');
      final access = service.generateToken(subject: 'k3');
      expect(service.verifyRefreshToken(refresh), isNotNull);
      expect(service.verifyRefreshToken(access), isNull);
      expect(service.verifyAccessToken(refresh), isNull);
    });
  });
}
