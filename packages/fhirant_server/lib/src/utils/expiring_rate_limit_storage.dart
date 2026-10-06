import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';
// `IpItem`, the type of `MemStorage.items`'s values and of `add`'s return,
// is not exported by the package (shelf_rate_limiter.dart exports the
// limiter, BaseStorage and MemStorage only), so overriding `add` needs the
// file that defines it.
// ignore: implementation_imports
import 'package:shelf_rate_limiter/src/models.dart';

/// The rate limiter's in-memory storage, with eviction.
///
/// `shelf_rate_limiter` 1.0.1's `MemStorage` (its `memory_storage.dart`,
/// read 2026-10-06) keeps one `IpItem` per client address for the life of
/// the process: `resetAll` and `resetIp` reset counts, nothing removes a
/// key. On a LAN that is a handful of entries; on an address the internet
/// can reach, one per distinct source for ever (REVIEW-2026-10-06 finding
/// 15). This storage drops the entries whose window has passed, once the
/// map has grown past [sweepAt] since the last sweep, so it holds at most
/// the addresses seen within one window plus [sweepAt].
class ExpiringMemStorage extends MemStorage {
  /// Creates the storage; see [sweepAt].
  ExpiringMemStorage({this.sweepAt = 1000});

  /// How many entries may accumulate between sweeps. A thousand is a
  /// choice: a sweep is one pass over the map, and a map of a thousand
  /// items is well under a megabyte.
  final int sweepAt;

  int _sizeAtLastSweep = 0;

  @override
  IpItem add(String key, Duration duration) {
    if (items.length - _sizeAtLastSweep >= sweepAt) {
      final now = DateTime.now();
      items.removeWhere((_, item) => !item.resetAt.isAfter(now));
      _sizeAtLastSweep = items.length;
    }
    return super.add(key, duration);
  }
}
