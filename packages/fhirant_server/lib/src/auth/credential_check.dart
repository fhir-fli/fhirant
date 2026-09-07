import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';

/// Maximum consecutive failed attempts before an account is locked.
const maxFailedAttempts = 5;

/// How long an account stays locked after [maxFailedAttempts].
const lockoutDuration = Duration(minutes: 15);

/// The one place a username and password are checked.
///
/// `/auth/login` and both `/auth/authorize` handlers used to check
/// credentials separately, and only login counted failures: six wrong
/// passwords through the OAuth form left the account unlocked, and a login
/// there never upgraded a legacy hash (REVIEW-2026-09-06 finding 7). Every
/// caller now gets the same lockout, the same reset, and the same rehash.
sealed class CredentialResult {
  const CredentialResult();
}

/// The password matched an active, unlocked account.
class CredentialOk extends CredentialResult {
  const CredentialOk(this.user);

  /// The account that authenticated.
  final User user;
}

/// Unknown username or wrong password. The two are not distinguished, and
/// an unknown username costs the same hash as a wrong password.
class CredentialInvalid extends CredentialResult {
  const CredentialInvalid();
}

/// The account exists but has been deactivated.
class CredentialInactive extends CredentialResult {
  const CredentialInactive();
}

/// The account is locked, either from an earlier run of failures or by the
/// attempt just made ([justLocked]).
class CredentialLocked extends CredentialResult {
  const CredentialLocked({
    required this.minutesRemaining,
    required this.justLocked,
  });

  /// Whole minutes until the lock lifts, rounded up.
  final int minutesRemaining;

  /// True when this attempt was the one that tripped the lock.
  final bool justLocked;
}

/// A salt used only to burn the same time on an unknown username as a wrong
/// password costs on a known one, so the response time does not say which
/// usernames exist.
final String _decoySalt = PasswordHasher.generateSalt();

/// Checks [password] against the account named [username].
Future<CredentialResult> checkCredentials(
  FhirAntDb db,
  String username,
  String password,
) async {
  final user = await db.getUserByUsername(username);
  if (user == null) {
    PasswordHasher.hashPassword(password, _decoySalt);
    return const CredentialInvalid();
  }

  if (!user.active) return const CredentialInactive();

  final lockedUntil = user.lockedUntil;
  if (lockedUntil != null) {
    final now = DateTime.now();
    if (lockedUntil.isAfter(now)) {
      return CredentialLocked(
        minutesRemaining: lockedUntil.difference(now).inMinutes + 1,
        justLocked: false,
      );
    }
    // The lock has expired: clear it and the count behind it.
    await db.resetFailedLogins(user.id);
  }

  if (!PasswordHasher.verifyPassword(password, user.salt, user.passwordHash)) {
    final failures = await db.incrementFailedLogins(user.id);
    if (failures >= maxFailedAttempts) {
      await db.lockAccount(user.id, DateTime.now().add(lockoutDuration));
      return CredentialLocked(
        minutesRemaining: lockoutDuration.inMinutes,
        justLocked: true,
      );
    }
    return const CredentialInvalid();
  }

  if (user.failedLoginCount > 0) {
    await db.resetFailedLogins(user.id);
  }
  await db.updateLastLogin(user.id);

  // A legacy HMAC or an under-iterated PBKDF2 is re-hashed now that the
  // plaintext is in hand, so accounts migrate to the current KDF as they
  // are used.
  if (PasswordHasher.needsRehash(user.passwordHash)) {
    final salt = PasswordHasher.generateSalt();
    await db.updatePassword(
      user.id,
      PasswordHasher.hashPassword(password, salt),
      salt,
    );
  }

  return CredentialOk(user);
}
