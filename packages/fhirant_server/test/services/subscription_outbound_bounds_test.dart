import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// OWASP ASVS 5.0.0 V4.2.5 (L3, read 2026-10-21, verbatim): "Verify that,
/// if the application (backend or frontend) builds and sends requests, it
/// uses validation, sanitization, or other mechanisms to avoid creating URIs
/// (such as for API calls) or HTTP request header fields (such as
/// Authorization or Cookie), which are too long to be accepted by the
/// receiving component." A rest-hook delivery sends the client's
/// `channel.header` lines and `channel.endpoint`; a 64 KiB header went out
/// whole (tool/review_2026-10-17/outbound_crlf_probe.tsv).
///
/// The bound is 8190 bytes a line: Apache httpd 2.4's defaults,
/// "LimitRequestFieldSize 8190" and "LimitRequestLine 8190" (core.html,
/// read 2026-10-21); nginx's default "large_client_header_buffers 4 8k"
/// refuses a request line or a header field longer than one buffer
/// (ngx_http_core_module.html, read 2026-10-21).
void main() {
  late FhirAntDb db;
  late SubscriptionService service;

  setUp(() {
    db = FhirAntDb(NativeDatabase.memory());
    service = SubscriptionService(
      db,
      httpClient: MockClient((_) async => http.Response('', 200)),
    );
  });
  tearDown(() async => db.close());

  fhir.Subscription subscription({
    String endpoint = 'https://example.org/hook',
    String? payload,
    List<String>? header,
  }) =>
      fhir.Subscription.fromJson({
        'resourceType': 'Subscription',
        'id': 's1',
        'status': 'requested',
        'reason': 'test',
        'criteria': 'Observation',
        'channel': {
          'type': 'rest-hook',
          'endpoint': endpoint,
          if (payload != null) 'payload': payload,
          if (header != null) 'header': header,
        },
      });

  Future<fhir.Subscription> activate(fhir.Subscription s) =>
      service.activate(s);

  // "x-test: " is 8 bytes on the wire; the value fills the line.
  String headerLine(int bytes) => 'X-Test: ${'a' * (bytes - 8)}';

  test('a header line of 8190 bytes is accepted, 8191 is refused', () async {
    final fits = await activate(subscription(header: [headerLine(8190)]));
    expect(fits.status.valueString, 'active', reason: '${fits.error}');
    final over = await activate(subscription(header: [headerLine(8191)]));
    expect(over.status.valueString, 'error');
    expect(over.error?.valueString, contains('8190'));
  });

  test('a header with CR or LF inside is refused', () async {
    for (final h in ['X-Test: a\r\nInjected: b', 'X-Test: a\nInjected: b']) {
      final s = await activate(subscription(header: [h]));
      expect(s.status.valueString, 'error', reason: h);
    }
  });

  // "POST " + target + " HTTP/1.1": 14 bytes besides the target.
  test('an endpoint whose POST line is 8190 bytes is accepted, 8191 refused',
      () async {
    String endpoint(int line) => 'https://example.org/${'p' * (line - 14 - 1)}';
    final fits = await activate(subscription(endpoint: endpoint(8190)));
    expect(fits.status.valueString, 'active', reason: '${fits.error}');
    final over = await activate(subscription(endpoint: endpoint(8191)));
    expect(over.status.valueString, 'error');
    expect(over.error?.valueString, contains('8190'));
  });

  // With a payload each delivery is "PUT <endpoint>/<type>/<id> HTTP/1.1";
  // the longest R4B type name and a 64-character id (R4B datatypes.html id)
  // must fit.
  test('with a payload, the longest type and id must fit too', () async {
    final longestType = fhir.R4ResourceType.values
        .map((t) => t.toString().length)
        .reduce((a, b) => a > b ? a : b);
    const room = 8190 - 4 - 9; // 'PUT ' and ' HTTP/1.1'
    final pathFits = room - 1 - longestType - 1 - 64;
    final fits = await activate(
      subscription(
        endpoint: 'https://example.org/${'p' * (pathFits - 1)}',
        payload: 'application/fhir+json',
      ),
    );
    expect(fits.status.valueString, 'active', reason: '${fits.error}');
    final over = await activate(
      subscription(
        endpoint: 'https://example.org/${'p' * pathFits}',
        payload: 'application/fhir+json',
      ),
    );
    expect(over.status.valueString, 'error');
  });
}
