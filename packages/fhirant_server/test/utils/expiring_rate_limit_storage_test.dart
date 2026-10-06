import 'package:fhirant_server/src/utils/expiring_rate_limit_storage.dart';
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';
import 'package:test/test.dart';

/// REVIEW-2026-10-06 finding 15: `shelf_rate_limiter` 1.0.1's `MemStorage`
/// never removes a key, so the limiter held one entry per client address
/// for the life of the process. [ExpiringMemStorage] drops entries whose
/// window has passed once the map has grown by `sweepAt` since the last
/// sweep.
void main() {
  test('the package storage keeps every address (the finding)', () async {
    final storage = MemStorage();
    for (var i = 0; i < 50; i++) {
      storage.add('10.0.0.$i', const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    storage.add('10.0.1.1', const Duration(milliseconds: 1));
    expect(storage.items.length, 51);
  });

  test('expired entries are dropped once the map has grown by sweepAt',
      () async {
    final storage = ExpiringMemStorage(sweepAt: 50);
    for (var i = 0; i < 50; i++) {
      storage.add('10.0.0.$i', const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Grown by sweepAt: the next add sweeps first, then stores its own key.
    storage.add('10.0.1.1', const Duration(minutes: 1));
    expect(storage.items.keys, ['10.0.1.1']);
  });

  test('entries still inside their window survive a sweep', () async {
    final storage = ExpiringMemStorage(sweepAt: 10)
      ..add('live', const Duration(minutes: 1));
    // Nineteen short-lived keys: the map sweeps once at ten entries
    // (nothing has expired yet), reaches twenty, and the next add is the
    // sweep that is due.
    for (var i = 0; i < 19; i++) {
      storage.add('gone.$i', const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    storage.add('new', const Duration(minutes: 1));
    expect(storage.items.keys.toSet(), {'live', 'new'});
  });

  test('a known address keeps its count through a sweep', () {
    final storage = ExpiringMemStorage()
      ..add('a', const Duration(minutes: 1))
      ..add('a', const Duration(minutes: 1));
    expect(storage.getItem('a')!.accessCount, 2);
  });
}
