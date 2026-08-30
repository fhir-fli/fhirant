import 'dart:async';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/websocket_subscriptions.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:http/http.dart' as http;

/// A criteria string split into the type it watches and the search it runs.
typedef ParsedCriteria = ({
  fhir.R4ResourceType resourceType,
  Map<String, List<String>> parameters,
});

/// Evaluates `Subscription` criteria against resources as they are written and
/// delivers notifications.
///
/// R4 subscription.html: criteria "are search strings interpreted identically
/// to REST API queries", so this parses them with the same
/// [SearchParameterParser] the REST endpoint uses and runs them through the
/// same database search. A criteria string that behaves one way as a GET and
/// another way here would be a defect the spec explicitly rules out.
///
/// Matching is done by running the criteria **with `_id` pinned to the resource
/// that just changed**. One resource either comes back or does not, which is
/// exactly the question, and it reuses the search engine rather than
/// reimplementing parameter semantics beside it.
///
/// 🛑 No notification is sent for a delete. That is the spec's rule, not an
/// omission: "there is no notification when a resource is deleted, or when a
/// resource is updated so that it no longer meets the criteria."
class SubscriptionService {
  /// Creates a service over [db], optionally with an injected [httpClient] so
  /// rest-hook delivery can be tested without a network.
  SubscriptionService(
    this.db, {
    http.Client? httpClient,
    DateTime Function()? clock,
    WebSocketSubscriptions? websockets,
    this.maxConsecutiveFailures = 5,
  })  : _http = httpClient ?? http.Client(),
        websockets = websockets ?? WebSocketSubscriptions(),
        _clock = clock ?? DateTime.now;

  /// The database subscriptions are read from and status written back to.
  final FhirAntDb db;
  final http.Client _http;
  final DateTime Function() _clock;

  /// The sockets clients have bound, for the websocket channel.
  final WebSocketSubscriptions websockets;

  /// Consecutive delivery failures before a subscription is switched `off`.
  ///
  /// 🛑 **This number is fhirant's policy, not a specification rule.** R4
  /// subscription.html delegates it: "The server **may** retry the notification
  /// a fixed number of times", and "If a subscription fails consistently a
  /// server **may** choose set the subscription status to off and stop trying
  /// to send notifications." There is no mandated count, interval or
  /// escalation.
  ///
  /// Five is chosen to ride out a subscriber restarting or a phone changing
  /// network, while stopping a permanently dead endpoint from being dialled on
  /// every single write. Configurable because the right number depends on the
  /// deployment, not on the standard.
  final int maxConsecutiveFailures;

  /// Where the consecutive-failure count is kept.
  ///
  /// R4 has no element for it: `Subscription.error` is `0..1` free text, "a
  /// record of the LAST error". An extension is the mechanism the standard
  /// provides for server data it does not itself model, and this one is under
  /// our own namespace so it can never be mistaken for an HL7 extension.
  /// It persists in the stored resource on purpose — an in-memory counter
  /// would reset every time the phone backgrounds the server, so a dead
  /// endpoint would never reach the threshold.
  static const failureCountExtensionUrl =
      'http://fhirant.fhir-fli.dev/StructureDefinition/'
      'subscription-consecutive-failures';

  /// Channel types this server delivers to. A subscription asking for anything
  /// else is refused at activation rather than accepted and silently ignored,
  /// so a client is never told a subscription is `active` when nothing will
  /// ever be sent.
  static const supportedChannels = {'rest-hook', 'websocket'};

  /// Splits a criteria string into its resource type and search parameters.
  ///
  /// Returns null when the type is unknown, which the caller reports as the
  /// reason a subscription cannot be activated.
  static ParsedCriteria? parseCriteria(String criteria) {
    final trimmed = criteria.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final split = trimmed.indexOf('?');
    final typeName = split == -1 ? trimmed : trimmed.substring(0, split);
    final query = split == -1 ? '' : trimmed.substring(split + 1);

    final resourceType = fhir.R4ResourceType.fromString(typeName);
    if (resourceType == null) {
      return null;
    }

    // Uri.splitQueryString handles the percent-decoding and the & splitting,
    // then the shared parser applies FHIR's own parameter rules.
    final raw =
        query.isEmpty ? <String, String>{} : Uri.splitQueryString(query);
    final parsed = SearchParameterParser.parseQueryParameters(raw);
    final parameters =
        (parsed['searchParams'] as Map<String, List<String>>?) ?? {};
    return (resourceType: resourceType, parameters: parameters);
  }

  /// Whether [changed] satisfies [subscription]'s criteria.
  Future<bool> matches(
    fhir.Subscription subscription,
    fhir.Resource changed,
  ) async {
    final id = changed.id?.valueString;
    if (id == null || id.isEmpty) {
      return false;
    }
    final criteria = parseCriteria(subscription.criteria.valueString ?? '');
    if (criteria == null) {
      return false;
    }
    if (criteria.resourceType != changed.resourceType) {
      return false;
    }
    final hits = await db.search(
      resourceType: criteria.resourceType,
      searchParameters: {
        ...criteria.parameters,
        '_id': [id],
      },
    );
    return hits.isNotEmpty;
  }

  /// Decides whether the server can honour [subscription], and writes the
  /// resulting status back.
  ///
  /// R4 subscription.html: the client creates a subscription as `requested`,
  /// and the server moves it to `active` once it has validated that it can
  /// process it. A subscription it cannot process becomes `error` with the
  /// reason in `Subscription.error`, so the client is never told a
  /// subscription is live when nothing will ever be delivered.
  Future<fhir.Subscription> activate(fhir.Subscription subscription) async {
    final status = subscription.status.valueString;
    if (status == 'off') {
      return subscription;
    }

    final criteria = parseCriteria(subscription.criteria.valueString ?? '');
    if (criteria == null) {
      return _withStatus(
        subscription,
        'error',
        'criteria is not a search on a known resource type: '
            '${subscription.criteria.valueString}',
      );
    }

    final channelType = subscription.channel.type.valueString;
    if (!supportedChannels.contains(channelType)) {
      return _withStatus(
        subscription,
        'error',
        'channel.type "$channelType" is not supported by this server; '
            'supported: ${supportedChannels.join(", ")}',
      );
    }

    // A websocket subscription needs no endpoint: the client dials the server
    // and binds by id, so there is nothing for the server to connect out to.
    final endpoint = subscription.channel.endpoint?.valueString;
    if (channelType == 'rest-hook' &&
        (endpoint == null || Uri.tryParse(endpoint) == null)) {
      return _withStatus(
        subscription,
        'error',
        'a rest-hook channel needs channel.endpoint to be a URL',
      );
    }

    if (_hasEnded(subscription)) {
      return _withStatus(subscription, 'off', null);
    }

    return _withStatus(subscription, 'active', null);
  }

  /// Delivers [changed] to every active subscription whose criteria it meets.
  ///
  /// Never throws: a subscriber that is unreachable must not fail the write
  /// that triggered the notification. A delivery failure is recorded on the
  /// subscription itself, which is what `Subscription.error` is for.
  Future<void> onResourceChanged(fhir.Resource changed) async {
    try {
      // `error` is deliverable, not terminal. R4 subscription.html: "The
      // server may retry the notification a fixed number of times", and "If
      // the notification succeeds, the server should update the status to
      // active again" — neither is reachable if a subscription in `error` is
      // never dialled again. Only `off` (given up) and `requested` (not yet
      // accepted by the server) are excluded.
      final stored = await db.search(
        resourceType: fhir.R4ResourceType.Subscription,
        searchParameters: {
          'status': ['active', 'error'],
        },
      );
      for (final resource in stored.whereType<fhir.Subscription>()) {
        if (_hasEnded(resource)) {
          await db.saveResource(_withStatus(resource, 'off', null));
          continue;
        }
        if (!await matches(resource, changed)) {
          continue;
        }
        await _deliver(resource, changed);
      }
    } catch (e, stack) {
      // A failure here means notifications were missed, never that the write
      // failed. Logged rather than swallowed silently.
      FhirantLogging().logError('Subscription evaluation failed', e, stack);
    }
  }

  /// Sends one notification, and records the outcome on the subscription.
  Future<void> _deliver(
    fhir.Subscription subscription,
    fhir.Resource changed,
  ) async {
    if (subscription.channel.type.valueString == 'websocket') {
      // The whole websocket protocol is `ping :id`. No payload travels over the
      // socket; the client re-runs its own criteria to find what changed. A
      // subscription nobody is bound to is not a failure — the client may
      // reconnect, and the spec has no queued websocket notification — so this
      // never marks the subscription in error.
      websockets.ping(subscription.id?.valueString ?? '');
      return;
    }

    final endpoint = subscription.channel.endpoint?.valueString;
    if (endpoint == null) {
      return;
    }
    final payload = subscription.channel.payload?.valueString;
    final headers = _headers(subscription);

    try {
      final http.Response response;
      if (payload == null || payload.isEmpty) {
        // "the server POSTs an empty body to the endpoint", and the client
        // then re-runs its own criteria to find what changed.
        response = await _http.post(Uri.parse(endpoint), headers: headers);
      } else {
        // "the server forwards a copy of any matching resource ... as an
        // Update operation using the nominated URL as the service base".
        final type = changed.resourceType.name;
        final id = changed.id?.valueString ?? '';
        response = await _http.put(
          Uri.parse('${endpoint.replaceAll(RegExp(r"/+$"), "")}/$type/$id'),
          headers: {...headers, 'Content-Type': payload},
          body: changed.toJsonString(),
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _recordSuccess(subscription);
        return;
      }
      await _recordFailure(
        subscription,
        'delivery to $endpoint returned ${response.statusCode}',
      );
    } catch (e) {
      await _recordFailure(subscription, 'delivery to $endpoint failed: $e');
    }
  }

  /// "If the notification succeeds, the server should update the status to
  /// active again." The failure count goes back to zero with it, so five
  /// failures spread over a year never add up to a shutdown.
  Future<void> _recordSuccess(fhir.Subscription subscription) async {
    if (subscription.error == null && _failureCount(subscription) == 0) {
      return;
    }
    await db.saveResource(
      _withFailureCount(_withStatus(subscription, 'active', null), 0),
    );
  }

  /// "If the notification fails, the server should set the status to error and
  /// mark the error in the resource", and after
  /// [maxConsecutiveFailures] of them this server stops trying.
  Future<void> _recordFailure(
    fhir.Subscription subscription,
    String message,
  ) async {
    final failures = _failureCount(subscription) + 1;
    final givenUp = failures >= maxConsecutiveFailures;
    final withStatus = _withStatus(
      subscription,
      givenUp ? 'off' : 'error',
      givenUp
          ? '$message (switched off after $failures consecutive failures)'
          : message,
    );
    await db.saveResource(_withFailureCount(withStatus, failures));
  }

  int _failureCount(fhir.Subscription subscription) {
    for (final extension in subscription.extension_ ?? <fhir.FhirExtension>[]) {
      if (extension.url.valueString == failureCountExtensionUrl) {
        return (extension.valueX as fhir.FhirInteger?)?.valueInt ?? 0;
      }
    }
    return 0;
  }

  fhir.Subscription _withFailureCount(
    fhir.Subscription subscription,
    int failures,
  ) {
    final others = (subscription.extension_ ?? <fhir.FhirExtension>[])
        .where((e) => e.url.valueString != failureCountExtensionUrl)
        .toList();
    return subscription.copyWith(
      extension_: [
        ...others,
        if (failures > 0)
          fhir.FhirExtension(
            url: fhir.FhirString(failureCountExtensionUrl),
            valueX: fhir.FhirInteger(failures),
          ),
      ],
    );
  }

  /// The extra headers a subscription asks to be sent.
  ///
  /// `channel.header` is `0..*` of "additional headers / information to send as
  /// part of the notification", written as a single string per header. Split on
  /// the FIRST colon, because a value may contain one.
  Map<String, String> _headers(fhir.Subscription subscription) {
    final headers = <String, String>{};
    for (final entry in subscription.channel.header ?? <fhir.FhirString>[]) {
      final raw = entry.valueString;
      if (raw == null) {
        continue;
      }
      final colon = raw.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      headers[raw.substring(0, colon).trim()] = raw.substring(colon + 1).trim();
    }
    return headers;
  }

  /// Whether `Subscription.end`, "the time for the server to turn the
  /// subscription off", has passed.
  bool _hasEnded(fhir.Subscription subscription) {
    final end = subscription.end?.valueDateTime;
    return end != null && !end.isAfter(_clock());
  }

  fhir.Subscription _withStatus(
    fhir.Subscription subscription,
    String status,
    String? error,
  ) {
    return subscription.copyWith(
      status: fhir.SubscriptionStatusCodes(status),
      error: error?.toFhirString,
    );
  }
}
