import 'dart:async';
import 'dart:math';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/services/disk_space.dart';
import 'package:shelf/shelf.dart';

/// What a request will write to the disk the store lives on.
enum StorageNeed {
  /// Nothing, or a few rows the server needs to let anyone in: reads,
  /// searches, operations that compute and store nothing, sign-in and
  /// account management, cancelling an export.
  none,

  /// A clinical write: create, update, patch, delete (a delete keeps the
  /// resource's history and adds a version), a transaction or batch,
  /// `$meta-add`/`$meta-delete`. Also every request this list does not
  /// name: an unknown write is a write.
  record,

  /// `$export`: files about the size of every current resource.
  export,

  /// `$backup`: a copy of the whole database, written before it is sent.
  backup,

  /// `$reindex`: the search index tables built again beside the old.
  reindex,

  /// `$restore`: the upload, then what restoring it adds to the store.
  restore,
}

/// Operations that compute an answer and store nothing, by their last path
/// segment. Each was read for a store write (`saveResource`, a file); none
/// has one.
const _computeOnly = {
  r'$validate',
  r'$validate-code',
  r'$lookup',
  r'$expand',
  r'$preferred-id',
  r'$translate',
  r'$subsumes',
  r'$fhirpath',
  r'$cql',
  r'$evaluate',
  r'$immds-forecast',
  r'$immds-forecast-who',
  r'$transform',
};

/// The [StorageNeed] of [method] on [path] (`request.url.path`, no leading
/// slash).
StorageNeed storageNeedOf(String method, String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final last = segments.isEmpty ? '' : segments.last;
  switch (method.toUpperCase()) {
    case 'GET':
    case 'HEAD':
    case 'OPTIONS':
      return last == r'$export' ? StorageNeed.export : StorageNeed.none;
    case 'DELETE':
      // Cancelling an export deletes its files.
      return path.startsWith(r'$export-poll-status/')
          ? StorageNeed.none
          : StorageNeed.record;
  }
  if (last == '_search' || _computeOnly.contains(last)) {
    return StorageNeed.none;
  }
  if (path.startsWith('auth/') || path.startsWith('admin/')) {
    return StorageNeed.none;
  }
  return switch (path) {
    r'$backup' => StorageNeed.backup,
    r'$restore' => StorageNeed.restore,
    r'$reindex' => StorageNeed.reindex,
    _ => StorageNeed.record,
  };
}

/// Keeps enough of the disk free that the phone keeps working and its
/// record can still be taken off it (OWASP ASVS 5.0.0 V5.2.4, L3: "a
/// single user cannot fill up the storage").
///
/// Two amounts are kept free.
///
/// - The phone's own: Android counts a volume as low on storage below 5%
///   of its size or 500 MiB, whichever is smaller (AOSP `StorageManager`
///   `getStorageLowBytes`: `DEFAULT_STORAGE_THRESHOLD_PERCENT_LOW = 5`,
///   `DEFAULT_THRESHOLD_MAX_BYTES = 500 MiB`; read 2026-11-01). A device
///   can tune that line in its settings; these are the defaults, used on
///   every platform.
/// - Room to export every current resource, so `$export` can always run:
///   the size of the current resources' JSON, which is about what an export
///   writes. History is not counted; an export does not carry it.
///
/// A clinical write is refused when it would leave less than both. A
/// write that takes a lot of disk at once (`$export`, `$backup`,
/// `$reindex`, `$restore`) is refused when it would not fit above the
/// phone's line: `$export` is what the second amount is kept for.
///
/// The current resources' size is summed from the store at the first
/// request, again every hour, and added to by each write accepted in
/// between (its body, an upper bound: an update replaces a version).
/// Summed over 928,935 MIMIC resources on a laptop: 0.66 s warm, 2.88 s
/// cold (`tool/review_2026-10-17/storage_floor/sum_cost.txt`).
class StorageFloor {
  StorageFloor(this.db, this.path, {DiskSpace? disk})
      : disk = disk ?? StatvfsDiskSpace();

  final FhirAntDb db;

  /// A path on the filesystem the store and its exports live on.
  final String path;
  final DiskSpace disk;

  /// The most free space Android keeps for itself: 500 MiB.
  static const int lowLineMaxBytes = 500 * 1024 * 1024;

  /// The share of the volume Android keeps free, in percent.
  static const int lowLinePercent = 5;

  /// The phone's own line for a volume of [total] bytes.
  static int lowLine(int total) =>
      min(total * lowLinePercent ~/ 100, lowLineMaxBytes);

  Future<int>? _active;
  int _addedSinceSum = 0;
  bool _warnedUnmeasured = false;

  /// The current resources' JSON, in bytes.
  Future<int> activeBytes() async =>
      await (_active ??= _sumActive()) + _addedSinceSum;

  /// Sums the current resources again; the hourly sweep calls it.
  Future<void> refresh() async {
    final sum = _sumActive();
    await sum;
    _active = sum;
    _addedSinceSum = 0;
  }

  /// [bytes] more were written and accepted.
  void wrote(int bytes) => _addedSinceSum += bytes;

  Future<int> _sumActive() async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(LENGTH(CAST(resource AS BLOB))), 0) AS n '
          'FROM resources',
        )
        .getSingle();
    return row.data['n'] as int;
  }

  /// The database file's pages in use, in bytes.
  Future<int> _databaseBytes() async {
    Future<int> pragma(String name) async =>
        (await db.customSelect('PRAGMA $name').getSingle()).data.values.first
            as int;
    final pageSize = await pragma('page_size');
    return (await pragma('page_count') - await pragma('freelist_count')) *
        pageSize;
  }

  /// Why [need] with a body of [incoming] bytes is refused, or null when
  /// it fits. Null too when this platform cannot be asked how much is free
  /// ([DiskSpace.measure]): logged once, never guessed. And null when the
  /// store cannot be asked how much it holds: the request goes on to the
  /// handler, which meets the same store and answers for it
  /// (store_failure_carries_cause_test), rather than a 507 that would name
  /// the disk for a fault that is not the disk's.
  Future<String?> refusal(StorageNeed need, int incoming) async {
    if (need == StorageNeed.none) return null;
    try {
      return await _refusal(need, incoming);
    } on Object catch (e, stack) {
      // A failed sum is not kept: the next request sums again.
      _active = null;
      FhirantLogging().logWarning(
        'Storage floor: the store could not be measured',
        e,
        stack,
      );
      return null;
    }
  }

  Future<String?> _refusal(StorageNeed need, int incoming) async {
    final usage = disk.measure(path);
    if (usage == null) {
      if (!_warnedUnmeasured) {
        _warnedUnmeasured = true;
        FhirantLogging().logWarning(
          'Storage floor: free space cannot be read on this platform; '
          'writes are not checked against it.',
        );
      }
      return null;
    }
    final line = lowLine(usage.total);
    final (needed, keep, what) = switch (need) {
      StorageNeed.record => (
          incoming,
          line + await activeBytes(),
          'the phone keeps ${_mib(line)} MiB free and this server keeps '
              '${_mib(await activeBytes())} MiB more, the room an export of '
              'every current resource needs',
        ),
      StorageNeed.export => (
          await activeBytes(),
          line,
          'an export of every current resource needs about '
              '${_mib(await activeBytes())} MiB and the phone keeps '
              '${_mib(line)} MiB free',
        ),
      StorageNeed.backup || StorageNeed.reindex => (
          await _databaseBytes(),
          line,
          'it writes about ${_mib(await _databaseBytes())} MiB, the size '
              'of the database, and the phone keeps ${_mib(line)} MiB free',
        ),
      // The upload, then at most as much again in the store: derived from
      // what a restore does, not measured.
      StorageNeed.restore => (
          2 * incoming,
          line,
          'the upload and restoring it need about '
              '${_mib(2 * incoming)} MiB and the phone keeps ${_mib(line)} '
              'MiB free',
        ),
      StorageNeed.none => (0, 0, ''),
    };
    if (usage.free - needed >= keep) return null;
    return 'Not enough free space: ${_mib(usage.free)} MiB is free, and '
        '$what. Reading, searching and \$export go on working; free space on '
        'this device, or move its record elsewhere, and send this again.';
  }

  static String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);
}

/// Refuses a request [floor] says will not fit with 507 Insufficient
/// Storage and a `no-store` OperationOutcome.
///
/// RFC 4918 §11.5 (rfc-editor.org text, read 2026-11-02, verbatim): "The
/// 507 (Insufficient Storage) status code means the method could not be
/// performed on the resource because the server is unable to store the
/// representation needed to successfully complete the request. This
/// condition is considered to be temporary." R4B issue-type `no-store`
/// (CodeSystem-issue-type.json): "The persistent store is unavailable; e.g.
/// the database is down for maintenance or similar action, and the
/// interaction or operation cannot be processed", under `transient`: "may be
/// able to resubmit the same content once an underlying issue is resolved".
///
/// Inside the authentication check: a caller with no credential learns
/// nothing about the disk.
Middleware storageFloorMiddleware(StorageFloor floor) {
  return (Handler inner) {
    return (Request request) async {
      final need = storageNeedOf(request.method, request.url.path);
      final incoming = request.contentLength ?? 0;
      final why = await floor.refusal(need, incoming);
      if (why != null) return outcomeResponse(507, 'no-store', why);
      final response = await inner(request);
      if (need == StorageNeed.record && response.statusCode < 300) {
        floor.wrote(incoming);
      }
      return response;
    };
  };
}
