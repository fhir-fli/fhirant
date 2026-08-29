import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The sockets currently bound to each subscription.
///
/// R4 subscription.html describes the websocket channel for "subscribers unable
/// to expose HTTP servers", which is the ordinary case for fhirant: the phone
/// running the server is reachable, the client watching it often is not. The
/// handshake the spec gives is:
///
/// ```text
/// client -> bind :id
/// server -> bound :id
/// server -> ping :id      (once per matching resource)
/// ```
///
/// Delivery carries **no payload**. `ping :id` says only that something the
/// subscription matches has changed; the client re-runs its own criteria to
/// find what. That is the whole protocol, and it is why nothing here needs the
/// resource itself.
class WebSocketSubscriptions {
  final Map<String, Set<WebSocketSink>> _bound = {};

  /// Subscription ids with at least one socket listening.
  Iterable<String> get boundIds => _bound.keys;

  /// The number of sockets bound to [subscriptionId].
  int socketsFor(String subscriptionId) => _bound[subscriptionId]?.length ?? 0;

  /// Handles one message from a client socket, returning what to send back, or
  /// null when the message is not part of the handshake.
  ///
  /// Kept separate from the socket plumbing so the protocol can be tested
  /// without opening one.
  String? handleMessage(String message, WebSocketSink sink) {
    final trimmed = message.trim();
    if (!trimmed.startsWith('bind ')) {
      // The spec defines `bind` from the client and nothing else. An unknown
      // message is ignored rather than answered, so a client cannot be misled
      // into thinking it bound.
      return null;
    }
    final id = trimmed.substring('bind '.length).trim().replaceFirst(':', '');
    if (id.isEmpty) {
      return null;
    }
    _bound.putIfAbsent(id, () => <WebSocketSink>{}).add(sink);
    return 'bound $id';
  }

  /// Drops [sink] from every subscription it was bound to.
  void release(WebSocketSink sink) {
    for (final id in _bound.keys.toList()) {
      final sinks = _bound[id]!..remove(sink);
      if (sinks.isEmpty) {
        _bound.remove(id);
      }
    }
  }

  /// Sends `ping :id` to every socket bound to [subscriptionId].
  ///
  /// Returns the number of sockets written to. A subscription nobody is bound
  /// to is not an error: the client may reconnect later, and the spec has no
  /// notion of a queued websocket notification.
  int ping(String subscriptionId) {
    final sinks = _bound[subscriptionId];
    if (sinks == null || sinks.isEmpty) {
      return 0;
    }
    var delivered = 0;
    for (final sink in sinks.toList()) {
      try {
        sink.add('ping $subscriptionId');
        delivered++;
      } catch (e) {
        // A socket that has gone away must not stop the others.
        FhirantLogging().logError('Websocket ping failed, dropping socket', e);
        sinks.remove(sink);
      }
    }
    if (sinks.isEmpty) {
      _bound.remove(subscriptionId);
    }
    return delivered;
  }
}
