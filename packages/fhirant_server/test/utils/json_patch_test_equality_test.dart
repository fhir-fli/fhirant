import 'package:fhirant_server/src/utils/json_patch.dart';
import 'package:test/test.dart';

/// RFC 6902 §4.6 (read 2026-10-06), on `test`: "objects: are considered
/// equal if they contain the same number of members, and if each member can
/// be considered equal to a member in the other object, by comparing their
/// keys (as strings) and their values (using this list of type-specific
/// rules)"; "numbers: are considered equal if their values are numerically
/// equal". The operation compared the JSON encodings, so key order and
/// `1` against `1.0` failed it (REVIEW-2026-10-06 finding 8, probe P5).
void main() {
  final document = <String, dynamic>{
    'a': {'x': 1, 'y': 2},
    'list': [
      1,
      'two',
      {'k': true},
    ],
    'n': 1,
    'nothing': null,
  };

  Map<String, dynamic> testOp(String path, Object? value) =>
      {'op': 'test', 'path': path, 'value': value};

  test('an object with the same members in another order is equal', () {
    expect(
      () => applyJsonPatch(document, [
        testOp('/a', {'y': 2, 'x': 1}),
      ]),
      returnsNormally,
    );
  });

  test('a number is equal to a numerically equal number', () {
    expect(
      () => applyJsonPatch(document, [testOp('/n', 1.0)]),
      returnsNormally,
    );
  });

  test('arrays compare element by element, in order', () {
    expect(
      () => applyJsonPatch(document, [
        testOp('/list', [
          1,
          'two',
          {'k': true},
        ]),
      ]),
      returnsNormally,
    );
    expect(
      () => applyJsonPatch(document, [
        testOp('/list', [
          'two',
          1,
          {'k': true},
        ]),
      ]),
      throwsFormatException,
    );
  });

  test('a member that is absent is not equal to one that is null', () {
    expect(
      () => applyJsonPatch(document, [testOp('/nothing', null)]),
      returnsNormally,
    );
    expect(
      () => applyJsonPatch(document, [
        testOp('/a', {'x': 1, 'y': 2, 'z': null}),
      ]),
      throwsFormatException,
    );
  });

  test('a different value still fails the test', () {
    expect(
      () => applyJsonPatch(document, [
        testOp('/a', {'x': 1, 'y': 3}),
      ]),
      throwsFormatException,
    );
    expect(
      () => applyJsonPatch(document, [testOp('/n', '1')]),
      throwsFormatException,
    );
  });
}
