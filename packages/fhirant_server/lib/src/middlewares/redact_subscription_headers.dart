import 'dart:convert';

import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:shelf/shelf.dart';

/// Removes `Subscription.channel.header` from every JSON response to a caller
/// without system authority, and labels each Subscription it changed
/// REDACTED.
///
/// A rest-hook Subscription is system authority's to create or change
/// (`storeRefusal`), and its headers are what the server sends with each
/// delivery: R4B subscription.html (read whole 2026-10-17) shows
/// `"header": ["Authorization: Bearer secret-token-abc-123"]` and says
/// "Servers are responsible for ensuring appropriate security is employed
/// for each channel". Any token that could read Subscriptions read them
/// (REVIEW-2026-10-17 finding 12). Done here, on the way out, because a
/// Subscription leaves the server through reads, searches, history, Bundle
/// entries and includes alike; one step sees them all. A redacted copy
/// cannot be written back over the original by such a caller, since
/// changing a rest-hook Subscription needs the same authority.
///
/// Only bodies that are JSON and name both `"Subscription"` and `"header"`
/// are parsed; the rest pass through as they are.
Middleware redactSubscriptionHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      final principal = Principal.of(request);
      if (principal == null || principal.isSystem) return response;
      final type = response.headers['content-type'] ?? '';
      if (!type.startsWith('application/fhir+json') &&
          !type.startsWith('application/json')) {
        return response;
      }
      final body = await response.readAsString();
      if (!body.contains('"Subscription"') || !body.contains('"header"')) {
        return response.change(body: body);
      }
      final Object? json;
      try {
        json = jsonDecode(body);
      } on FormatException {
        return response.change(body: body);
      }
      if (!_redact(json)) return response.change(body: body);
      return response.change(body: jsonEncode(json));
    };
  };
}

/// The label R4B security-labels take from v3-ObservationValue: "remove any
/// portion of the resource that is not authorized to be access, used, or
/// disclosed" (hl7.terminology 6.0.2, CodeSystem-v3-ObservationValue,
/// REDACTED).
const Map<String, String> _redactedLabel = {
  'system': 'http://terminology.hl7.org/CodeSystem/v3-ObservationValue',
  'code': 'REDACTED',
  'display': 'redacted',
};

/// Removes channel headers from every Subscription under [node]; true when
/// one was removed.
bool _redact(Object? node) {
  var changed = false;
  if (node is List) {
    for (final item in node) {
      if (_redact(item)) changed = true;
    }
    return changed;
  }
  if (node is! Map<String, dynamic>) return false;
  if (node['resourceType'] == 'Subscription') {
    final channel = node['channel'];
    if (channel is Map<String, dynamic> &&
        (channel.containsKey('header') || channel.containsKey('_header'))) {
      channel
        ..remove('header')
        ..remove('_header');
      final meta = (node['meta'] as Map<String, dynamic>?) ?? {};
      final security = [...?meta['security'] as List?];
      if (!security.any((s) => s is Map && s['code'] == 'REDACTED')) {
        security.add(_redactedLabel);
      }
      node['meta'] = {...meta, 'security': security};
      changed = true;
    }
  }
  for (final value in node.values) {
    if (_redact(value)) changed = true;
  }
  return changed;
}
