import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// Registered apps (schema 32): an administrator names each one and every
/// address it may be sent back to (OWASP ASVS 5.0.0 V10.4.1).
void main() {
  late FhirAntDb db;
  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });
  tearDown(() => db.close());

  test('register, list, change, remove', () async {
    expect(await db.getOAuthClients(), isEmpty);
    await db.putOAuthClient(
      'scarab',
      name: 'Scarab',
      redirectUris: ['http://127.0.0.1/cb', 'com.example.scarab:/cb'],
    );
    var app = (await db.getOAuthClient('scarab'))!;
    expect(app.name, 'Scarab');
    expect(app.redirectUris, ['com.example.scarab:/cb', 'http://127.0.0.1/cb']);

    await db.putOAuthClient(
      'scarab',
      name: 'Scarab EHR',
      redirectUris: ['http://127.0.0.1/cb'],
    );
    app = (await db.getOAuthClient('scarab'))!;
    expect(app.name, 'Scarab EHR');
    expect(app.redirectUris, ['http://127.0.0.1/cb'], reason: 'replaced');

    expect(await db.isOAuthClientRegistered('scarab'), isTrue);
    expect(await db.isOAuthClientRegistered('other'), isFalse);

    await db.deleteOAuthClient('scarab');
    expect(await db.getOAuthClient('scarab'), isNull);
    expect(await db.isOAuthClientRegistered('scarab'), isFalse);
    final left = await db
        .customSelect('SELECT count(*) AS c FROM oauth_client_redirects')
        .getSingle();
    expect(left.read<int>('c'), 0);
  });

  test('removing an app withdraws the codes it holds', () async {
    final user = await db.createUser(
      username: 'someone',
      passwordHash: 'h',
      salt: 's',
    );
    await db.putOAuthClient('app', name: 'App', redirectUris: ['http://a/cb']);
    await db.createAuthorizationCode(
      code: 'code-1',
      clientId: 'app',
      userId: user,
      redirectUri: 'http://a/cb',
      scope: 'user/*.rs',
      codeChallenge: 'x',
      codeChallengeMethod: 'S256',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    await db.deleteOAuthClient('app');
    expect(await db.getAuthorizationCode('code-1'), isNull);
  });
}
