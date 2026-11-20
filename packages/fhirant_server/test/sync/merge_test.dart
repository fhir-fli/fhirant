import 'package:fhirant_server/src/sync/merge.dart';
import 'package:test/test.dart';

/// The merge rule of `$sync`, with the clocks set by the test.
///
/// Grey, 2026-11-19: a field changed on one side takes that change; a field
/// both sides changed takes the newer save, by each server's own clock.
void main() {
  DateTime t(int minute) => DateTime.utc(2026, 11, 19, 10, minute);

  Map<String, dynamic> patient(Map<String, dynamic> fields) => {
        'resourceType': 'Patient',
        'id': 'p1',
        ...fields,
      };

  SyncVersion v(String id, int minute, Map<String, dynamic>? fields) =>
      SyncVersion(id, t(minute), fields == null ? null : patient(fields));

  const base = {
    'gender': 'female',
    'birthDate': '1980-01-01',
    'name': [
      {'family': 'Okello'},
    ],
  };

  test('a field changed on one side only takes that change', () {
    final local = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 5, {...base, 'gender': 'other'}),
      ],
    );
    final remote = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 3, {...base, 'birthDate': '1980-01-02'}),
      ],
    );
    final merged = mergeResource(local: local, remote: remote);
    expect(merged.json!['gender'], 'other');
    expect(merged.json!['birthDate'], '1980-01-02');
    expect(merged.conflicts, isEmpty);
  });

  test('a field both sides changed takes the newer save, either way round', () {
    SyncMerge run({required int localAt, required int remoteAt}) =>
        mergeResource(
          local: SyncSide(
            base: v('1', 0, base),
            since: [
              v('2', localAt, {...base, 'birthDate': '1981-01-01'}),
            ],
          ),
          remote: SyncSide(
            base: v('1', 0, base),
            since: [
              v('4', remoteAt, {...base, 'birthDate': '1982-01-01'}),
            ],
          ),
        );

    final localNewer = run(localAt: 9, remoteAt: 4);
    expect(localNewer.json!['birthDate'], '1981-01-01');
    expect(localNewer.conflicts.single.winner, SyncSource.local);
    expect(localNewer.conflicts.single.field, 'birthDate');

    final remoteNewer = run(localAt: 4, remoteAt: 9);
    expect(remoteNewer.json!['birthDate'], '1982-01-01');
    expect(remoteNewer.conflicts.single.winner, SyncSource.remote);
  });

  test(
      'the time of a field is the save that gave it its value, not the '
      'latest save', () {
    // Local set birthDate at minute 2 and saved something else at 9; the
    // peer set birthDate at 5. The peer's birthDate is newer.
    final local = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 2, {...base, 'birthDate': '1981-01-01'}),
        v('3', 9, {...base, 'birthDate': '1981-01-01', 'gender': 'male'}),
      ],
    );
    final remote = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 5, {...base, 'birthDate': '1982-01-01'}),
      ],
    );
    final merged = mergeResource(local: local, remote: remote);
    expect(merged.json!['birthDate'], '1982-01-01');
    expect(merged.json!['gender'], 'male');
  });

  test('a field changed and changed back counts as unchanged', () {
    final local = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 7, {...base, 'gender': 'male'}),
        v('3', 8, base),
      ],
    );
    final remote = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 1, {...base, 'gender': 'other'}),
      ],
    );
    expect(
      mergeResource(local: local, remote: remote).json!['gender'],
      'other',
    );
  });

  test('a field removed on one side is removed', () {
    final local = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 3, {'gender': 'female', 'name': base['name']}),
      ],
    );
    final remote = SyncSide(base: v('1', 0, base), since: const []);
    expect(
      mergeResource(local: local, remote: remote).json!.containsKey(
            'birthDate',
          ),
      isFalse,
    );
  });

  test('a list is one field', () {
    final local = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 3, {
          ...base,
          'name': [
            {'family': 'Okello'},
            {'family': 'Akello'},
          ],
        }),
      ],
    );
    final remote = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 6, {
          ...base,
          'name': [
            {
              'family': 'Okello',
              'given': ['Grace'],
            },
          ],
        }),
      ],
    );
    final merged = mergeResource(local: local, remote: remote);
    expect(merged.json!['name'], [
      {
        'family': 'Okello',
        'given': ['Grace'],
      },
    ]);
    expect(merged.conflicts.single.field, 'name');
  });

  test('a resource only one side has is copied', () {
    final local = SyncSide(since: [v('1', 2, base)]);
    const remote = SyncSide(since: []);
    expect(mergeResource(local: local, remote: remote).json, patient(base));
    expect(mergeResource(local: remote, remote: local).json, patient(base));
  });

  test("a delete newer than the other side's last change stands", () {
    final deleted = SyncSide(
      base: v('1', 0, base),
      since: [v('2', 8, null)],
    );
    final edited = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 4, {...base, 'gender': 'male'}),
      ],
    );
    expect(mergeResource(local: deleted, remote: edited).json, isNull);
    expect(mergeResource(local: edited, remote: deleted).json, isNull);
  });

  test("an edit newer than the other side's delete brings it back", () {
    final deleted = SyncSide(
      base: v('1', 0, base),
      since: [v('2', 4, null)],
    );
    final edited = SyncSide(
      base: v('1', 0, base),
      since: [
        v('2', 8, {...base, 'gender': 'male'}),
      ],
    );
    expect(
      mergeResource(local: deleted, remote: edited).json!['gender'],
      'male',
    );
    expect(
      mergeResource(local: edited, remote: deleted).json!['gender'],
      'male',
    );
  });

  test('a delete with no change on the other side stands', () {
    final deleted = SyncSide(
      base: v('1', 0, base),
      since: [v('2', 4, null)],
    );
    final untouched = SyncSide(base: v('1', 0, base), since: const []);
    expect(mergeResource(local: untouched, remote: deleted).json, isNull);
  });

  test("values that differ with neither side changed take the peer's", () {
    // An earlier sync wrote its merge to the peer but not here.
    final local = SyncSide(
      base: v('3', 5, {...base, 'gender': 'male'}),
      since: const [],
    );
    final remote = SyncSide(
      base: v('7', 6, {...base, 'gender': 'other'}),
      since: const [],
    );
    expect(
      mergeResource(local: local, remote: remote).json!['gender'],
      'other',
    );
  });

  test('meta.source and tags are fields; versionId and lastUpdated are not',
      () {
    final local = SyncSide(
      base: v('1', 0, base),
      since: [
        SyncVersion('2', t(3), {
          ...patient(base),
          'meta': {
            'versionId': '2',
            'lastUpdated': '2026-11-19T10:03:00Z',
            'source': 'http://a.example',
          },
        }),
      ],
    );
    final remote = SyncSide(
      base: v('1', 0, base),
      since: [
        SyncVersion('9', t(4), {
          ...patient(base),
          'meta': {
            'versionId': '9',
            'lastUpdated': '2026-11-19T10:04:00Z',
            'tag': [
              {'system': 'http://t', 'code': 'x'},
            ],
          },
        }),
      ],
    );
    final meta =
        mergeResource(local: local, remote: remote).json!['meta'] as Map;
    expect(meta['source'], 'http://a.example');
    expect(meta['tag'], [
      {'system': 'http://t', 'code': 'x'},
    ]);
    expect(meta.containsKey('versionId'), isFalse);
    expect(meta.containsKey('lastUpdated'), isFalse);
  });

  test('with no base, a differing field takes the side that set it later', () {
    final local = SyncSide(
      since: [
        v('1', 1, base),
        v('2', 6, {...base, 'gender': 'male'}),
      ],
    );
    final remote = SyncSide(
      since: [
        v('1', 3, {...base, 'gender': 'other'}),
      ],
    );
    expect(mergeResource(local: local, remote: remote).json!['gender'], 'male');
  });
}
