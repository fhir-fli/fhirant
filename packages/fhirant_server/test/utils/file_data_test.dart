import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/file_data.dart';
import 'package:test/test.dart';

/// Every place a file can sit in a resource, for the antivirus scan (OWASP
/// ASVS 5.0.0 V5.4.3). A file reaches this server only as a base64Binary
/// value inside FHIR JSON; R4B's profiles-types and profiles-resources
/// (read 2026-10-21) give 18 elements that may hold one, among them
/// Binary.data, Attachment.data, Signature.data and every `[x]` that allows
/// base64Binary (Extension.value[x], Parameters.parameter.value[x],
/// Task.input.value[x]). The walk is by type, so each case here is a
/// different way of reaching that type, not a list the walk reads.
void main() {
  final bytes = base64.encode(utf8.encode('file content'));

  List<String> pathsIn(Map<String, dynamic> json) =>
      fileData(fhir.Resource.fromJson(json)).map((f) => f.path).toList();

  test('Binary.data', () {
    expect(
      pathsIn({'resourceType': 'Binary', 'contentType': 'x', 'data': bytes}),
      ['Binary.data'],
    );
  });

  test('an Attachment nested in a backbone element', () {
    expect(
      pathsIn({
        'resourceType': 'DocumentReference',
        'status': 'current',
        'content': [
          {
            'attachment': {'contentType': 'application/pdf', 'data': bytes},
          },
        ],
      }),
      ['DocumentReference.content.attachment.data'],
    );
  });

  test('Signature.data', () {
    expect(
      pathsIn({
        'resourceType': 'Provenance',
        'target': [
          {'reference': 'Patient/p'},
        ],
        'recorded': '2026-10-21T00:00:00Z',
        'agent': [
          {
            'who': {'reference': 'Practitioner/x'},
          },
        ],
        'signature': [
          {
            'type': [
              {'system': 'urn:iso-astm:E1762-95:2013', 'code': '1.2.840'},
            ],
            'when': '2026-10-21T00:00:00Z',
            'who': {'reference': 'Practitioner/x'},
            'data': bytes,
          },
        ],
      }),
      ['Provenance.signature.data'],
    );
  });

  test('an extension value, including a modifier extension', () {
    expect(
      pathsIn({
        'resourceType': 'Observation',
        'status': 'final',
        'code': {'text': 'x'},
        'extension': [
          {'url': 'http://example.org/a', 'valueBase64Binary': bytes},
        ],
        'modifierExtension': [
          {'url': 'http://example.org/b', 'valueBase64Binary': bytes},
        ],
      }),
      unorderedEquals([
        'Observation.extension.value',
        'Observation.modifierExtension.value',
      ]),
    );
  });

  test("a primitive's own extension", () {
    expect(
      pathsIn({
        'resourceType': 'Patient',
        'birthDate': '1970-01-01',
        '_birthDate': {
          'extension': [
            {'url': 'http://example.org/a', 'valueBase64Binary': bytes},
          ],
        },
      }),
      ['Patient.birthDate.extension.value'],
    );
  });

  test('a nested extension', () {
    expect(
      pathsIn({
        'resourceType': 'Patient',
        'extension': [
          {
            'url': 'http://example.org/outer',
            'extension': [
              {'url': 'inner', 'valueBase64Binary': bytes},
            ],
          },
        ],
      }),
      ['Patient.extension.extension.value'],
    );
  });

  test('Parameters and Task choice values', () {
    expect(
      pathsIn({
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'a', 'valueBase64Binary': bytes},
          {
            'name': 'b',
            'resource': {
              'resourceType': 'Task',
              'status': 'draft',
              'intent': 'order',
              'input': [
                {
                  'type': {'text': 'x'},
                  'valueBase64Binary': bytes,
                },
              ],
            },
          },
        ],
      }),
      unorderedEquals([
        'Parameters.parameter[0].value',
        'Parameters.parameter[1].resource.input.value',
      ]),
    );
  });

  test('a contained resource', () {
    expect(
      pathsIn({
        'resourceType': 'DocumentReference',
        'status': 'current',
        'contained': [
          {
            'resourceType': 'Binary',
            'id': 'b',
            'contentType': 'x',
            'data': bytes,
          },
        ],
        'content': [
          {
            'attachment': {'url': '#b'},
          },
        ],
      }),
      ['DocumentReference.contained.data'],
    );
  });

  test('every value, not only the first', () {
    expect(
      pathsIn({
        'resourceType': 'DocumentReference',
        'status': 'current',
        'content': [
          for (var i = 0; i < 3; i++)
            {
              'attachment': {'data': bytes},
            },
        ],
      }),
      [
        'DocumentReference.content[0].attachment.data',
        'DocumentReference.content[1].attachment.data',
        'DocumentReference.content[2].attachment.data',
      ],
    );
  });

  test('the decoded bytes are what was sent', () {
    final found = fileData(
      fhir.Resource.fromJson(
        {'resourceType': 'Binary', 'contentType': 'x', 'data': bytes},
      ),
    ).single;
    expect(utf8.decode(found.bytes!), 'file content');
  });

  // R4B base64Binary regex `(\s*([0-9a-zA-Z\+/=]){4}\s*)+`; the published
  // binary-example.json has a space between two groups.
  test('whitespace between groups of four is allowed', () {
    final spaced = '${bytes.substring(0, 8)} \n${bytes.substring(8)}';
    final found = fileData(
      fhir.Resource.fromJson(
        {'resourceType': 'Binary', 'contentType': 'x', 'data': spaced},
      ),
    ).single;
    expect(utf8.decode(found.bytes!), 'file content');
  });

  // Why fileData's undecodable case is only a fallback: the model already
  // refuses such a value when the body is parsed, which the handlers answer
  // 400.
  test('a value that is not base64 never becomes a resource', () {
    expect(
      () => fhir.Resource.fromJson(
        {'resourceType': 'Binary', 'contentType': 'x', 'data': 'not*base64'},
      ),
      throwsFormatException,
    );
  });

  test('a resource with no file has none', () {
    expect(
      pathsIn({
        'resourceType': 'Patient',
        'name': [
          {'family': 'Doe'},
        ],
      }),
      isEmpty,
    );
  });

  // What each file declares, for the type check (ASVS V5.2.2): its type,
  // where the type sits, whether R4B requires it, and whether the value is
  // a file at all.
  List<Object> typesIn(Map<String, dynamic> json) => [
        for (final f in fileData(fhir.Resource.fromJson(json)))
          (f.path, f.isFile, f.type, f.typePath, f.typeRequired),
      ];

  test('each file carries the type its element declares', () {
    expect(
      typesIn({
        'resourceType': 'Binary',
        'contentType': 'image/png',
        'data': bytes,
      }),
      [
        ('Binary.data', true, 'image/png', 'Binary.contentType', true),
      ],
    );
    expect(
      typesIn({
        'resourceType': 'Provenance',
        'target': [
          {'reference': 'Patient/p1'},
        ],
        'recorded': '2026-10-21T10:00:00Z',
        'agent': [
          {
            'who': {'reference': 'Practitioner/x'},
          },
        ],
        'signature': [
          {
            'type': [
              {'code': 'x'},
            ],
            'when': '2026-10-21T10:00:00Z',
            'who': {'reference': 'Practitioner/x'},
            'data': bytes,
          },
        ],
      }),
      [
        (
          'Provenance.signature.data',
          true,
          null,
          'Provenance.signature.sigFormat',
          false
        ),
      ],
    );
    expect(
      typesIn({
        'resourceType': 'Patient',
        'extension': [
          {'url': 'urn:x', 'valueBase64Binary': bytes},
        ],
      }),
      [('Patient.extension.value', true, null, null, false)],
    );
  });

  test('a hash, an audit query and a barcode are not files', () {
    expect(
      typesIn({
        'resourceType': 'DocumentReference',
        'status': 'current',
        'content': [
          {
            'attachment': {
              'contentType': 'text/plain',
              'data': bytes,
              'hash': bytes,
            },
          },
        ],
      }),
      [
        (
          'DocumentReference.content.attachment.data',
          true,
          'text/plain',
          'DocumentReference.content.attachment.contentType',
          true
        ),
        ('DocumentReference.content.attachment.hash', false, null, null, false),
      ],
    );
    expect(
      typesIn({
        'resourceType': 'AuditEvent',
        'type': {'code': 'rest'},
        'recorded': '2026-10-21T10:00:00Z',
        'agent': [
          {'requestor': true},
        ],
        'source': {
          'observer': {'reference': 'Device/d'},
        },
        'entity': [
          {'query': bytes},
        ],
      }),
      [('AuditEvent.entity.query', false, null, null, false)],
    );
    expect(
      typesIn({
        'resourceType': 'Device',
        'udiCarrier': [
          {'carrierAIDC': bytes},
        ],
      }),
      [
        ('Device.udiCarrier.carrierAIDC', false, null, null, false),
      ],
    );
  });
}
