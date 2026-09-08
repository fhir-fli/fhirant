import 'package:fhirant_server/src/utils/json_patch.dart';
import 'package:test/test.dart';

/// RFC 6902 section 4.1, read 2026-09-08, on arrays: "the supplied value is
/// added to the array at the indicated location. Any elements at or above
/// the specified index are shifted one position to the right. The specified
/// index MUST NOT be greater than the number of elements in the array. If
/// the "-" character is used to index the end of the array (see [RFC6901]),
/// this has the effect of appending the value to the array."
void main() {
  Map<String, dynamic> patient() => {
        'resourceType': 'Patient',
        'id': 'p',
        'name': [
          {'family': 'A'},
          {'family': 'B'},
        ],
      };

  test('add with "-" appends (finding 21)', () {
    final out = applyJsonPatch(patient(), [
      {
        'op': 'add',
        'path': '/name/-',
        'value': {'family': 'C'},
      },
    ]);
    expect(
      (out['name'] as List).map((n) => n['family']),
      ['A', 'B', 'C'],
    );
  });

  test('add at an index inserts and shifts, it does not overwrite', () {
    final out = applyJsonPatch(patient(), [
      {
        'op': 'add',
        'path': '/name/0',
        'value': {'family': 'Z'},
      },
    ]);
    expect(
      (out['name'] as List).map((n) => n['family']),
      ['Z', 'A', 'B'],
    );
  });

  test('add at the length appends; past it is an error', () {
    final out = applyJsonPatch(patient(), [
      {
        'op': 'add',
        'path': '/name/2',
        'value': {'family': 'C'},
      },
    ]);
    expect((out['name'] as List).length, 3);
    expect(
      () => applyJsonPatch(patient(), [
        {
          'op': 'add',
          'path': '/name/5',
          'value': {'family': 'C'},
        },
      ]),
      throwsFormatException,
    );
  });

  test('add with "-" under a member that does not exist yet creates the list',
      () {
    final out = applyJsonPatch(patient(), [
      {
        'op': 'add',
        'path': '/identifier/-',
        'value': {'value': '123'},
      },
    ]);
    expect(out['identifier'], [
      {'value': '123'},
    ]);
  });

  test('replace at an index overwrites', () {
    final out = applyJsonPatch(patient(), [
      {
        'op': 'replace',
        'path': '/name/1',
        'value': {'family': 'Q'},
      },
    ]);
    expect(
      (out['name'] as List).map((n) => n['family']),
      ['A', 'Q'],
    );
  });

  test('move to "-" appends the moved element', () {
    final out = applyJsonPatch(patient(), [
      {'op': 'move', 'from': '/name/0', 'path': '/name/-'},
    ]);
    expect(
      (out['name'] as List).map((n) => n['family']),
      ['B', 'A'],
    );
  });
}
