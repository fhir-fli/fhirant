import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/websocket_subscriptions.dart';
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
Handler websocketHandler(WebSocketSubscriptions registry) {
  return webSocketHandler((webSocket, _) {
    final sink = webSocket.sink;
    webSocket.stream.listen(
      (message) {
        if (message is! String) {
          return;
        }
        final reply = registry.handleMessage(message, sink);
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
  });
}
