import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/services/websocket_subscriptions.dart';
import 'package:fhirant_server/src/utils/stored_resource.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

/// Upgrades a request to the websocket a `Subscription` binds over.
///
/// This file was empty for the life of the repo and `handlers.dart` exported it
/// anyway, which read as a half-built feature where there was none at all.
///
/// R4 subscription.html gives the handshake: the client connects, sends
/// `bind :id`, and the server answers `bound :id`. Thereafter the server sends
/// `ping :id` whenever a resource matching that subscription's criteria is
/// written. No payload travels over the socket; the client re-runs its own
/// criteria to find what changed.
///
/// A socket binds a stored Subscription only when its token may read that
/// Subscription, the rule every read uses (REVIEW-2026-10-17 finding 11:
/// one account's socket was bound to another's Subscription and received
/// its pings). FHIR defines no owner of a Subscription, so readability is
/// the test. An id that is not stored binds as before: REVIEW_DECISIONS.md,
/// A16.6, reverted the existence check (2026-09-19). A refused bind is not
/// answered, as an unknown message is not.
Handler websocketHandler(WebSocketSubscriptions registry, FhirAntDb db) {
  return (Request request) {
    final principal = Principal.of(request);
    Future<bool> mayBind(String message) async {
      final trimmed = message.trim();
      if (!trimmed.startsWith('bind ') || principal == null) return true;
      final id = trimmed.substring('bind '.length).trim().replaceFirst(':', '');
      if (id.isEmpty) return true;
      if (authorizeRequest(principal, 'GET', 'Subscription/$id') != null) {
        return false;
      }
      final lookup = await lookupStoredFor(
        principal,
        db,
        'Subscription',
        id,
        permission: 'r',
      );
      return lookup is StoredFound || lookup is StoredAbsent;
    }

    return webSocketHandler((webSocket, _) {
      final sink = webSocket.sink;
      webSocket.stream.asyncMap((message) async {
        if (message is! String) return null;
        if (!await mayBind(message)) {
          FhirantLogging().logInfo('Websocket bind refused');
          return null;
        }
        return registry.handleMessage(message, sink);
      }).listen(
        (reply) {
          if (reply != null) {
            sink.add(reply);
            FhirantLogging().logInfo('Websocket $reply');
          }
        },
        onDone: () => registry.release(sink),
        onError: (Object e) {
          FhirantLogging().logError('Websocket error, releasing sockets', e);
          registry.release(sink);
        },
        cancelOnError: true,
      );
    })(request);
  };
}
