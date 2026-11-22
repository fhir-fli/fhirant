import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/account_rules.dart' as rules;
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/handlers/sync_handler.dart'
    show syncPeerKey, syncPeerProblem;
import 'package:fhirant_server/src/sync/sync_job.dart';
import 'package:fhirant_server/src/utils/breached_passwords.dart';
import 'package:http/http.dart' as http;
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
  /// [exportDir] is the app's export directory: the storage floor measures
  /// the disk there, and on a path that does not exist it cannot measure
  /// and lets every write through. [syncJobs] is the app's one record of
  /// the running sync, shared by every console it opens, so a sync started
  /// here outlives this console's session. [peerClient] makes the requests
  /// to a peer server's sign-in.
  DeviceConsole(
    FhirAntDb db, {
    required String jwtSecret,
    String? exportDir,
    SyncJobs? syncJobs,
    BreachedPasswordLookup? breachedPasswords = hibpBreachLookup,
    http.Client Function()? peerClient,
  })  : _peerClient = peerClient ?? http.Client.new,
        _server = FhirAntServer(
          db,
          jwtSecret: jwtSecret,
          exportDir: exportDir,
          syncJobs: syncJobs,
          breachedPasswords: breachedPasswords,
        ) {
    _handler = _server.createHandler(_server.createRouter());
  }

  final FhirAntServer _server;
  final http.Client Function() _peerClient;
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
      headers: response.headers,
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

  /// Every registered app (`GET /admin/clients`).
  Future<ConsoleResult<List<RegisteredApp>>> apps(DeviceSession session) async {
    final r = await send('GET', '/admin/clients', token: session.token);
    if (r.status != 200) return ConsoleResult.failed(r);
    return ConsoleResult.ok(
      (r.json['apps'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RegisteredApp.fromJson)
          .toList(),
    );
  }

  /// Registers the app [clientId], or changes it: its [name] and every
  /// address it may be sent back to (`PUT /admin/clients/<clientId>`).
  Future<ConsoleResult<void>> putApp(
    DeviceSession session,
    String clientId, {
    required String name,
    required List<String> redirectUris,
  }) =>
      _done(
        send(
          'PUT',
          '/admin/clients/${Uri.encodeComponent(clientId)}',
          token: session.token,
          body: {'name': name, 'redirect_uris': redirectUris},
        ),
      );

  /// Removes the app [clientId]; its sessions end
  /// (`DELETE /admin/clients/<clientId>`).
  Future<ConsoleResult<void>> removeApp(
    DeviceSession session,
    String clientId,
  ) =>
      _done(
        send(
          'DELETE',
          '/admin/clients/${Uri.encodeComponent(clientId)}',
          token: session.token,
        ),
      );

  // ── Sync ────────────────────────────────────────────────────────────────

  /// The servers a sync completed with, newest first
  /// (`GET /admin/sync-peers`).
  Future<ConsoleResult<List<SyncedPeer>>> syncPeers(
    DeviceSession session,
  ) async {
    final r = await send('GET', '/admin/sync-peers', token: session.token);
    if (r.status != 200) return ConsoleResult.failed(r);
    return ConsoleResult.ok(
      (r.json['peers'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SyncedPeer.fromJson)
          .toList(),
    );
  }

  /// Starts a sync with the server at [peer] (`POST /$sync`).
  ///
  /// With [username] and [password], signs in at the peer first, with its
  /// own `/auth/login` (a fhirant server: its lockout and audit apply
  /// there), and uses that sign-in's token for the run; the peer session
  /// is signed out when the sync ends, or at once when the sync is not
  /// started. With [token] instead, that token is the run's (a server that
  /// is not fhirant). With neither, the peer is asked with no token. The
  /// token is held for the run only, as the route holds it.
  ///
  /// A refusal from the peer is marked [ConsoleReply.fromPeer]: its 401 is
  /// the peer's sign-in, not this one's.
  Future<ConsoleResult<void>> startSync(
    DeviceSession session,
    String peer, {
    String? username,
    String? password,
    String? token,
  }) async {
    final problem = syncPeerProblem(peer);
    if (problem != null) {
      return ConsoleResult.failed(
        ConsoleReply(400, {'error': problem.message}, ''),
      );
    }
    final base = Uri.parse(syncPeerKey(Uri.parse(peer.trim())));
    var runToken = token;
    String? peerRefresh;
    if (username != null) {
      final signIn = await _peerSignIn(base, username, password ?? '');
      if (!signIn.ok) return ConsoleResult.failed(signIn.refusal!);
      runToken = signIn.value!.token;
      peerRefresh = signIn.value!.refreshToken;
    }
    final r = await send(
      'POST',
      r'/$sync',
      token: session.token,
      body: {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'peer', 'valueUrl': '$base'},
          if (runToken != null) {'name': 'token', 'valueString': runToken},
        ],
      },
    );
    final job = _server.syncJobs.current;
    if (r.status != 202 || job == null) {
      if (username != null) await _peerSignOut(base, runToken!, peerRefresh);
      return ConsoleResult.failed(r);
    }
    if (username != null) {
      unawaited(
        job.done.then((_) => _peerSignOut(base, runToken!, peerRefresh)),
      );
    }
    return const ConsoleResult.ok(null);
  }

  /// Where the sync stands (`GET /$sync-status`).
  Future<ConsoleResult<SyncStatus>> syncStatus(DeviceSession session) async {
    final r = await send('GET', r'/$sync-status', token: session.token);
    switch (r.status) {
      case 404:
        return const ConsoleResult.ok(SyncStatus.none());
      case 202:
        return ConsoleResult.ok(
          SyncStatus.running(r.headers['x-progress'] ?? 'Syncing'),
        );
      case 200:
        return ConsoleResult.ok(SyncStatus.fromParameters(r.json));
      case 500:
        return ConsoleResult.ok(SyncStatus.failed(r.message));
    }
    return ConsoleResult.failed(r);
  }

  Future<ConsoleResult<DeviceSession>> _peerSignIn(
    Uri base,
    String username,
    String password,
  ) async {
    final client = _peerClient();
    try {
      final response = await client
          .post(
            base.replace(path: '${base.path}/auth/login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      Object? json;
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        json = null;
      }
      final map = json is Map<String, dynamic> ? json : <String, dynamic>{};
      final token = map['token'];
      if (response.statusCode != 200 || token is! String) {
        return ConsoleResult.failed(
          ConsoleReply(
            response.statusCode,
            map,
            response.body,
            fromPeer: true,
          ),
        );
      }
      return ConsoleResult.ok(
        DeviceSession(
          username: username,
          role: map['role'] as String? ?? '',
          token: token,
          refreshToken: map['refresh_token'] as String?,
        ),
      );
    } on Object catch (e) {
      return ConsoleResult.failed(
        ConsoleReply(
          0,
          {'error': 'Could not reach $base: $e'},
          '',
          fromPeer: true,
        ),
      );
    } finally {
      client.close();
    }
  }

  /// Ends the peer session a sync signed in for. Best effort: a peer that
  /// cannot be reached keeps the session until its tokens expire.
  Future<void> _peerSignOut(Uri base, String token, String? refresh) async {
    final client = _peerClient();
    try {
      await client
          .post(
            base.replace(path: '${base.path}/auth/logout'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({if (refresh != null) 'refresh_token': refresh}),
          )
          .timeout(const Duration(seconds: 30));
    } on Object {
      // Nothing more to do: the tokens expire on their own.
    } finally {
      client.close();
    }
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
  const ConsoleReply(
    this.status,
    this.json,
    this.text, {
    this.headers = const {},
    this.fromPeer = false,
  });
  final int status;
  final Map<String, dynamic> json;
  final String text;
  final Map<String, String> headers;

  /// The answer came from a peer server, not this one (0: no answer).
  final bool fromPeer;

  /// The route's own explanation, for the screen.
  String get message {
    final who = fromPeer ? 'The other server' : 'The server';
    String said(String m) => fromPeer ? '$who: $m' : m;
    final error = json['error'];
    if (error is String && error.isNotEmpty) {
      final description = json['error_description'];
      return said(
        description is String && description.isNotEmpty ? description : error,
      );
    }
    // A FHIR route answers with an OperationOutcome.
    final issues = json['issue'];
    if (issues is List && issues.isNotEmpty) {
      final first = issues.first;
      final text = first is Map ? first['diagnostics'] : null;
      if (text is String && text.isNotEmpty) return said(text);
    }
    return '$who answered $status';
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

/// One row of `GET /admin/clients`: an app allowed to sign people in.
class RegisteredApp {
  const RegisteredApp({
    required this.clientId,
    required this.name,
    required this.registered,
    required this.redirectUris,
  });

  factory RegisteredApp.fromJson(Map<String, dynamic> j) => RegisteredApp(
        clientId: j['client_id'] as String,
        name: j['name'] as String? ?? '',
        registered: DateTime.parse(j['registered'] as String),
        redirectUris: (j['redirect_uris'] as List? ?? const []).cast<String>(),
      );

  final String clientId;
  final String name;
  final DateTime registered;
  final List<String> redirectUris;
}

/// One row of `GET /admin/sync-peers`: a server a sync completed with.
class SyncedPeer {
  const SyncedPeer({required this.peer, this.lastRun});

  factory SyncedPeer.fromJson(Map<String, dynamic> j) => SyncedPeer(
        peer: j['peer'] as String,
        lastRun: DateTime.tryParse(j['last_run'] as String? ?? ''),
      );

  /// Its base URL.
  final String peer;

  /// When the last sync with it completed.
  final DateTime? lastRun;
}

/// Where the sync stands, from `GET /$sync-status`.
class SyncStatus {
  /// None was run since the app started.
  const SyncStatus.none()
      : state = SyncState.none,
        progress = null,
        error = null,
        peer = null,
        started = null,
        finished = null,
        counts = const {},
        conflicts = const [],
        retryLater = const [],
        failures = const [];

  /// One is running; [progress] is the route's own line.
  const SyncStatus.running(String this.progress)
      : state = SyncState.running,
        error = null,
        peer = null,
        started = null,
        finished = null,
        counts = const {},
        conflicts = const [],
        retryLater = const [],
        failures = const [];

  /// The last one stopped early.
  const SyncStatus.failed(String this.error)
      : state = SyncState.failed,
        progress = null,
        peer = null,
        started = null,
        finished = null,
        counts = const {},
        conflicts = const [],
        retryLater = const [],
        failures = const [];

  /// The last one finished: the route's Parameters.
  factory SyncStatus.fromParameters(Map<String, dynamic> json) {
    final counts = <String, int>{};
    final lists = <String, List<String>>{};
    String? peer;
    DateTime? started;
    DateTime? finished;
    for (final p in (json['parameter'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final name = p['name'] as String?;
      if (name == null) continue;
      if (p['valueInteger'] is int) {
        counts[name] = p['valueInteger'] as int;
      } else if (p['valueString'] is String) {
        lists.putIfAbsent(name, () => []).add(p['valueString'] as String);
      } else if (name == 'peer') {
        peer = p['valueUrl'] as String?;
      } else if (name == 'started') {
        started = DateTime.tryParse(p['valueInstant'] as String? ?? '');
      } else if (name == 'finished') {
        finished = DateTime.tryParse(p['valueInstant'] as String? ?? '');
      }
    }
    return SyncStatus._done(
      peer: peer,
      started: started,
      finished: finished,
      counts: counts,
      conflicts: lists['conflict'] ?? const [],
      retryLater: lists['retryLater'] ?? const [],
      failures: lists['failure'] ?? const [],
    );
  }

  const SyncStatus._done({
    required this.peer,
    required this.started,
    required this.finished,
    required this.counts,
    required this.conflicts,
    required this.retryLater,
    required this.failures,
  })  : state = SyncState.done,
        progress = null,
        error = null;

  final SyncState state;
  final String? progress;
  final String? error;
  final String? peer;
  final DateTime? started;
  final DateTime? finished;

  /// considered, unchanged, writtenToPeer, writtenHere, deletedOnPeer,
  /// deletedHere.
  final Map<String, int> counts;
  final List<String> conflicts;
  final List<String> retryLater;
  final List<String> failures;
}

/// Whether a sync was run, runs, or how it ended.
enum SyncState { none, running, done, failed }
