import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.11.2, read 2026-10-18: "Servers SHALL replace all
/// matching links in the bundle, whether they are found in the resource ids,
/// resource references, elements of type uri, url, oid, uuid, and <a href=""
/// & <img src="" in the narrative." and "References to resources that are
/// not part of the bundle are left untouched." REVIEW-2026-10-17 (smaller
/// list): a `urn:uuid` in a narrative `href` was stored as written.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db);
  });

  tearDown(() => db.close());

  const patientUrn = 'urn:uuid:7f3c2a90-0b1e-4c55-9a51-3d2f6e8b1c04';
  const outsideUrn = 'urn:uuid:0d9e4b17-55aa-4f0c-8e6b-a1c2d3e4f5a6';

  Map<String, dynamic> observation(String div) => {
        'resourceType': 'Observation',
        'status': 'final',
        'code': {'text': 'Potassium'},
        'subject': {'reference': patientUrn},
        'text': {'status': 'generated', 'div': div},
      };

  /// Posts a transaction of a Patient at [patientUrn] and [second], and
  /// returns the Patient's new reference and the second entry as stored.
  Future<(String, Map<String, dynamic>)> transact(
    Map<String, dynamic> second, {
    Map<String, dynamic>? secondRequest,
  }) async {
    final bundle = {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'fullUrl': patientUrn,
          'resource': {
            'resourceType': 'Patient',
            'name': [
              {'family': 'Narrative'},
            ],
          },
          'request': {'method': 'POST', 'url': 'Patient'},
        },
        {
          'resource': second,
          'request': secondRequest ?? {'method': 'POST', 'url': 'Observation'},
        },
      ],
    };
    final r = await handler(
      testRequest(
        'POST',
        '/',
        body: jsonEncode(bundle),
        headers: {'content-type': 'application/fhir+json'},
        authToken: token,
      ),
    );
    final body = await r.readAsString();
    expect(r.statusCode, 200, reason: body);
    final entries = (jsonDecode(body) as Map)['entry'] as List;
    // `Type/id`, from a location that may be absolute and versioned.
    String reference(int i) {
      final location =
          ((entries[i] as Map)['response'] as Map)['location'] as String;
      final segments = Uri.parse(location).pathSegments;
      final at = segments.indexOf('_history');
      final path = at < 0 ? segments : segments.sublist(0, at);
      return path.sublist(path.length - 2).join('/');
    }

    final patientRef = reference(0);
    // An update's response need not carry a location; its URL names it.
    final secondRef =
        secondRequest == null ? reference(1) : secondRequest['url'] as String;
    final stored = await handler(
      testRequest('GET', '/$secondRef', authToken: token),
    );
    return (
      patientRef,
      jsonDecode(await stored.readAsString()) as Map<String, dynamic>,
    );
  }

  String xhtml(String inner) =>
      '<div xmlns="http://www.w3.org/1999/xhtml">$inner</div>';

  String div(Map<String, dynamic> resource) =>
      (resource['text'] as Map)['div'] as String;

  test('an <a href> to an entry in the bundle is rewritten', () async {
    final (patient, obs) = await transact(
      observation(
        xhtml('<a href="$patientUrn">the patient</a>'),
      ),
    );
    expect(div(obs), contains('href="$patient"'));
    expect(div(obs), isNot(contains('urn:uuid')));
    expect((obs['subject'] as Map)['reference'], patient);
  });

  test('an <img src> to an entry in the bundle is rewritten', () async {
    final (patient, obs) = await transact(
      observation(
        xhtml('<img src="$patientUrn" alt="photo"/>'),
      ),
    );
    expect(div(obs), contains('src="$patient"'));
    expect(div(obs), isNot(contains('urn:uuid')));
  });

  test('a single-quoted href is rewritten too', () async {
    final (patient, obs) = await transact(
      observation(
        xhtml("<a href='$patientUrn'>the patient</a>"),
      ),
    );
    expect(div(obs), contains("href='$patient'"));
    expect(div(obs), isNot(contains('urn:uuid')));
  });

  test('every matching link in one narrative is rewritten', () async {
    final (patient, obs) = await transact(
      observation(
        xhtml(
          '<a href="$patientUrn">one</a> <a href="$patientUrn">two</a> '
          '<img src="$patientUrn"/>',
        ),
      ),
    );
    expect(div(obs), isNot(contains('urn:uuid')));
    expect(RegExp(RegExp.escape(patient)).allMatches(div(obs)), hasLength(3));
  });

  test('the narrative of a PUT entry is rewritten', () async {
    final (patient, obs) = await transact(
      {
        ...observation(
          xhtml('<a href="$patientUrn">the patient</a>'),
        ),
        'id': 'narrative-put',
      },
      secondRequest: {'method': 'PUT', 'url': 'Observation/narrative-put'},
    );
    expect(div(obs), contains('href="$patient"'));
    expect(div(obs), isNot(contains('urn:uuid')));
  });

  test('a link to something outside the bundle is left untouched', () async {
    final (_, obs) = await transact(
      observation(
        xhtml('<a href="$outsideUrn">elsewhere</a>'),
      ),
    );
    expect(div(obs), contains('href="$outsideUrn"'));
  });

  test('the urn in narrative text, not a link, is left as written', () async {
    // The rule names href and src; prose that quotes an id is not a link.
    final (_, obs) = await transact(
      observation(
        xhtml('<p>Bundle entry $patientUrn</p>'),
      ),
    );
    expect(div(obs), contains('<p>Bundle entry $patientUrn</p>'));
  });
}
