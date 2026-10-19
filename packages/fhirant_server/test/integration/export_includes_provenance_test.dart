import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Bulk Data Access STU2 export.html (hl7.org/fhir/uv/bulkdata/STU2/
/// export.html, read 2026-10-17, verbatim): "If an includeAssociatedValue
/// value relevant to provenance is not specified, or if this parameter is
/// not supported by a server, the server SHALL include all available
/// Provenance resources whose Provenance.target is a resource in the Patient
/// compartment in a patient level export request". REVIEW-2026-10-17
/// finding 13: a Provenance targeting pat1's Observation was in neither the
/// Patient nor the Group export (Provenance joins the Patient compartment
/// only through `patient`, a target that is the Patient itself).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String exportDir;

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_export_provenance_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir, devMode: true);
    db = server.db;
    handler = server.handler;
    for (final r in <Map<String, dynamic>>[
      {'resourceType': 'Patient', 'id': 'p1'},
      {'resourceType': 'Patient', 'id': 'p2'},
      {
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p1'},
      },
      {
        'resourceType': 'Observation',
        'id': 'o2',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p2'},
      },
      {
        'resourceType': 'Observation',
        'id': 'loose',
        'status': 'final',
        'code': {'text': 'no subject'},
      },
      {
        'resourceType': 'Provenance',
        'id': 'prov-o1',
        'target': [
          {'reference': 'Observation/o1'},
        ],
        'recorded': '2026-10-17T00:00:00Z',
        'agent': [
          {
            'who': {'display': 'lab'},
          },
        ],
      },
      {
        'resourceType': 'Provenance',
        'id': 'prov-o2',
        'target': [
          {'reference': 'Observation/o2'},
        ],
        'recorded': '2026-10-17T00:00:00Z',
        'agent': [
          {
            'who': {'display': 'lab'},
          },
        ],
      },
      {
        'resourceType': 'Provenance',
        'id': 'prov-loose',
        'target': [
          {'reference': 'Observation/loose'},
        ],
        'recorded': '2026-10-17T00:00:00Z',
        'agent': [
          {
            'who': {'display': 'lab'},
          },
        ],
      },
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

  /// The ids exported per type, for the export at [path].
  Future<Map<String, List<String>>> export(String path) async {
    final kick = await handler(
      testRequest('GET', path, headers: {'prefer': 'respond-async'}),
    );
    expect(kick.statusCode, 202, reason: await kick.readAsString());
    final jobId = kick.headers['content-location']!.split('/').last;
    final done = await pollExport(handler, jobId);
    expect(done.statusCode, 200);
    final manifest =
        jsonDecode(await done.readAsString()) as Map<String, dynamic>;
    final out = <String, List<String>>{};
    for (final o in (manifest['output'] as List).cast<Map<String, dynamic>>()) {
      final file = await handler(
        testRequest('GET', Uri.parse(o['url'] as String).path),
      );
      final text = await file.readAsString();
      out[o['type'] as String] = [
        for (final line in const LineSplitter().convert(text))
          if (line.isNotEmpty)
            (jsonDecode(line) as Map<String, dynamic>)['id'] as String,
      ]..sort();
    }
    return out;
  }

  test('a patient-level export includes Provenance about its resources',
      () async {
    final got = await export(r'/Patient/$export');
    expect(got['Provenance'], ['prov-o1', 'prov-o2']);
  });

  test('a group export includes Provenance about its members only', () async {
    final got = await export(r'/Group/g1/$export');
    expect(got['Observation'], ['o1']);
    expect(got['Provenance'], ['prov-o1']);
  });

  test('_type without Provenance leaves it out; with it, it is there',
      () async {
    expect(
      (await export(r'/Patient/$export?_type=Observation'))
          .containsKey('Provenance'),
      isFalse,
    );
    expect(
      (await export(r'/Patient/$export?_type=Provenance'))['Provenance'],
      ['prov-o1', 'prov-o2'],
    );
  });
}
