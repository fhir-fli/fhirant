import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fhirant_server/src/utils/pkce.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-17 A16: the verifier honoured `plain` although the
/// authorize endpoint refuses it; now only S256 verifies (RFC 7636 §7.2).
void main() {
  // RFC 7636 appendix B's example, verbatim: verifier
  // dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk, challenge
  // E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM.
  const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  const challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

  test('S256 verifies the RFC 7636 appendix B pair', () {
    expect(
      base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', ''),
      challenge,
      reason: 'the appendix pair is what we think it is',
    );
    expect(
      Pkce.verifyCodeChallenge(
        codeVerifier: verifier,
        codeChallenge: challenge,
        codeChallengeMethod: 'S256',
      ),
      isTrue,
    );
    expect(
      Pkce.verifyCodeChallenge(
        codeVerifier: '${verifier}x',
        codeChallenge: challenge,
        codeChallengeMethod: 'S256',
      ),
      isFalse,
    );
  });

  test('plain never verifies, even when verifier and challenge are equal', () {
    expect(
      Pkce.verifyCodeChallenge(
        codeVerifier: verifier,
        codeChallenge: verifier,
        codeChallengeMethod: 'plain',
      ),
      isFalse,
    );
  });

  test('an unknown method never verifies', () {
    expect(
      Pkce.verifyCodeChallenge(
        codeVerifier: verifier,
        codeChallenge: challenge,
        codeChallengeMethod: 's256',
      ),
      isFalse,
    );
  });
}
