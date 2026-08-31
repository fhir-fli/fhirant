// lib/src/core/server_core.dart
import 'dart:async';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/handlers/handlers.dart';
import 'package:fhirant_server/src/middlewares/audit_middleware.dart';
import 'package:fhirant_server/src/middlewares/auth_middleware.dart';
import 'package:fhirant_server/src/middlewares/content_negotiation.dart';
import 'package:fhirant_server/src/middlewares/cors_middleware.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:fhirant_server/src/services/websocket_subscriptions.dart';
import 'package:fhirant_server/src/utils/jwt_secret.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';
import 'package:shelf_router/shelf_router.dart';

/// A single logged HTTP request.
class RequestLogEntry {
  RequestLogEntry({
    required this.timestamp,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.durationMs,
    required this.clientIp,
  });
  final DateTime timestamp;
  final String method;
  final String path;
  final int statusCode;
  final int durationMs;
  final String clientIp;
}

/// Core server functionality without platform-specific dependencies
class FhirAntServer {
  FhirAntServer(
    this.dbInterface, {
    String? jwtSecret,
    String? exportDir,
    this.maxRequests = 10,
    this.rateLimitDuration = const Duration(seconds: 60),
    this.devMode = false,
    this.corsAllowOrigin,
  })  : exportDir = exportDir ?? 'data/export',
        _startTime = DateTime.now() {
    // Resolve the signing secret without ever falling back to a shared,
    // hardcoded value (which would let anyone forge tokens). An explicit
    // secret (e.g. from the mobile app's secure storage) or FHIRANT_JWT_SECRET
    // is used as-is; otherwise a strong per-process secret is generated.
    // Headless deployments should pass a persisted secret (see
    // JwtSecret.resolveForServer in bin/server.dart) so tokens survive
    // restarts; an unpersisted generated secret is still safe, just ephemeral.
    final envSecret = Platform.environment['FHIRANT_JWT_SECRET'];
    final secret = (jwtSecret != null && jwtSecret.isNotEmpty)
        ? jwtSecret
        : (envSecret != null && envSecret.isNotEmpty)
            ? envSecret
            : JwtSecret.generate();
    _jwtService = JwtService(secret);
  }
  final FhirAntDb dbInterface;
  final String exportDir;
  final int maxRequests;

  /// The `Access-Control-Allow-Origin` value for browser clients. Defaults to
  /// `*` — appropriate for the open LAN/native-client model (fhirant uses
  /// bearer tokens, not cookies, so this is not a CSRF vector) — but a
  /// deployment that serves a known web origin can lock it down here.
  /// Origin permitted to read this server's responses from a browser, or null
  /// to publish no cross-origin policy. See [CorsConfig.allowOrigin].
  final String? corsAllowOrigin;
  final Duration rateLimitDuration;
  late final JwtService _jwtService;
  final DateTime _startTime;
  HttpServer? _server;
  Timer? _cleanupTimer;

  /// The subscription service the router built, so the hourly cleanup can
  /// sweep finished subscriptions with it.
  SubscriptionService? _subscriptions;
  bool _isRunning = false;
  final StreamController<RequestLogEntry> _requestLogController =
      StreamController<RequestLogEntry>.broadcast();

  final bool devMode;

  bool get isRunning => _isRunning;
  int? get port => _server?.port;

  /// Stream of request log entries for live monitoring.
  Stream<RequestLogEntry> get requestLog => _requestLogController.stream;

  /// Create router with all handlers
  Router createRouter() {
    // One service for the life of the router, so rest-hook delivery reuses a
    // single HTTP client rather than building one per write, and so every
    // bound websocket is visible to every write.
    final websockets = WebSocketSubscriptions();
    final subscriptions =
        SubscriptionService(dbInterface, websockets: websockets);
    _subscriptions = subscriptions;
    final router = Router()
      // Auth routes
      ..get(
        '/auth/status',
        (Request req) => authStatusHandler(req, dbInterface),
      )
      ..post(
        '/auth/register',
        (Request req) => registerHandler(req, dbInterface, _jwtService),
      )
      ..post(
        '/auth/login',
        (Request req) => loginHandler(req, dbInterface, _jwtService),
      )
      ..post(
        '/auth/token',
        (Request req) => refreshHandler(req, dbInterface, _jwtService),
      )
      ..post('/auth/revoke', (Request req) => revokeHandler(req, dbInterface))
      ..post('/auth/logout', (Request req) => logoutHandler(req, dbInterface))
      ..get('/auth/authorize', authorizeGetHandler)
      ..post('/auth/authorize', (Request req) {
        final contentType = req.headers['content-type'] ?? '';
        if (contentType.contains('application/json')) {
          return authorizeJsonHandler(req, dbInterface);
        }
        return authorizePostHandler(req, dbInterface);
      })
      // Admin routes (protected by auth middleware — not under auth/ prefix)
      ..post('/admin/unlock/<userId>', (Request req, String userId) {
        final id = int.tryParse(userId);
        if (id == null) {
          return Response(400, body: '{"error": "Invalid user ID"}');
        }
        return unlockAccountHandler(req, id, dbInterface);
      })
      // Public routes
      ..get('/', baseHandler)
      ..get('/favicon.ico', favicoHandler)
      ..get(
        '/health',
        (Request req) => healthHandler(req, dbInterface, _startTime),
      )
      ..get('/metadata', metadataHandler)
      ..get('/.well-known/smart-configuration', smartConfigHandler)
      // Library/$evaluate (must be before generic /<resourceType>/$validate)
      ..post(
        r'/Library/<id>/$evaluate',
        (Request req, String id) =>
            libraryEvaluateHandler(req, id, dbInterface),
      )
      ..post(
        r'/Library/$evaluate',
        (Request req) => libraryEvaluateByUrlHandler(req, dbInterface),
      )
      // Validation endpoints
      ..all(
        r'/$validate',
        (Request req) => validateHandler(req, dbInterface),
      )
      ..all(
        r'/<resourceType>/$validate',
        (Request req, String resourceType) =>
            validateHandler(req, dbInterface, resourceType),
      )
      // Terminology operations
      ..get(
        r'/CodeSystem/<id>/$validate-code',
        (Request req, String id) =>
            validateCodeHandler(req, dbInterface, 'CodeSystem', id),
      )
      ..post(
        r'/CodeSystem/<id>/$validate-code',
        (Request req, String id) =>
            validateCodeHandler(req, dbInterface, 'CodeSystem', id),
      )
      ..get(
        r'/CodeSystem/$validate-code',
        (Request req) => validateCodeHandler(req, dbInterface, 'CodeSystem'),
      )
      ..post(
        r'/CodeSystem/$validate-code',
        (Request req) => validateCodeHandler(req, dbInterface, 'CodeSystem'),
      )
      ..get(
        r'/ValueSet/<id>/$validate-code',
        (Request req, String id) =>
            validateCodeHandler(req, dbInterface, 'ValueSet', id),
      )
      ..post(
        r'/ValueSet/<id>/$validate-code',
        (Request req, String id) =>
            validateCodeHandler(req, dbInterface, 'ValueSet', id),
      )
      ..get(
        r'/ValueSet/$validate-code',
        (Request req) => validateCodeHandler(req, dbInterface, 'ValueSet'),
      )
      ..post(
        r'/ValueSet/$validate-code',
        (Request req) => validateCodeHandler(req, dbInterface, 'ValueSet'),
      )
      ..get(
        r'/CodeSystem/<id>/$lookup',
        (Request req, String id) => lookupHandler(req, dbInterface, id),
      )
      ..post(
        r'/CodeSystem/<id>/$lookup',
        (Request req, String id) => lookupHandler(req, dbInterface, id),
      )
      ..get(
        r'/CodeSystem/$lookup',
        (Request req) => lookupHandler(req, dbInterface),
      )
      ..post(
        r'/CodeSystem/$lookup',
        (Request req) => lookupHandler(req, dbInterface),
      )
      // ValueSet $expand
      ..get(
        r'/ValueSet/<id>/$expand',
        (Request req, String id) => expandHandler(req, dbInterface, id),
      )
      ..post(
        r'/ValueSet/<id>/$expand',
        (Request req, String id) => expandHandler(req, dbInterface, id),
      )
      ..get(
        r'/ValueSet/$expand',
        (Request req) => expandHandler(req, dbInterface),
      )
      ..post(
        r'/ValueSet/$expand',
        (Request req) => expandHandler(req, dbInterface),
      )
      // NamingSystem $preferred-id
      ..get(
        r'/NamingSystem/$preferred-id',
        (Request req) => preferredIdHandler(req, dbInterface),
      )
      ..post(
        r'/NamingSystem/$preferred-id',
        (Request req) => preferredIdHandler(req, dbInterface),
      )
      // ConceptMap $translate
      ..get(
        r'/ConceptMap/<id>/$translate',
        (Request req, String id) => translateHandler(req, dbInterface, id),
      )
      ..post(
        r'/ConceptMap/<id>/$translate',
        (Request req, String id) => translateHandler(req, dbInterface, id),
      )
      ..get(
        r'/ConceptMap/$translate',
        (Request req) => translateHandler(req, dbInterface),
      )
      ..post(
        r'/ConceptMap/$translate',
        (Request req) => translateHandler(req, dbInterface),
      )
      // CodeSystem $subsumes
      ..get(
        r'/CodeSystem/<id>/$subsumes',
        (Request req, String id) => subsumesHandler(req, dbInterface, id),
      )
      ..post(
        r'/CodeSystem/<id>/$subsumes',
        (Request req, String id) => subsumesHandler(req, dbInterface, id),
      )
      ..get(
        r'/CodeSystem/$subsumes',
        (Request req) => subsumesHandler(req, dbInterface),
      )
      ..post(
        r'/CodeSystem/$subsumes',
        (Request req) => subsumesHandler(req, dbInterface),
      )
      // Backup/Restore endpoints
      ..post(r'/$backup', (Request req) => backupHandler(req, dbInterface))
      ..post(r'/$restore', (Request req) => restoreHandler(req, dbInterface))
      // FHIRPath endpoint - supports GET and POST
      ..get(r'/$fhirpath', (Request req) => fhirPathHandler(req, dbInterface))
      ..post(r'/$fhirpath', (Request req) => fhirPathHandler(req, dbInterface))
      // CQL endpoint (convenience)
      ..post(r'/$cql', (Request req) => cqlHandler(req, dbInterface))
      // Immunization forecasting (Cicada)
      ..post(
        r'/$immds-forecast',
        (Request req) => immdsForecastHandler(req, dbInterface),
      )
      ..post(
        r'/$immds-forecast-who',
        (Request req) => immdsForecastWhoHandler(req, dbInterface),
      )
      // Websocket channel for Subscription. R4 subscription.html: the client
      // connects here, sends `bind :id`, and the server answers `bound :id`.
      ..get('/ws', websocketHandler(websockets))
      // Mapping/Transform endpoint
      ..post(r'/$transform', (Request req) => mappingHandler(req, dbInterface))
      // Bulk Data Export endpoints
      ..get(
        r'/$export',
        (Request req) => exportKickoffHandler(
          req,
          dbInterface,
          exportDir,
        ),
      )
      ..get(
        r'/Group/<groupId>/$export',
        (Request req, String groupId) => exportKickoffHandler(
          req,
          dbInterface,
          exportDir,
          exportLevel: 'group',
          groupId: groupId,
        ),
      )
      ..get(
        r'/Patient/$export',
        (Request req) => exportKickoffHandler(
          req,
          dbInterface,
          exportDir,
          exportLevel: 'patient',
        ),
      )
      ..get(
        r'/$export-poll-status/<jobId>',
        (Request req, String jobId) =>
            exportStatusHandler(req, dbInterface, jobId),
      )
      ..delete(
        r'/$export-poll-status/<jobId>',
        (Request req, String jobId) =>
            exportDeleteHandler(req, dbInterface, exportDir, jobId),
      )
      ..get(
        r'/$export-file/<jobId>/<fileName>',
        (Request req, String jobId, String fileName) =>
            exportFileHandler(req, exportDir, jobId, fileName),
      )
      // $document operation on Composition
      ..get(
        r'/Composition/<id>/$document',
        (Request req, String id) => documentHandler(req, id, dbInterface),
      )
      // $everything operation (before history to avoid /<type>/<id>/_history match)
      ..get(
        r'/<compartmentType>/<id>/$everything',
        (Request req, String compartmentType, String id) =>
            everythingHandler(req, compartmentType, id, dbInterface),
      )
      // $meta operations (before history to avoid /<type>/<id>/_history match)
      ..get(
        r'/<resourceType>/<id>/$meta',
        (Request req, String resourceType, String id) =>
            metaHandler(req, resourceType, id, dbInterface),
      )
      ..post(
        r'/<resourceType>/<id>/$meta-add',
        (Request req, String resourceType, String id) =>
            metaAddHandler(req, resourceType, id, dbInterface),
      )
      ..post(
        r'/<resourceType>/<id>/$meta-delete',
        (Request req, String resourceType, String id) =>
            metaDeleteHandler(req, resourceType, id, dbInterface),
      )
      // History endpoints (must come before resource endpoints to match
      // correctly)
      ..get(
        '/<resourceType>/<id>/_history/<vid>',
        (Request req, String resourceType, String id, String vid) =>
            vreadResourceHandler(req, resourceType, id, vid, dbInterface),
      )
      ..get(
        '/<resourceType>/<id>/_history',
        (Request req, String resourceType, String id) =>
            resourceHistoryHandler(req, resourceType, id, dbInterface),
      )
      ..get(
        '/<resourceType>/_history',
        (Request req, String resourceType) =>
            typeHistoryHandler(req, resourceType, dbInterface),
      )
      ..get(
        '/_history',
        (Request req) => systemHistoryHandler(req, dbInterface),
      )
      // Compartment search (3-segment: /Patient/123/Observation)
      // Must come after _history routes so /<type>/<id>/_history matches first
      ..get(
        '/<compartmentType>/<compartmentId>/<resourceType>',
        (
          Request req,
          String compartmentType,
          String compartmentId,
          String resourceType,
        ) =>
            compartmentSearchHandler(
          req,
          compartmentType,
          compartmentId,
          resourceType,
          dbInterface,
        ),
      )
      // System-level POST search (before bundle handler)
      ..post(
        '/_search',
        (Request req) => postSystemSearchHandler(req, dbInterface),
      )
      // Transaction/Batch endpoint
      ..post(
        '/',
        (Request req) =>
            bundleHandler(req, dbInterface, subscriptions: subscriptions),
      )
      // Resource CRUD endpoints
      ..get(
        '/<resourceType>',
        (Request req, String resourceType) =>
            getResourcesHandler(req, resourceType, dbInterface),
      )
      // POST-based search (must come before generic POST /<resourceType>)
      ..post(
        '/<resourceType>/_search',
        (Request req, String resourceType) =>
            postSearchHandler(req, resourceType, dbInterface),
      )
      ..post(
        '/<resourceType>',
        (Request req, String resourceType) => postResourceHandler(
          req,
          resourceType,
          dbInterface,
          subscriptions: subscriptions,
        ),
      )
      ..get(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            getResourceByIdHandler(req, resourceType, id, dbInterface),
      )
      ..put(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) => putResourceHandler(
          req,
          resourceType,
          id,
          dbInterface,
          subscriptions: subscriptions,
        ),
      )
      ..patch(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            patchResourceHandler(req, resourceType, id, dbInterface),
      )
      ..delete(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            deleteResourceHandler(req, resourceType, id, dbInterface),
      )
      ..delete(
        '/<resourceType>',
        (Request req, String resourceType) =>
            conditionalDeleteHandler(req, resourceType, dbInterface),
      );

    return router;
  }

  /// Create pipeline with middleware
  Handler createHandler(Router router) {
    // Setup rate limiting
    final memoryStorage = MemStorage();
    final rateLimiter = ShelfRateLimiter(
      storage: memoryStorage,
      duration: rateLimitDuration,
      maxRequests: maxRequests,
    );

    var pipeline = const Pipeline()
        // Must run first: pins the client identity to the real connection
        // address so logging and rate limiting can't be fooled by a spoofed
        // X-Forwarded-For header.
        .addMiddleware(_trustedClientIpMiddleware())
        .addMiddleware(_logRequestsMiddleware())
        .addMiddleware(
          corsMiddleware(config: CorsConfig(allowOrigin: corsAllowOrigin)),
        )
        .addMiddleware(contentNegotiationMiddleware());

    if (devMode) {
      pipeline = pipeline.addMiddleware(_devModeMiddleware());
    } else {
      pipeline =
          pipeline.addMiddleware(authMiddleware(_jwtService, dbInterface));
    }

    return pipeline
        .addMiddleware(auditMiddleware(dbInterface))
        .addMiddleware(rateLimiter.rateLimiter())
        .addHandler(router.call);
  }

  /// Start the server with HTTP
  Future<void> startHttp(int port) async {
    if (_isRunning) return;

    final router = createRouter();
    final handler = createHandler(router);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
    );

    _isRunning = true;
    _startCleanupTimer();
    FhirantLogging().logInfo(
      'Server started at http://${_server!.address.address}:${_server!.port}',
    );
    if (devMode) {
      FhirantLogging()
          .logWarning('WARNING: Dev mode enabled — authentication is disabled');
    }
  }

  /// Start the server with HTTPS if cert/key available
  Future<void> startHttps(
    int port,
    String privateKeyPem,
    String certificatePem,
  ) async {
    if (_isRunning) return;

    final router = createRouter();
    final handler = createHandler(router);

    final securityContext = SecurityContext()
      ..useCertificateChainBytes(certificatePem.codeUnits)
      ..usePrivateKeyBytes(privateKeyPem.codeUnits);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      securityContext: securityContext,
    );

    _isRunning = true;
    _startCleanupTimer();
    FhirantLogging().logInfo(
      'Server started at https://${_server!.address.address}:${_server!.port}',
    );
    if (devMode) {
      FhirantLogging()
          .logWarning('WARNING: Dev mode enabled — authentication is disabled');
    }
  }

  /// Stop the server
  Future<void> stop() async {
    if (!_isRunning) return;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
    await _requestLogController.close();
    FhirantLogging().logInfo('Server stopped');
  }

  /// Start periodic cleanup of expired revoked tokens and finished
  /// subscriptions (every hour).
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      await dbInterface.cleanupRevokedTokens();
      // R4 calls Subscription.end "the time for the server to turn the
      // subscription off". Delivery already honours it, but without a sweep
      // the STORED status stays `active` until some unrelated write triggers
      // an evaluation, and a client reading the resource on a quiet server is
      // told `active` about a subscription that is finished.
      await _subscriptions?.sweepExpired();
    });
  }

  /// Middleware that bypasses authentication in dev mode.
  ///
  /// Injects a synthetic admin auth_user into every request so that
  /// downstream middleware (audit, scope enforcement) still functions.
  Middleware _devModeMiddleware() {
    return (Handler innerHandler) {
      return (Request request) {
        final devUser = <String, dynamic>{
          'sub': 'dev-mode',
          'username': 'dev-mode',
          'role': 'admin',
          'scopes': ['system/*.*'],
        };
        final updatedRequest = request.change(context: {'auth_user': devUser});
        return innerHandler(updatedRequest);
      };
    };
  }

  /// Overwrites any incoming `X-Forwarded-For` header with the real TCP
  /// connection address.
  ///
  /// `shelf_rate_limiter` (and our request logging) key on `X-Forwarded-For`,
  /// falling back to the connection address only when that header is absent.
  /// Since a client can send any `X-Forwarded-For` it likes, an attacker could
  /// rotate the header to get a fresh rate-limit bucket per request and defeat
  /// brute-force/DoS protection — including on `/auth/login`. Pinning the header
  /// to the connection address (available as `HttpConnectionInfo`) removes that
  /// bypass for fhirant's direct on-device/LAN deployments.
  ///
  /// NOTE: this intentionally does NOT trust an upstream proxy's
  /// `X-Forwarded-For`. If fhirant is ever run behind a trusted reverse proxy
  /// (e.g. a cloud load balancer that sets the header), this would need a
  /// proxy-allowlist so the real client IP from the header is honored there.
  Middleware _trustedClientIpMiddleware() {
    return (Handler innerHandler) {
      return (Request request) {
        final info = request.context['shelf.io.connection_info'];
        if (info is HttpConnectionInfo) {
          return innerHandler(
            request.change(
              headers: {'x-forwarded-for': info.remoteAddress.address},
            ),
          );
        }
        // No connection info to derive a real address from, so there is
        // nothing to trust — but the header cannot simply be removed either:
        // the rate limiter keys on it and casts the connection info
        // unconditionally, so its absence is a crash rather than a fallback.
        // Overwrite it with a sentinel instead. Every request that arrives
        // this way shares one rate-limit bucket, which throttles them together
        // rather than letting a caller pick their own bucket by choosing a
        // value.
        return innerHandler(
          request.change(headers: {'x-forwarded-for': 'unknown'}),
        );
      };
    };
  }

  /// Returns [uri] reduced to its shape: identifiers replaced by placeholders
  /// in the path, and every query parameter value replaced too.
  ///
  /// `/Patient/abc?name=Faulkenberry` becomes
  /// `/Patient/{id}?name=[redacted]`.
  ///
  /// This file is a debug log, not the audit trail. Who touched which record,
  /// when, and to what effect is recorded as a FHIR AuditEvent inside the
  /// encrypted database, which is where ISO 27789 wants it and where it is
  /// protected. Repeating the record identity out here would duplicate
  /// protected content into an unprotected place, and adds nothing the
  /// AuditEvent does not already hold.
  ///
  /// What is left is what this log is actually for: which operation, against
  /// which resource type, with what outcome and how long it took.
  static String _redactUri(Uri uri) {
    final segments = uri.pathSegments;
    final shaped = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      // The segment after a resource type is that resource's id; the segment
      // after _history is a version id. Operations ($…) and the parameter
      // segments themselves are structure, not identity, so they stay.
      final followsType = i > 0 &&
          segments[i - 1].isNotEmpty &&
          _isResourceType(segments[i - 1]);
      final followsHistory = i > 0 && segments[i - 1] == '_history';
      if (segment.startsWith(r'$') || segment.startsWith('_')) {
        shaped.add(segment);
      } else if (followsHistory) {
        shaped.add('{vid}');
      } else if (followsType) {
        shaped.add('{id}');
      } else {
        shaped.add(segment);
      }
    }

    final path = '/${shaped.join('/')}';
    if (uri.query.isEmpty) return path;
    final redacted =
        uri.queryParametersAll.keys.map((name) => '$name=[redacted]').join('&');
    return '$path?$redacted';
  }

  /// Whether [segment] looks like a FHIR resource type, which is the signal
  /// that whatever follows it is an identifier.
  static bool _isResourceType(String segment) =>
      segment[0].toUpperCase() == segment[0] &&
      segment[0].toLowerCase() != segment[0];

  /// Middleware for logging
  Middleware _logRequestsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final startTime = DateTime.now();
        final response = await innerHandler(request);
        final duration = DateTime.now().difference(startTime);

        final clientIp = request.headers['x-forwarded-for'] ??
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'Unknown';

        // Log the request using platform-agnostic logging.
        //
        // The URI is reduced to its shape first — see [_redactUri]. The
        // record identity belongs to the AuditEvent in the encrypted
        // database, not to a plaintext file beside it.
        FhirantLogging().logInfo(
          '${request.method} ${_redactUri(request.requestedUri)} - '
          '${response.statusCode} (${duration.inMilliseconds}ms) '
          'from $clientIp',
        );

        // Emit to the request log stream for live monitoring
        if (!_requestLogController.isClosed) {
          _requestLogController.add(
            RequestLogEntry(
              timestamp: startTime,
              method: request.method,
              path: request.requestedUri.path,
              statusCode: response.statusCode,
              durationMs: duration.inMilliseconds,
              clientIp: clientIp,
            ),
          );
        }

        return response;
      };
    };
  }
}
