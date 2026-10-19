import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Bulk Data Access STU2 export.html (hl7.org/fhir/uv/bulkdata/STU2/
/// export.html, read 2026-10-18, verbatim): "Binary Resources whose content
/// is associated with an individual patient SHALL be serialized as
/// DocumentReference Resources with the content.attachment element populated
/// as described in the Attachments section below. Binary Resources not
/// associated with an individual patient MAY be included in a System Level
/// export." Attachments: "When populated, the url element SHALL be an
/// absolute url that can be de-referenced to the attachment's content."
///
/// R4B binary.html (read 2026-10-18) says how a Binary is tied to a patient:
/// it "is generally used as the target in the Attachment data type to
/// reference content via the .url element, such as in the DocumentReference
/// and Media resources", and securityContext tells the server "that the
/// Binary resource should be treated as if it was the other resource".
/// REVIEW-2026-10-17 (smaller list): a system export wrote every Binary to
/// Binary.ndjson, and a relative `Binary/x` attachment url went out as is.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String exportDir;

  const base = 'http://localhost:8080';

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_export_binary_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir, devMode: true);
    db = server.db;
    handler = server.handler;
    Map<String, dynamic> binary(String id, [String? context]) => {
          'resourceType': 'Binary',
          'id': id,
          'contentType': 'text/plain',
          'data': base64Encode(utf8.encode('content of $id')),
          if (context != null) 'securityContext': {'reference': context},
        };
    Map<String, dynamic> attachment(String url) =>
        {'contentType': 'text/plain', 'url': url};
    for (final r in <Map<String, dynamic>>[
      {
        'resourceType': 'Patient',
        'id': 'p1',
        'photo': [attachment('Binary/b-photo')],
      },
      // Named by a patient's DocumentReference, and its security context.
      binary('b-doc', 'DocumentReference/d1'),
      {
        'resourceType': 'DocumentReference',
        'id': 'd1',
        'status': 'current',
        'subject': {'reference': 'Patient/p1'},
        'content': [
          {'attachment': attachment('Binary/b-doc')},
        ],
      },
      // Named by a patient's DocumentReference by absolute url only.
      binary('b-ref'),
      {
        'resourceType': 'DocumentReference',
        'id': 'd2',
        'status': 'current',
        'subject': {'reference': 'Patient/p1'},
        'content': [
          {'attachment': attachment('$base/Binary/b-ref')},
        ],
      },
      // The patient's by security context, and named by no attachment.
      binary('b-pat', 'Patient/p1'),
      // Named by the patient's photo, and by an extension's attachment.
      binary('b-photo'),
      binary('b-ext'),
      {
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'wound photo'},
        'subject': {'reference': 'Patient/p1'},
        'extension': [
          {
            'url': 'http://example.org/fhir/StructureDefinition/photo',
            'valueAttachment': attachment('Binary/b-ext'),
          },
        ],
      },
      // No patient: a DocumentReference with no subject or author is in no
      // Patient compartment, and a Binary nothing names.
      binary('b-loose'),
      {
        'resourceType': 'DocumentReference',
        'id': 'd3',
        'status': 'current',
        'content': [
          {'attachment': attachment('Binary/b-loose')},
          {'attachment': attachment('https://elsewhere.example/doc.pdf')},
        ],
      },
      binary('b-free'),
      {
        'resourceType': 'Group',
        'id': 'g1',
        'type': 'person',
        'actual': true,
        'member': [
          {
            'entity': {'reference': 'Patient/p1'},
          },
        ],
      },
    ]) {
      await db.saveResource(fhir.Resource.fromJson(r));
    }
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// The resources exported per type, by id, for the export at [path].
  Future<Map<String, Map<String, Map<String, dynamic>>>> export(
    String path,
  ) async {
    final kick = await handler(
      testRequest('GET', path, headers: {'prefer': 'respond-async'}),
    );
    expect(kick.statusCode, 202, reason: await kick.readAsString());
    final jobId = kick.headers['content-location']!.split('/').last;
    Response? done;
    for (var i = 0; i < 100; i++) {
      final r = await handler(
        testRequest('GET', '/\$export-poll-status/$jobId'),
      );
      if (r.statusCode != 202) {
        done = r;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(done?.statusCode, 200);
    final manifest =
        jsonDecode(await done!.readAsString()) as Map<String, dynamic>;
    final out = <String, Map<String, Map<String, dynamic>>>{};
    for (final o in (manifest['output'] as List).cast<Map<String, dynamic>>()) {
      final file = await handler(
        testRequest('GET', Uri.parse(o['url'] as String).path),
      );
      final text = await file.readAsString();
      out[o['type'] as String] = {
        for (final line in const LineSplitter().convert(text))
          if (line.isNotEmpty)
            (jsonDecode(line) as Map<String, dynamic>)['id'] as String:
                jsonDecode(line) as Map<String, dynamic>,
      };
    }
    return out;
  }

  List<String> urls(Map<String, dynamic> documentReference) => [
        for (final c in documentReference['content'] as List)
          ((c as Map)['attachment'] as Map)['url'] as String,
      ];

  test('a system export leaves out every Binary tied to a patient', () async {
    final got = await export(r'/$export');
    expect(got['Binary']!.keys.toList()..sort(), ['b-free', 'b-loose']);
  });

  test('_type=Binary alone still leaves them out', () async {
    // The tie is read from the store, not from what the job exports.
    final got = await export(r'/$export?_type=Binary');
    expect(got['Binary']!.keys.toList()..sort(), ['b-free', 'b-loose']);
  });

  test('a relative attachment url goes out absolute, at every level', () async {
    for (final path in [
      r'/$export',
      r'/Patient/$export',
      r'/Group/g1/$export',
    ]) {
      final got = await export(path);
      final docs = got['DocumentReference']!;
      expect(urls(docs['d1']!), ['$base/Binary/b-doc'], reason: path);
      expect(urls(docs['d2']!), ['$base/Binary/b-ref'], reason: path);
      final photo = (got['Patient']!['p1']!['photo'] as List).single as Map;
      expect(photo['url'], '$base/Binary/b-photo', reason: path);
      final ext =
          (got['Observation']!['o1']!['extension'] as List).single as Map;
      expect(
        (ext['valueAttachment'] as Map)['url'],
        '$base/Binary/b-ext',
        reason: path,
      );
    }
  });

  test('an absolute url elsewhere is left as written', () async {
    final got = await export(r'/$export');
    expect(urls(got['DocumentReference']!['d3']!), [
      '$base/Binary/b-loose',
      'https://elsewhere.example/doc.pdf',
    ]);
  });

  test('the exported url dereferences to the content', () async {
    final got = await export(r'/Patient/$export');
    final url = urls(got['DocumentReference']!['d1']!).single;
    final r = await handler(testRequest('GET', Uri.parse(url).path));
    expect(r.statusCode, 200);
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    expect(body['id'], 'b-doc');
    expect(
      utf8.decode(base64Decode(body['data'] as String)),
      'content of b-doc',
    );
  });

  test('control: nothing in the store is changed by the export', () async {
    await export(r'/$export');
    final d1 =
        (await db.getResource(fhir.R4ResourceType.DocumentReference, 'd1'))!
            .toJson();
    expect(urls(d1), ['Binary/b-doc']);
  });
}
