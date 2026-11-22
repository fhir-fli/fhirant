import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/handlers/account_handler.dart'
    show requireAdmin;
import 'package:fhirant_server/src/services/storage_floor.dart';
import 'package:fhirant_server/src/sync/sync_endpoint.dart';
import 'package:fhirant_server/src/sync/sync_job.dart';
import 'package:fhirant_server/src/utils/parameters_body.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// `POST /$sync` (admin or a `system/` scope, enforced by the authorization
/// layer as for `$reindex`): brings this server and the peer named by the
/// `peer` parameter (its base URL) to the same content for everything
/// either changed since their last sync, through the peer's REST
/// interface with the `token` parameter as its bearer token.
///
/// Asynchronous, as `$reindex` is: 202 with `Content-Location` to
/// `/$sync-status`; 409 while one is running. The token is held for the
/// run only, never stored or logged.
Future<Response> syncKickoffHandler(
  Request request, {
  required FhirAntDb db,
  required SyncJobs jobs,
  required Handler Function() router,
  required String? baseUrl,
  StorageFloor? floor,
  http.Client Function()? httpClient,
}) async {
  final read = await readOperationParameters(request);
  if (read.refusal != null) return read.refusal!;
  final peerText = read.params['peer'];
  final token = read.params['token'];
  final problem = syncPeerProblem(peerText);
  if (problem != null) {
    return outcomeResponse(400, problem.code, problem.message);
  }
  final peer = Uri.parse((peerText as String).trim());
  if (token != null && token is! String) {
    return outcomeResponse(400, 'invalid', 'token must be a string.');
  }
  final peerKey = syncPeerKey(peer);
  final origin = request.requestedUri;
  final localBase = baseUrl ??
      Uri(
        scheme: origin.scheme,
        host: origin.host,
        port: origin.hasPort ? origin.port : null,
      ).toString();
  final authUser = request.context['auth_user'];
  final remoteEndpoint = RemoteEndpoint(
    Uri.parse(peerKey),
    token: token as String?,
    client: httpClient?.call(),
  );
  final job = await jobs.start(
    db: db,
    peer: peerKey,
    local: SyncClient(
      LocalEndpoint(
        router(),
        Uri.parse(localBase),
        authUser is Map<String, dynamic> ? authUser : null,
      ),
    ),
    remote: SyncClient(remoteEndpoint),
    floor: floor,
    onDone: remoteEndpoint.close,
  );
  if (job == null) {
    remoteEndpoint.close();
    final lease = await db.syncLease();
    return outcomeResponse(
      409,
      'conflict',
      lease == null
          ? r'A $sync is already running; poll its status.'
          : 'A sync with ${lease.peer} has been running since '
              '${_instant(lease.started)}; one runs at a time.',
    );
  }
  FhirantLogging().logInfo(
    '\$sync with $peerKey started by ${Principal.of(request)?.username}',
  );
  final status = Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: r'/$sync-status',
  );
  return Response(
    202,
    headers: {
      'Content-Location': '$status',
      'Content-Type': 'application/fhir+json',
    },
    body: jsonEncode({
      'resourceType': 'OperationOutcome',
      'issue': [
        {
          'severity': 'information',
          'code': 'informational',
          'diagnostics': 'Sync with $peerKey started '
              '${job.started.toIso8601String()}.',
        },
      ],
    }),
  );
}

/// Why [peerText] cannot be a peer to sync with (its issue code and the
/// explanation), or null when it can: the base URL of a server, http or
/// https, with no user name or password in it. Credentials go in `token`:
/// in the URL they would be logged, returned by `$sync-status` and kept as
/// the bookkeeping key. The Administration screen checks the address with
/// this before it signs in at the peer.
({String code, String message})? syncPeerProblem(Object? peerText) {
  final peer = peerText is String ? Uri.tryParse(peerText.trim()) : null;
  if (peer == null ||
      !(peer.scheme == 'http' || peer.scheme == 'https') ||
      peer.host.isEmpty) {
    return (
      code: 'required',
      message: 'peer must be the base URL of the server to sync with '
          '(http or https).',
    );
  }
  if (peer.userInfo.isNotEmpty) {
    return (
      code: 'invalid',
      message: 'peer must not carry a user name or password; pass the '
          'credential as token.',
    );
  }
  return null;
}

/// The key a peer's bookkeeping is kept under: its base URL with no query,
/// fragment or trailing slash.
String syncPeerKey(Uri peer) => Uri(
      scheme: peer.scheme,
      host: peer.host,
      port: peer.hasPort ? peer.port : null,
      path: peer.path.replaceFirst(RegExp(r'/+$'), ''),
    ).toString();

/// `GET /$sync-status`: 202 while the sync runs, 200 with a Parameters of
/// what it did when it finished, 500 when it stopped early, 404 when none
/// was started in this process.
///
/// A sync another process on this device runs (the phone's Administration
/// screen, or the server while the screen asks) holds the store's lease:
/// 202 with its peer and start, the counts being that process's own.
Future<Response> syncStatusHandler(
  Request request,
  SyncJobs jobs,
  FhirAntDb db,
) async {
  final job = jobs.current;
  if (job == null || !job.running) {
    final lease = await db.syncLease();
    if (lease != null &&
        DateTime.now().difference(lease.heartbeat) < jobs.staleAfter) {
      return Response(
        202,
        headers: {
          'X-Progress': 'Syncing with ${lease.peer} since '
              '${_instant(lease.started)}, started elsewhere on this device',
          'Retry-After': '5',
        },
      );
    }
  }
  if (job == null) {
    return outcomeResponse(404, 'not-found', r'No $sync has been run.');
  }
  if (job.running) {
    return Response(
      202,
      headers: {
        'X-Progress': 'Syncing with ${job.peer} since '
            '${job.started.toIso8601String()}: '
            '${job.report.considered} resources to compare',
        'Retry-After': '5',
      },
    );
  }
  if (job.error != null) {
    return outcomeResponse(500, 'exception', 'Sync failed: ${job.error}');
  }
  final r = job.report;
  Map<String, dynamic> integer(String name, int value) =>
      {'name': name, 'valueInteger': value};
  Map<String, dynamic> text(String name, String value) =>
      {'name': name, 'valueString': value};
  return Response(
    200,
    headers: {'Content-Type': 'application/fhir+json'},
    body: jsonEncode({
      'resourceType': 'Parameters',
      'parameter': [
        {'name': 'peer', 'valueUrl': job.peer},
        {'name': 'started', 'valueInstant': _instant(job.started)},
        {'name': 'finished', 'valueInstant': _instant(job.finished!)},
        integer('considered', r.considered),
        integer('unchanged', r.unchanged),
        integer('writtenToPeer', r.writtenToPeer),
        integer('writtenHere', r.writtenHere),
        integer('deletedOnPeer', r.deletedOnPeer),
        integer('deletedHere', r.deletedHere),
        for (final c in r.conflicts) text('conflict', c),
        for (final c in r.retryLater) text('retryLater', c),
        for (final f in r.failures) text('failure', f),
      ],
    }),
  );
}

/// `GET /admin/sync-peers` (administrators): every server a sync with this
/// one completed with, newest first, and when it last did
/// (`{"peers": [{"peer": "<base URL>", "last_run": "<instant>"}]}`). The
/// Administration screen offers these to sync with again.
Future<Response> syncPeersHandler(Request request, FhirAntDb db) async {
  final refused = requireAdmin(request);
  if (refused != null) return refused;
  return Response.ok(
    jsonEncode({
      'peers': [
        for (final p in await db.syncPeers())
          {
            'peer': p.peer,
            if (p.lastRun != null) 'last_run': _instant(p.lastRun!),
          },
      ],
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

String _instant(DateTime t) => t.toUtc().toIso8601String();
