import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;

import 'package:fhir_r4/fhir_r4.dart' show R4ResourceType;
import 'package:fhirant_server/src/sync/merge.dart';
import 'package:fhirant_server/src/utils/fhir_id.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// One reply from a FHIR server: status, headers (lower-case names), body.
typedef SyncReply = ({int status, Map<String, String> headers, String body});

/// A FHIR server a sync reads and writes through its REST interface: the
/// peer over HTTP ([RemoteEndpoint]), or this server's own handlers in
/// process ([LocalEndpoint]). Both sides are read and written the same way,
/// so the checks a client's write goes through in the handlers (parsing,
/// the file scan, the required codes, If-Match) apply to what a sync
/// writes on either side.
abstract class SyncEndpoint {
  /// The base URL requests are addressed to.
  Uri get base;

  /// Sends [method] to [pathAndQuery] (relative to [base], no leading
  /// slash).
  Future<SyncReply> send(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
  });
}

/// [base] with a path that ends in `/` and no query, so a relative path
/// resolves under it.
Uri _directory(Uri base) => Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path.endsWith('/') ? base.path : '${base.path}/',
    );

/// The peer server, over HTTP, with a bearer [token] when one is given.
///
/// A 429 is waited out and sent again: fhirant answers 429 past 600
/// requests a minute from one address (its default), and a sync of more
/// than a few hundred resources passes that. The wait is the reply's
/// `Retry-After` in seconds, else 5 s; after [maxRetries] in a row the 429
/// is returned.
class RemoteEndpoint implements SyncEndpoint {
  /// Creates an endpoint for the peer at [base].
  RemoteEndpoint(
    Uri base, {
    this.token,
    http.Client? client,
    this.maxRetries = 20,
    this.wait = _sleep,
  })  : base = _directory(base),
        _client = client ?? http.Client();

  @override
  final Uri base;

  /// The bearer token sent to the peer, or null.
  final String? token;

  /// How many 429s in a row are waited out.
  final int maxRetries;

  /// Waits; replaced in tests.
  final Future<void> Function(Duration) wait;

  final http.Client _client;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  @override
  Future<SyncReply> send(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final target = base.resolve(pathAndQuery);
    for (var attempt = 0;; attempt++) {
      final request = http.Request(method, target)
        ..headers.addAll({
          'accept': 'application/fhir+json',
          if (token != null) 'authorization': 'Bearer $token',
          ...?headers,
        });
      if (body != null) request.body = body;
      final reply = await http.Response.fromStream(await _client.send(request));
      if (reply.statusCode == 429 && attempt < maxRetries) {
        final seconds = int.tryParse(reply.headers['retry-after'] ?? '');
        await wait(Duration(seconds: seconds ?? 5));
        continue;
      }
      return (
        status: reply.statusCode,
        headers: reply.headers,
        body: reply.body,
      );
    }
  }

  /// Closes the HTTP client.
  void close() => _client.close();
}

/// This server, through its own router in process, as the account that
/// started the sync ([authUser]: the token claims the auth middleware put
/// on the kickoff request). The router's handlers do their own checks;
/// what the middleware adds (rate limit, audit, the storage floor) is not
/// on this path: the kickoff was audited and passed the floor, and the
/// sync checks the floor before each write here.
class LocalEndpoint implements SyncEndpoint {
  /// Creates an endpoint over [router], served at [base].
  LocalEndpoint(this.router, Uri base, this.authUser) : base = _directory(base);

  /// The server's router (`FhirAntServer.createRouter()`).
  final Handler router;

  @override
  final Uri base;

  /// The caller's claims, as `Principal.of` reads them.
  final Map<String, dynamic>? authUser;

  @override
  Future<SyncReply> send(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final request = Request(
      method,
      base.resolve(pathAndQuery),
      headers: {'accept': 'application/fhir+json', ...?headers},
      body: body,
      context: {if (authUser != null) 'auth_user': authUser!},
    );
    final response = await router(request);
    return (
      status: response.statusCode,
      headers: response.headers,
      body: await response.readAsString(),
    );
  }
}

/// A sync step got an answer it cannot use.
class SyncFailure implements Exception {
  /// Creates a failure.
  SyncFailure(this.message);

  /// What went wrong, with the status and the start of the reply.
  final String message;

  @override
  String toString() => message;
}

/// What a sync reads and writes, over a [SyncEndpoint].
class SyncClient {
  /// Creates a client over [endpoint].
  SyncClient(this.endpoint);

  /// The server.
  final SyncEndpoint endpoint;

  /// The largest page asked for (fhirant's `kMaxPageSize`).
  static const pageSize = 500;

  /// The resources with a version saved at or after [since], or every
  /// resource when [since] is null, by `Type/id`; and the latest
  /// `lastModified` seen, as the server wrote it, for the next `_since`;
  /// and the server's clock when it answered (the reply's `Date`, else
  /// this machine's clock: the in-process side has no `Date` header), so a
  /// caller can tell the clock went back behind its cursor.
  ///
  /// R4B http.html §3.1.0.12 history (hl7.org/fhir/R4B/http.html, read
  /// 2026-11-19): `_since` is "Only include resource versions that were
  /// created at or after the given instant in time", and "The history
  /// interaction can be used to set up a subscription from one system to
  /// another, so that resources are synchronized between them".
  Future<({Set<String> keys, String? latest, DateTime now})> changedSince(
    String? since,
  ) async {
    final keys = <String>{};
    String? latest;
    DateTime? latestAt;
    DateTime? now;
    var next = '_history?_count=$pageSize'
        '${since == null ? '' : '&_since=${Uri.encodeQueryComponent(since)}'}';
    for (;;) {
      final reply = await endpoint.send('GET', next);
      now ??= _dateOf(reply) ?? DateTime.now().toUtc();
      final page = _decode(reply, next);
      for (final entry in _entries(page)) {
        final key = _keyOf(entry);
        if (key == null) continue;
        keys.add(key);
        final modified =
            (entry['response'] as Map?)?['lastModified'] as String?;
        final at = modified == null ? null : DateTime.tryParse(modified);
        if (at != null && (latestAt == null || at.isAfter(latestAt))) {
          latestAt = at;
          latest = modified;
        }
      }
      final link = _nextLink(page);
      if (link == null) break;
      next = link;
    }
    return (keys: keys, latest: latest, now: now);
  }

  static DateTime? _dateOf(SyncReply reply) {
    final date = reply.headers['date'];
    if (date == null) return null;
    try {
      return HttpDate.parse(date);
    } on FormatException {
      return null;
    } on HttpException {
      return null;
    }
  }

  /// Every version of [key] (`Type/id`), oldest first; empty when the
  /// server never had it.
  Future<List<SyncVersion>> history(String key) async {
    // In the server's order, which is newest first (http.html §3.1.0.12,
    // read 2026-11-19: "sorted with oldest versions last"). The order is
    // the server's, not the versions' times: a clock set back stamps a
    // newer version earlier, and two saves can share a millisecond.
    final byVersion = <String, SyncVersion>{};
    var next = '$key/_history?_count=$pageSize';
    for (;;) {
      final reply = await endpoint.send('GET', next);
      if (reply.status == 404 || reply.status == 410) break;
      final page = _decode(reply, next);
      for (final entry in _entries(page)) {
        final version = _versionOf(entry);
        // A page read after a new save repeats an entry; the first
        // reading keeps its place.
        if (version != null) {
          byVersion.putIfAbsent(version.versionId, () => version);
        }
      }
      final link = _nextLink(page);
      if (link == null) break;
      next = link;
    }
    return byVersion.values.toList().reversed.toList();
  }

  /// Writes [json] as [key] (update, or update as create), with
  /// `If-Match` on [ifMatch] when given. Returns the status, the new
  /// version id (from the reply's ETag) and the reply's body.
  Future<({int status, String? versionId, String body})> put(
    String key,
    Map<String, dynamic> json, {
    String? ifMatch,
  }) async {
    final reply = await endpoint.send(
      'PUT',
      key,
      headers: {
        'content-type': 'application/fhir+json',
        if (ifMatch != null) 'if-match': 'W/"$ifMatch"',
      },
      body: jsonEncode(json),
    );
    return (
      status: reply.status,
      versionId: etagVersion(reply.headers['etag']),
      body: reply.body,
    );
  }

  /// Deletes [key], with `If-Match` on [ifMatch]; returns the reply.
  Future<SyncReply> delete(String key, {required String ifMatch}) =>
      endpoint.send('DELETE', key, headers: {'if-match': 'W/"$ifMatch"'});

  Map<String, dynamic> _decode(SyncReply reply, String what) {
    if (reply.status != 200) {
      throw SyncFailure('GET $what answered ${reply.status}: '
          '${_start(reply.body)}');
    }
    final body = jsonDecode(reply.body);
    if (body is! Map<String, dynamic> || body['resourceType'] != 'Bundle') {
      throw SyncFailure('GET $what did not answer a Bundle');
    }
    return body;
  }

  static Iterable<Map<String, dynamic>> _entries(Map<String, dynamic> b) =>
      (b['entry'] as List? ?? const []).whereType<Map<String, dynamic>>();

  /// The Bundle's `next` link, relative to the endpoint's base. The server
  /// builds it absolute from the URL it was asked on, which is under the
  /// base.
  String? _nextLink(Map<String, dynamic> bundle) {
    for (final link in (bundle['link'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      if (link['relation'] != 'next' || link['url'] is! String) continue;
      final url = link['url'] as String;
      final base = endpoint.base.toString();
      if (url.startsWith(base)) return url.substring(base.length);
      // Under another name for the same server (a configured base URL):
      // keep the path after the base's own path.
      final uri = Uri.parse(url);
      final basePath = endpoint.base.path;
      final path = uri.path.startsWith(basePath)
          ? uri.path.substring(basePath.length)
          : uri.path.replaceFirst(RegExp('^/'), '');
      return '$path${uri.hasQuery ? '?${uri.query}' : ''}';
    }
    return null;
  }

  /// `Type/id` of a history entry: from its resource, else from its
  /// request URL or fullUrl (a delete carries no resource). The key becomes
  /// a request path on both servers, so a type that is not an R4 resource
  /// type or an id outside the `id` grammar (fhir_id.dart) stops the sync:
  /// `admin/users/2/role` from a peer would otherwise be a PUT to this
  /// server's account route (review of PR #110, reproduced).
  static String? _keyOf(Map<String, dynamic> entry) {
    final key = _rawKeyOf(entry);
    if (key == null) return null;
    final slash = key.indexOf('/');
    final type = key.substring(0, slash);
    final id = key.substring(slash + 1);
    if (R4ResourceType.fromString(type) == null ||
        !fhirIdGrammar.hasMatch(id)) {
      throw SyncFailure('history entry names "$key", which is not a '
          'resource type and id');
    }
    return key;
  }

  static String? _rawKeyOf(Map<String, dynamic> entry) {
    final resource = entry['resource'];
    if (resource is Map &&
        resource['resourceType'] is String &&
        resource['id'] is String) {
      return '${resource['resourceType']}/${resource['id']}';
    }
    for (final url in [
      (entry['request'] as Map?)?['url'] as String?,
      entry['fullUrl'] as String?,
    ]) {
      if (url == null) continue;
      final parts =
          Uri.parse(url).path.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}/${parts.last}';
      }
    }
    return null;
  }

  static SyncVersion? _versionOf(Map<String, dynamic> entry) {
    final response = entry['response'] as Map?;
    final resource = entry['resource'];
    final json = resource is Map<String, dynamic> ? resource : null;
    final method = (entry['request'] as Map?)?['method'] as String?;
    final meta = json?['meta'] as Map?;
    final versionId = etagVersion(response?['etag'] as String?) ??
        meta?['versionId'] as String?;
    final modified =
        response?['lastModified'] as String? ?? meta?['lastUpdated'] as String?;
    final at = modified == null ? null : DateTime.tryParse(modified);
    if (versionId == null || at == null) return null;
    return SyncVersion(
      versionId,
      at,
      method == 'DELETE' ? null : json,
    );
  }
}

/// The version in an ETag (`W/"3"` → `3`), or null.
String? etagVersion(String? etag) {
  if (etag == null) return null;
  return RegExp('(?:W/)?"([^"]*)"').firstMatch(etag)?.group(1);
}

String _start(String body) =>
    body.length > 300 ? '${body.substring(0, 300)}…' : body;
