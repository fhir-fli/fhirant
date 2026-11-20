import 'dart:async';
import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/storage_floor.dart';
import 'package:fhirant_server/src/sync/merge.dart';
import 'package:fhirant_server/src/sync/sync_endpoint.dart';

/// Resource types a sync leaves alone, each with why.
///
/// - `AuditEvent`: each server's record of what was done to it. No client
///   may write one, an administrator included (`authorizeRequest`), so the
///   peer refuses them; and each sync's writes add AuditEvents on the peer,
///   which a sync copying them would carry back, without end.
/// - `Subscription`: where this server sends its own notifications. The
///   server decides its `status` (R4 subscription.html: a client creates it
///   `requested`), so each side would rewrite the other's on every sync,
///   and both would notify the same endpoint.
const syncSkippedTypes = {'AuditEvent', 'Subscription'};

/// Counts and findings of one sync.
class SyncReport {
  /// Resources either side changed since the last sync, minus
  /// [syncSkippedTypes].
  int considered = 0;

  /// Of those, already the same on both sides as the last sync left them.
  int unchanged = 0;

  /// Written to the peer (created, updated or brought back).
  int writtenToPeer = 0;

  /// Written here.
  int writtenHere = 0;

  /// Deleted on the peer.
  int deletedOnPeer = 0;

  /// Deleted here.
  int deletedHere = 0;

  /// Fields both sides changed, each decided by the later save.
  final List<String> conflicts = [];

  /// Resources one side changed while the sync was writing them (412);
  /// the next sync takes them up again.
  final List<String> retryLater = [];

  /// Resources a side refused to write, with its answer; the next sync
  /// tries them again.
  final List<String> failures = [];
}

/// One `$sync` run against one peer.
class SyncJob {
  SyncJob._(this.peer);

  /// The peer's base URL.
  final String peer;

  /// When the sync began.
  final DateTime started = DateTime.now();

  /// When it ended, null while running.
  DateTime? finished;

  /// What it did so far.
  final SyncReport report = SyncReport();

  /// Why it stopped early, null when it ran through or is running.
  String? error;

  /// Whether it is still running.
  bool get running => finished == null;
}

/// The `$sync` job of this process: one at a time.
class SyncJobs {
  SyncJob? _current;

  /// The job running or last finished, or null when none was run.
  SyncJob? get current => _current;

  /// Starts a sync unless one is running; returns it, or null when one is
  /// already running.
  SyncJob? start({
    required FhirAntDb db,
    required String peer,
    required SyncClient local,
    required SyncClient remote,
    StorageFloor? floor,
    void Function()? onDone,
  }) {
    if (_current?.running ?? false) return null;
    final job = SyncJob._(peer);
    _current = job;
    unawaited(
      Synchronizer(
        db: db,
        peer: peer,
        local: local,
        remote: remote,
        floor: floor,
        report: job.report,
      ).run().then(
        (_) {},
        onError: (Object e, StackTrace st) {
          job.error = '$e';
          FhirantLogging().logError('\$sync with $peer failed', e, st);
        },
      ).whenComplete(() {
        job.finished = DateTime.now();
        onDone?.call();
      }),
    );
    return job;
  }
}

/// What a history scan showed of one resource on one side: its newest
/// version id (null when the entry carried none) and whether that version
/// is a delete.
typedef _Seen = ({String? versionId, bool deleted});

/// A resource on its way to the other side in a batch: its key, the JSON,
/// the version it was copied from, and its size in bytes.
typedef _Copy = ({
  String key,
  Map<String, dynamic> json,
  String source,
  int bytes,
});

/// Brings this server and a peer to the same content for every resource
/// either changed since the last sync between them.
///
/// Both sides' histories since the last sync are read page by page
/// (`_history?_since`, R4B http.html §3.1.0.12), this side's first. Three
/// kinds of resource come out of that read:
///
/// - Unchanged: the newest version each side shows is the one the last
///   sync left it at (`sync_pairs`), or the side shows none. A sync's own
///   writes are of this kind on the next run. Nothing more is read.
/// - A copy: both sides were read whole (no earlier sync, or a clock set
///   back) and only one side ever had the resource. Its newest version, in
///   the page already read, is written to the other side in batches
///   (R4B http.html §3.1.0.11), which is what a first sync mostly is: a
///   first sync of 10,000 that read each resource's history and wrote each
///   on its own took 1,227 s (tool/sync_cost_2026-11-20/RESULTS.md). The
///   Android FHIR SDK uploads the same way, in Bundles of up to 500
///   (android-fhir 28a5034, UploadStrategy.forBundleRequest).
/// - Everything else: both sides' histories of it are read, each split at
///   the version the last sync left it at, merged ([mergeResource]), the
///   result written to the peer, then here, and the versions both now hold
///   recorded. The peer is written first: when the peer takes the merge and
///   this side cannot (it changed in between, 412), the peer holds the
///   merge and the next sync's rule for "neither changed, different
///   values" (take the peer's) carries it here. When the peer cannot take
///   it, nothing is recorded and the next sync starts over.
///
/// The history cursors move only when every resource went through: a
/// refused write is tried again next time rather than skipped for good.
class Synchronizer {
  /// Creates one run.
  Synchronizer({
    required this.db,
    required this.peer,
    required this.local,
    required this.remote,
    required this.report,
    this.floor,
  });

  /// This server's store, for the sync bookkeeping.
  final FhirAntDb db;

  /// The peer's base URL, the key of the bookkeeping.
  final String peer;

  /// This server.
  final SyncClient local;

  /// The peer.
  final SyncClient remote;

  /// What the run did.
  final SyncReport report;

  /// This server's storage floor, checked before each write here.
  final StorageFloor? floor;

  /// The most bytes of resources one batch carries: under the 16 MiB body
  /// a fhirant peer takes by default (`maxRequestBody`), with room for the
  /// Bundle around them. A larger resource goes in a batch of its own.
  static const int batchBytes = 4 * 1024 * 1024;

  final List<_Copy> _toHere = [];
  final List<_Copy> _toPeer = [];
  int _toHereBytes = 0;
  int _toPeerBytes = 0;

  static bool _skipped(String key) =>
      syncSkippedTypes.contains(key.split('/').first);

  /// Runs the sync.
  Future<void> run() async {
    final cursor = await db.syncCursor(peer);

    final seenHere = <String, _Seen>{};
    final here = await local.scan(cursor?.localSince, (key, version) {
      seenHere.putIfAbsent(
        key,
        () =>
            (versionId: version?.versionId, deleted: version?.deleted ?? false),
      );
    });

    final seenThere = <String, _Seen>{};
    final copied = <String>{};
    final there = await remote.scan(cursor?.remoteSince, (key, version) async {
      if (seenThere.containsKey(key)) return;
      seenThere[key] =
          (versionId: version?.versionId, deleted: version?.deleted ?? false);
      // Only the peer ever had it: its newest version, read just now.
      if (here.whole &&
          !_skipped(key) &&
          !seenHere.containsKey(key) &&
          version != null &&
          !version.deleted) {
        copied.add(key);
        await _queue(key, version, toPeer: false);
      }
    });
    await _flush(toPeer: false);

    if (here.whole && there.whole) {
      // Only this side ever had it. The whole history is read again rather
      // than held from the first read: holding every resource's JSON for a
      // store the size of MIMIC-IV (928,935 resources) is not needed when
      // the second read is in process.
      final pushed = <String>{};
      await local.scan(null, (key, version) async {
        if (!pushed.add(key) ||
            _skipped(key) ||
            seenThere.containsKey(key) ||
            !seenHere.containsKey(key) ||
            version == null ||
            version.deleted) {
          return;
        }
        copied.add(key);
        await _queue(key, version, toPeer: true);
      });
      await _flush(toPeer: true);
    }

    final keys = {...seenHere.keys, ...seenThere.keys}
        .where((k) => !_skipped(k))
        .toList()
      ..sort();
    report.considered = keys.length;
    final rest = [
      for (final k in keys)
        if (!copied.contains(k)) k,
    ];
    for (var at = 0; at < rest.length; at += SyncClient.pageSize) {
      final chunk = rest.sublist(
        at,
        (at + SyncClient.pageSize).clamp(0, rest.length),
      );
      // The pairs of a page of keys in one query. A sync of 10,000 that
      // changed nothing took 10.2 s with one query a key, 5.3 s with this
      // (measured 2026-11-20).
      final pairs = await db.syncPairs(peer, chunk);
      for (final key in chunk) {
        try {
          await _syncOne(
            key,
            pairs[key],
            seenHere: seenHere[key],
            seenThere: seenThere[key],
          );
        } on SyncFailure catch (e) {
          report.failures.add('$key: $e');
        }
      }
    }
    if (report.failures.isEmpty) {
      await db.setSyncCursor(
        peer,
        remoteSince: there.latest ?? cursor?.remoteSince,
        localSince: here.latest ?? cursor?.localSince,
      );
    }
  }

  Future<void> _queue(
    String key,
    SyncVersion version, {
    required bool toPeer,
  }) async {
    final bytes = utf8.encode(jsonEncode(version.json)).length;
    final queued = toPeer ? _toPeerBytes : _toHereBytes;
    final list = toPeer ? _toPeer : _toHere;
    if (list.isNotEmpty &&
        (list.length >= SyncClient.pageSize || queued + bytes > batchBytes)) {
      await _flush(toPeer: toPeer);
    }
    list.add(
      (
        key: key,
        json: version.json!,
        source: version.versionId,
        bytes: bytes,
      ),
    );
    if (toPeer) {
      _toPeerBytes += bytes;
    } else {
      _toHereBytes += bytes;
    }
  }

  /// Writes the queued copies to one side in one Bundle and records each
  /// one written. A copy the side refuses is a failure, tried again next
  /// run; a Bundle the side refuses whole is a failure of each copy in it.
  Future<void> _flush({required bool toPeer}) async {
    final list = toPeer ? _toPeer : _toHere;
    if (list.isEmpty) return;
    final copies = List<_Copy>.of(list);
    list.clear();
    if (toPeer) {
      _toPeerBytes = 0;
    } else {
      _toHereBytes = 0;
    }
    final where = toPeer ? 'peer' : 'here';
    // A batch here goes through this server's storage floor
    // (syncLocalHandler) and is refused whole when it would cut into it;
    // the peer was not written for a copy, so nothing is left half done.
    final client = toPeer ? remote : local;
    final entries = [
      for (final c in copies)
        {
          'resource': c.json,
          'request': {'method': 'PUT', 'url': c.key},
        },
    ];
    // As a transaction first: one commit for all of them, where a batch
    // commits each entry on its own (500 MIMIC-IV Observations measured
    // 2026-11-20 on a fhirant file store: 1.5-1.8 s as a transaction,
    // 8.3-9.0 s as a batch; tool/sync_cost_2026-11-20/
    // batch_vs_transaction.py). A transaction refused is sent again as a
    // batch, so one copy the side will not take holds back only itself.
    List<({int status, String? versionId, String detail})> answers;
    try {
      answers = await client.bundle('transaction', entries);
    } on SyncFailure {
      try {
        answers = await client.bundle('batch', entries);
      } on SyncFailure catch (e) {
        for (final c in copies) {
          report.failures.add('${c.key}: write $where: $e');
        }
        return;
      }
    }
    // The pairs in one commit, not one each.
    await db.transaction<void>(() async {
      for (var i = 0; i < copies.length; i++) {
        final c = copies[i];
        final a = answers[i];
        if (a.status < 200 || a.status >= 300) {
          report.failures
              .add('${c.key}: write $where answered ${a.status}: ${a.detail}');
          continue;
        }
        toPeer ? report.writtenToPeer++ : report.writtenHere++;
        await db.setSyncPair(
          peer,
          c.key,
          local: toPeer ? c.source : a.versionId,
          remote: toPeer ? a.versionId : c.source,
        );
      }
    });
  }

  /// Whether a side has nothing after [pairVersion], the version the last
  /// sync left it at: the newest version its scan showed is that one, or
  /// the scan showed none. A side read whole that shows none does not have
  /// the resource at all; when the other side has it, it was a copy and
  /// never reaches here, and when neither has it there is nothing to write.
  static bool _unchangedSince(_Seen? seen, String? pairVersion) =>
      seen == null || (seen.versionId != null && seen.versionId == pairVersion);

  Future<void> _syncOne(
    String key,
    ({String? local, String? remote})? pair, {
    required _Seen? seenHere,
    required _Seen? seenThere,
  }) async {
    if (pair != null &&
        _unchangedSince(seenHere, pair.local) &&
        _unchangedSince(seenThere, pair.remote)) {
      report.unchanged++;
      return;
    }
    final mine = await local.history(key);
    final theirs = await remote.history(key);
    if (pair != null &&
        mine.isNotEmpty &&
        theirs.isNotEmpty &&
        mine.last.versionId == pair.local &&
        theirs.last.versionId == pair.remote) {
      report.unchanged++;
      return;
    }
    final here = _split(mine, pair?.local);
    final there = _split(theirs, pair?.remote);
    final merged = mergeResource(local: here, remote: there);
    for (final c in merged.conflicts) {
      report.conflicts.add(
        '$key ${c.field}: ${c.winner.name} kept '
        '(here ${c.localAt.toIso8601String()}, '
        'peer ${c.remoteAt.toIso8601String()})',
      );
    }
    final json = merged.json;

    // The floor is checked before anything is written, so a refusal here
    // leaves both sides as they were.
    if (json != null &&
        floor != null &&
        !(here.present && sameContent(json, here.current!.json))) {
      final refused = await floor!.refusal(
        StorageNeed.record,
        utf8.encode(jsonEncode(json)).length,
      );
      if (refused != null) throw SyncFailure('not written here: $refused');
    }

    // The peer first.
    final peerNow = await _apply(remote, key, there, json, toPeer: true);
    if (peerNow == null) return;
    final hereNow = await _apply(local, key, here, json, toPeer: false);
    await db.setSyncPair(
      peer,
      key,
      // Not written here (412): this side's base stays the version the
      // merge was made from, and the peer holds the merge.
      local: hereNow == null ? here.current?.versionId : hereNow.versionId,
      remote: peerNow.versionId,
    );
  }

  /// Writes [json] (null: delete) to [side] through [client] when it holds
  /// something else. Returns the version the side is at afterwards
  /// (wrapped, so a side that never had the resource reads as a null
  /// version), or null when the side changed meanwhile (412) or refused.
  Future<({String? versionId})?> _apply(
    SyncClient client,
    String key,
    SyncSide side,
    Map<String, dynamic>? json, {
    required bool toPeer,
  }) async {
    final current = side.current;
    final where = toPeer ? 'peer' : 'here';
    if (json == null) {
      if (!side.present) return (versionId: current?.versionId);
      final reply = await client.delete(key, ifMatch: current!.versionId);
      if (reply.status == 412) {
        report.retryLater.add('$key (changed $where during the sync)');
        return null;
      }
      if (reply.status >= 300) {
        throw SyncFailure('delete $where answered ${reply.status}: '
            '${_start(reply.body)}');
      }
      toPeer ? report.deletedOnPeer++ : report.deletedHere++;
      final after = await client.history(key);
      return (versionId: after.isEmpty ? null : after.last.versionId);
    }
    if (side.present && sameContent(json, current!.json)) {
      return (versionId: current.versionId);
    }
    final written = await client.put(
      key,
      json,
      ifMatch: side.present ? current!.versionId : null,
    );
    if (written.status == 412) {
      report.retryLater.add('$key (changed $where during the sync)');
      return null;
    }
    if (written.status >= 300) {
      throw SyncFailure('write $where answered ${written.status}: '
          '${_start(written.body)}');
    }
    toPeer ? report.writtenToPeer++ : report.writtenHere++;
    return (versionId: written.versionId);
  }

  /// [versions] split at [baseVersion]: the base, and what came after it.
  /// A base not in the history (a pair from a restored store) is no base.
  static SyncSide _split(List<SyncVersion> versions, String? baseVersion) {
    if (baseVersion == null) return SyncSide(since: versions);
    final at = versions.indexWhere((v) => v.versionId == baseVersion);
    if (at < 0) return SyncSide(since: versions);
    return SyncSide(base: versions[at], since: versions.sublist(at + 1));
  }

  static String _start(String body) =>
      body.length > 300 ? '${body.substring(0, 300)}…' : body;
}
