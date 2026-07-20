import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Generation and offline-friendly persistence of the JWT signing secret.
///
/// The signing secret must be strong and unique per deployment: anyone who
/// knows it can forge tokens for any user, including admins. Earlier versions
/// fell back to a hardcoded string when nothing was configured, so this class
/// centralizes secure handling.
///
/// [resolveForServer] is designed for headless (CLI/container) deployments
/// that may run **completely offline in the field with no operator to set
/// environment variables**: when nothing is configured it generates a strong
/// secret and persists it locally, so a zero-config deployment still gets a
/// stable, unguessable secret without contacting anything.
class JwtSecret {
  JwtSecret._();

  /// Generates a cryptographically strong secret: 32 bytes of secure
  /// randomness, base64url-encoded.
  static String generate() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Resolves the signing secret for a headless deployment.
  ///
  /// Precedence:
  /// 1. [explicit] — a value the caller already holds (e.g. from secure
  ///    storage on mobile), used verbatim when non-empty.
  /// 2. [envValue] — e.g. `FHIRANT_JWT_SECRET`; preferred for cloud/
  ///    multi-instance deployments where instances must share one secret and
  ///    the filesystem is ephemeral.
  /// 3. A secret persisted at [persistPath], created (with owner-only
  ///    permissions where supported) if the file is absent or empty.
  ///
  /// Never returns a shared or hardcoded default.
  static String resolveForServer({
    String? explicit,
    String? envValue,
    required String persistPath,
  }) {
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (envValue != null && envValue.isNotEmpty) return envValue;

    final file = File(persistPath);
    if (file.existsSync()) {
      final existing = file.readAsStringSync().trim();
      if (existing.isNotEmpty) return existing;
    }

    final secret = generate();
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(secret, flush: true);
    _restrictToOwner(file);
    return secret;
  }

  /// Best-effort tightening of file permissions to owner-only (POSIX).
  /// No-op on platforms without `chmod` (e.g. Windows), where filesystem
  /// ACLs govern access instead. Non-fatal on failure — the secret is still
  /// random and local either way.
  static void _restrictToOwner(File file) {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        Process.runSync('chmod', ['600', file.path]);
      } catch (_) {
        // Ignored: permissions are a hardening bonus, not a correctness need.
      }
    }
  }
}
