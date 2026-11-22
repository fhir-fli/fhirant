import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/account_rules.dart' as rules;
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/breached_passwords.dart';
import 'package:shelf/shelf.dart';

/// The account work an operator does on the phone itself, through the
/// server's own routes, in this process, with no network (Grey 2026-11-21:
/// "anything requiring the command line is wrong for this app").
///
/// Every call goes through the same pipeline a client's request does: the
/// credential rate limit and lockout at sign-in, the token check, the
/// administrator check, the last-administrator rules, the password policy
/// and breach check, and the audit trail. Nothing here decides anything a
/// route already decides; each method is one request. The pipeline is
/// built without listening on a port, so it works whether the phone's
/// server is started or not, and whether this process or the foreground
/// service runs it: both share the store and the signing secret.
///
/// The requests carry the loopback address, which is what the audit trail
/// records as where they came from.
class DeviceConsole {
  DeviceConsole(
    FhirAntDb db, {
    required String jwtSecret,
    BreachedPasswordLookup? breachedPasswords = hibpBreachLookup,
  }) : _server = FhirAntServer(
          db,
          jwtSecret: jwtSecret,
          breachedPasswords: breachedPasswords,
        ) {
    _handler = _server.createHandler(_server.createRouter());
  }

  final FhirAntServer _server;
  late final Handler _handler;

  /// The roles an account can have.
  static const Set<String> roles = rules.validRoles;

  /// The address an on-device request is recorded under.
  static const deviceAddress = '127.0.0.1';

  /// One request through the pipeline.
  Future<ConsoleReply> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final response = await _handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        // The connection is this device's own: the server's first step
        // takes the address from it, as from a socket, and the audit trail
        // records it.
        context: const {'shelf.io.connection_info': _OnDevice()},
        headers: {
          if (token != null) 'authorization': 'Bearer $token',
          if (body != null) 'content-type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final text = await response.readAsString();
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    return ConsoleReply(
      response.statusCode,
      json is Map<String, dynamic> ? json : const {},
      text,
    );
  }

  /// Signs in with a username and password (`POST /auth/login`).
  Future<ConsoleResult<DeviceSession>> signIn(
    String username,
    String password,
  ) async {
    final r = await send(
      'POST',
      '/auth/login',
      body: {'username': username, 'password': password},
    );
    if (r.status != 200) return ConsoleResult.failed(r);
    return ConsoleResult.ok(
      DeviceSession(
        username: r.json['username'] as String? ?? username,
        role: r.json['role'] as String? ?? '',
        token: r.json['token'] as String,
        refreshToken: r.json['refresh_token'] as String?,
      ),
    );
  }

  /// Ends [session] (`POST /auth/logout`): both its tokens are revoked.
  Future<void> signOut(DeviceSession session) async {
    await send(
      'POST',
      '/auth/logout',
      token: session.token,
      body: {
        if (session.refreshToken != null) 'refresh_token': session.refreshToken,
      },
    );
  }

  /// Every account (`GET /admin/users`).
  Future<ConsoleResult<List<Account>>> accounts(DeviceSession session) async {
    final r = await send('GET', '/admin/users', token: session.token);
    if (r.status != 200) return ConsoleResult.failed(r);
    final users = (r.json['users'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Account.fromJson)
        .toList();
    return ConsoleResult.ok(users);
  }

  /// Creates an account that waits for its owner (`POST /auth/register`).
  /// [patient] is a Patient id or `Patient/<id>`, for a patient's own
  /// account; [scopes] null takes the role's defaults.
  Future<ConsoleResult<void>> create(
    DeviceSession session, {
    required String username,
    required String role,
    String? patient,
    List<String>? scopes,
  }) =>
      _done(
        send(
          'POST',
          '/auth/register',
          token: session.token,
          body: {
            'username': username,
            'role': role,
            if (patient != null && patient.isNotEmpty) 'patient': patient,
            if (scopes != null) 'scopes': scopes,
          },
        ),
      );

  /// Approves the password the owner sent, with the code they were shown.
  Future<ConsoleResult<void>> approve(
    DeviceSession session,
    int userId,
    String code,
  ) =>
      _done(
        send(
          'POST',
          '/admin/users/$userId/approve',
          token: session.token,
          body: {'code': code},
        ),
      );

  /// Resets an account's password: it waits for its owner again.
  Future<ConsoleResult<void>> reset(DeviceSession session, int userId) => _done(
        send('POST', '/admin/users/$userId/password', token: session.token),
      );

  /// Switches an account on or off.
  Future<ConsoleResult<void>> setActive(
    DeviceSession session,
    int userId, {
    required bool active,
  }) =>
      _done(
        send(
          'POST',
          '/admin/users/$userId/${active ? 'activate' : 'deactivate'}',
          token: session.token,
        ),
      );

  /// Changes an account's role.
  Future<ConsoleResult<void>> setRole(
    DeviceSession session,
    int userId,
    String role,
  ) =>
      _done(
        send(
          'PUT',
          '/admin/users/$userId/role',
          token: session.token,
          body: {'role': role},
        ),
      );

  /// Changes an account's permissions; null returns it to its role's.
  Future<ConsoleResult<void>> setScopes(
    DeviceSession session,
    int userId,
    List<String>? scopes,
  ) =>
      _done(
        send(
          'PUT',
          '/admin/users/$userId/scopes',
          token: session.token,
          body: {'scopes': scopes},
        ),
      );

  /// Unlocks an account locked by failed sign-ins.
  Future<ConsoleResult<void>> unlock(DeviceSession session, int userId) =>
      _done(send('POST', '/admin/unlock/$userId', token: session.token));

  /// The owner of a waiting account sends their own password
  /// (`POST /auth/claim`); the result is the code to show the
  /// administrator. The answer is the same for an account that does not
  /// wait (the route's rule), so a code is not proof the account exists.
  Future<ConsoleResult<String>> claim(
    String username,
    String newPassword,
  ) async {
    final r = await send(
      'POST',
      '/auth/claim',
      body: {'username': username, 'new_password': newPassword},
    );
    if (r.status != 202) return ConsoleResult.failed(r);
    return ConsoleResult.ok(r.json['code'] as String);
  }

  /// The signed-in person changes their own password; the session the
  /// change hands back replaces [session].
  Future<ConsoleResult<DeviceSession>> changeOwnPassword(
    DeviceSession session,
    String current,
    String next,
  ) async {
    final r = await send(
      'POST',
      '/auth/password',
      token: session.token,
      body: {'current_password': current, 'new_password': next},
    );
    if (r.status != 200) return ConsoleResult.failed(r);
    return ConsoleResult.ok(
      DeviceSession(
        username: session.username,
        role: session.role,
        token: r.json['token'] as String,
        refreshToken: r.json['refresh_token'] as String?,
      ),
    );
  }

  /// Writes what the calls queued for the audit trail.
  Future<void> close() => _server.auditQueue.drain();

  static Future<ConsoleResult<void>> _done(Future<ConsoleReply> reply) async {
    final r = await reply;
    return r.status >= 200 && r.status < 300
        ? const ConsoleResult.ok(null)
        : ConsoleResult.failed(r);
  }
}

/// The connection of an on-device request: loopback, no port.
class _OnDevice implements HttpConnectionInfo {
  const _OnDevice();
  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;
  @override
  int get remotePort => 0;
  @override
  int get localPort => 0;
}

/// A route's answer.
class ConsoleReply {
  const ConsoleReply(this.status, this.json, this.text);
  final int status;
  final Map<String, dynamic> json;
  final String text;

  /// The route's own explanation, for the screen.
  String get message {
    final error = json['error'];
    if (error is String && error.isNotEmpty) {
      final description = json['error_description'];
      return description is String && description.isNotEmpty
          ? description
          : error;
    }
    return 'The server answered $status';
  }
}

/// A call's value, or the reply that refused it.
class ConsoleResult<T> {
  const ConsoleResult.ok(T this.value) : refusal = null;
  const ConsoleResult.failed(ConsoleReply this.refusal) : value = null;
  final T? value;
  final ConsoleReply? refusal;
  bool get ok => refusal == null;
}

/// A sign-in on the phone.
class DeviceSession {
  const DeviceSession({
    required this.username,
    required this.role,
    required this.token,
    this.refreshToken,
  });
  final String username;
  final String role;
  final String token;
  final String? refreshToken;
  bool get isAdmin => role == 'admin';
}

/// One row of `GET /admin/users`.
class Account {
  const Account({
    required this.id,
    required this.username,
    required this.role,
    required this.active,
    required this.locked,
    required this.scopes,
    this.patient,
    this.awaitingOwnerUntil,
    this.passwordSent = false,
    this.lastLogin,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as int,
        username: j['username'] as String,
        role: j['role'] as String,
        active: j['active'] as bool? ?? false,
        locked: j['locked'] as bool? ?? false,
        scopes: (j['scopes'] as List? ?? const []).cast<String>(),
        patient: j['patient'] as String?,
        awaitingOwnerUntil: DateTime.tryParse(
          j['awaiting_owner_until'] as String? ?? '',
        ),
        passwordSent: j['password_sent'] as bool? ?? false,
        lastLogin: DateTime.tryParse(j['last_login'] as String? ?? ''),
      );

  final int id;
  final String username;
  final String role;
  final bool active;
  final bool locked;
  final List<String> scopes;
  final String? patient;
  final DateTime? awaitingOwnerUntil;
  final bool passwordSent;
  final DateTime? lastLogin;

  /// Waiting for its owner, and the wait has not run out.
  bool get awaitingOwner =>
      awaitingOwnerUntil != null && awaitingOwnerUntil!.isAfter(DateTime.now());
}
