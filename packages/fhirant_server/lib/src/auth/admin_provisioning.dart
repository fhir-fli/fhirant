import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';

/// Outcome of an admin-provisioning attempt.
enum AdminSetupStatus {
  /// The initial admin account was created.
  created,

  /// A user already exists — bootstrap is a one-time operation.
  alreadyExists,

  /// The username or password failed validation ([AdminSetupResult.message]).
  invalid,
}

/// Result of [AdminProvisioning.createInitialAdmin].
class AdminSetupResult {
  const AdminSetupResult(this.status, {this.message, this.userId});

  final AdminSetupStatus status;

  /// A human-readable reason when [status] is [AdminSetupStatus.invalid].
  final String? message;

  /// The new user's id when [status] is [AdminSetupStatus.created].
  final int? userId;

  bool get ok => status == AdminSetupStatus.created;
}

/// Creates the single initial administrator account for a fresh server.
///
/// This is the one credential a real (Secure-mode) deployment needs: the
/// operator sets it up on first launch, and external LAN clients authenticate
/// with it. It is the same first-user bootstrap the HTTP `/auth/register`
/// endpoint performs, factored out so the app can provision the admin directly
/// against the local database without a running server.
class AdminProvisioning {
  AdminProvisioning._();

  /// Minimum username length (mirrors the HTTP register handler).
  static const minUsernameLength = 3;

  /// Creates the initial admin account on a database that has **no users**.
  ///
  /// Fails with [AdminSetupStatus.alreadyExists] if any user already exists
  /// (bootstrap is one-time), or [AdminSetupStatus.invalid] if the username is
  /// too short or the password fails [PasswordPolicy].
  static Future<AdminSetupResult> createInitialAdmin(
    FhirAntDb db,
    String username,
    String password,
  ) async {
    final trimmed = username.trim();
    if (trimmed.length < minUsernameLength) {
      return const AdminSetupResult(
        AdminSetupStatus.invalid,
        message: 'Username must be at least $minUsernameLength characters.',
      );
    }

    final policyError = PasswordPolicy.validate(password);
    if (policyError != null) {
      return AdminSetupResult(AdminSetupStatus.invalid, message: policyError);
    }

    // Bootstrap only applies to an empty user table. Checking the count (rather
    // than just this username) keeps "the first account is the admin" true and
    // prevents a second unauthenticated admin from being created.
    if (await db.getUserCount() > 0) {
      return const AdminSetupResult(AdminSetupStatus.alreadyExists);
    }

    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hashPassword(password, salt);
    final scopes = jsonEncode(SmartScopeEnforcer.defaultScopesForRole('admin'));

    final id = await db.createUser(
      username: trimmed,
      passwordHash: hash,
      salt: salt,
      role: 'admin',
      scopes: scopes,
    );

    return AdminSetupResult(AdminSetupStatus.created, userId: id);
  }
}
