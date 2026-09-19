import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/fhir_id.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The sockets currently bound to each subscription.
///
/// R4B subscription.html 2.46.8.2 WebSockets (read whole 2026-09-19,
/// verbatim) gives the protocol: "Client sends a bind :id message over the
/// socket (using the logical id of the subscription). For example, the
/// client might issue: bind 123)." · "Server responds with a "bound :id"
/// message to acknowledge." · "Server sends a "ping :id" message to notify
/// the client each time a new result is available". The channel is for
/// subscribers unable to expose HTTP servers, which is the ordinary case
/// for fhirant: the phone running the server is reachable, the client
/// watching it often is not.
///
/// Delivery carries **no payload**. `ping :id` says only that something the
/// subscription matches has changed; the client re-runs its own criteria to
/// find what. That is the whole protocol, and it is why nothing here needs the
/// resource itself.
///
/// The spec defines no refusal message, so a bind that is not accepted is
/// not acknowledged: the client never sees `bound`. A bind is accepted when
/// the id is a FHIR id, [exists] (when given) says the Subscription is
/// stored, and the socket holds fewer than [maxBindsPerSocket] ids. Before
/// this, any id, any number of them, bound (REVIEW-2026-09-17 A16): a
/// socket could fill the registry with ids that name nothing.
class WebSocketSubscriptions {
  WebSocketSubscriptions({
    this.exists,
    this.maxBindsPerSocket = 16,
  });

  /// Whether a Subscription with this logical id is stored. Null (tests of
  /// the protocol alone) accepts any well-formed id.
  final Future<bool> Function(String id)? exists;

  /// How many distinct subscriptions one socket may bind. A chosen ceiling,
  /// not a measured one: a client watches a handful of subscriptions, and a
  /// registry entry costs memory per bind for as long as the socket lives.
  final int maxBindsPerSocket;

  final Map<String, Set<WebSocketSink>> _bound = {};

  /// Subscription ids with at least one socket listening.
  Iterable<String> get boundIds => _bound.keys;

  /// The number of sockets bound to [subscriptionId].
  int socketsFor(String subscriptionId) => _bound[subscriptionId]?.length ?? 0;

  /// The number of distinct subscriptions [sink] is bound to.
  int bindsOf(WebSocketSink sink) =>
      _bound.values.where((sinks) => sinks.contains(sink)).length;

  /// Handles one message from a client socket, returning what to send back, or
  /// null when the message is not part of the handshake or the bind is not
  /// accepted.
  ///
  /// Kept separate from the socket plumbing so the protocol can be tested
  /// without opening one.
  Future<String?> handleMessage(String message, WebSocketSink sink) async {
    final trimmed = message.trim();
    if (!trimmed.startsWith('bind ')) {
      // The spec defines `bind` from the client and nothing else. An unknown
      // message is ignored rather than answered, so a client cannot be misled
      // into thinking it bound.
      return null;
    }
    final id = trimmed.substring('bind '.length).trim().replaceFirst(':', '');
    if (id.isEmpty || !isFhirId(id)) {
      return null;
    }
    final already = _bound[id]?.contains(sink) ?? false;
    if (!already && bindsOf(sink) >= maxBindsPerSocket) {
      FhirantLogging().logWarning(
        'Websocket bind $id refused: the socket holds $maxBindsPerSocket',
      );
      return null;
    }
    if (!already && exists != null && !await exists!(id)) {
      FhirantLogging().logInfo('Websocket bind $id refused: no Subscription');
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
