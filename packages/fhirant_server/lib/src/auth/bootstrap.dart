import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/admin_provisioning.dart';
import 'package:fhirant_server/src/utils/jwt_secret.dart';

/// The first administrator of a headless server (REVIEW-2026-09-17 A15).
///
/// With authentication on and no account in the store, the first
/// `POST /auth/register` from anyone on the network used to become the
/// administrator. The app has no such window: it provisions its
/// administrator locally (`AdminProvisioning`) before it serves. The CLI
/// and the container now have the two ways other servers do this, read at
/// their documentation on 2026-09-19:
///
/// 1. **Seeded from the environment**, as Keycloak's bootstrap admin is
///    (`bootstrap-admin-recovery`, verbatim): "bin/kc.[sh|bat] start
///    --bootstrap-admin-username tmpadm --bootstrap-admin-password pass"
///    and "bin/kc.[sh|bat] bootstrap-admin user --username tmpadm
///    --password:env PASS_VAR". Here: `FHIRANT_ADMIN_USERNAME` and
///    `FHIRANT_ADMIN_PASSWORD`, applied at start by [seedAdminFromEnvironment]
///    through the same [AdminProvisioning] the app uses, so the password
///    policy holds.
/// 2. **A one-time token printed at start**, as Jenkins' initial admin
///    password is (installing/linux, "Unlocking Jenkins", verbatim): "From
///    the Jenkins console log output, copy the automatically generated
///    alphanumeric password", also written to
///    `/var/lib/jenkins/secrets/initialAdminPassword`. Here:
///    [issueBootstrapToken] generates one while the store has no account,
///    writes it owner-readable beside the database, and the CLI logs it.
///    The first registration must present it ([bootstrapTokenHeader] or the
///    `bootstrap_token` body field); a registration without it is 403.
///
/// The token is valid only while the store has no account: once one
/// exists, registration needs an administrator's token, and the file is
/// removed at the next start.

/// The request header carrying the bootstrap token. Shelf lower-cases
/// header names, so this is the lookup key too.
const bootstrapTokenHeader = 'x-bootstrap-token';

/// Environment variable naming the administrator to seed at start.
const adminUsernameEnv = 'FHIRANT_ADMIN_USERNAME';

/// Environment variable carrying that administrator's password.
const adminPasswordEnv = 'FHIRANT_ADMIN_PASSWORD';

/// What [seedAdminFromEnvironment] did.
sealed class SeedOutcome {
  const SeedOutcome();
}

/// Neither variable was set: nothing to do.
class SeedNotConfigured extends SeedOutcome {
  const SeedNotConfigured();
}

/// The account was created.
class SeedCreated extends SeedOutcome {
  const SeedCreated(this.username);
  final String username;
}

/// The store already has an active administrator; the variables were
/// left alone (they are a bootstrap, not a reset).
class SeedAlreadyProvisioned extends SeedOutcome {
  const SeedAlreadyProvisioned();
}

/// The variables were set but cannot be applied: only one of the two, or
/// a username or password outside the policy. The server should refuse to
/// start rather than run with the administrator the operator asked for
/// missing.
class SeedRefused extends SeedOutcome {
  const SeedRefused(this.message);
  final String message;
}

/// Creates the administrator named by [adminUsernameEnv] and
/// [adminPasswordEnv] in [env], if both are set and the store has no active
/// administrator.
Future<SeedOutcome> seedAdminFromEnvironment(
  FhirAntDb db,
  Map<String, String> env,
) async {
  final username = env[adminUsernameEnv];
  final password = env[adminPasswordEnv];
  final hasUser = username != null && username.isNotEmpty;
  final hasPassword = password != null && password.isNotEmpty;
  if (!hasUser && !hasPassword) return const SeedNotConfigured();
  if (!hasUser || !hasPassword) {
    return const SeedRefused(
      'Set both $adminUsernameEnv and $adminPasswordEnv, or neither',
    );
  }
  final result = await AdminProvisioning.createInitialAdmin(
    db,
    username,
    password,
  );
  return switch (result.status) {
    AdminSetupStatus.created => SeedCreated(username.trim()),
    AdminSetupStatus.alreadyExists => const SeedAlreadyProvisioned(),
    AdminSetupStatus.invalid => SeedRefused(result.message ?? 'invalid'),
  };
}

/// A fresh bootstrap token: 32 bytes of secure randomness, base64url.
String generateBootstrapToken() => JwtSecret.generate();

/// Issues the token the first registration must carry, or null when the
/// store already has an account.
///
/// A new token is generated at every start (never read back from the
/// file), written to [persistPath] readable by the owner only, and
/// returned for the caller to log. When an account exists the file, if
/// any, is removed: the token it held can no longer be used.
Future<String?> issueBootstrapToken(
  FhirAntDb db, {
  required String persistPath,
}) async {
  final file = File(persistPath);
  if (await db.getUserCount() > 0) {
    if (file.existsSync()) file.deleteSync();
    return null;
  }
  final token = generateBootstrapToken();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(token, flush: true);
  JwtSecret.restrictToOwner(file);
  return token;
}

/// Constant-time comparison of a presented token with the issued one.
bool bootstrapTokenMatches(String presented, String issued) {
  if (presented.length != issued.length) return false;
  var diff = 0;
  for (var i = 0; i < issued.length; i++) {
    diff |= presented.codeUnitAt(i) ^ issued.codeUnitAt(i);
  }
  return diff == 0;
}
