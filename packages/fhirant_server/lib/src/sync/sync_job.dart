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
    required String localBase,
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
        localBase: localBase,
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

/// Brings this server and a peer to the same content for every resource
/// either changed since the last sync between them.
///
/// For each such resource: read both sides' histories, split each at the
/// version the last sync left it at (`sync_pairs`), merge
/// ([mergeResource]), write the result to the peer, then here, and record
/// the versions both now hold. The peer is written first: when the peer
/// takes the merge and this side cannot (it changed in between, 412), the
/// peer holds the merge and the next sync's rule for "neither changed,
/// different values" (take the peer's) carries it here. When the peer
/// cannot take it, nothing is recorded and the next sync starts over.
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
    required this.localBase,
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

  /// This server's base URL, written into `meta.source` of what it sends
  /// that has none.
  final String localBase;

  /// What the run did.
  final SyncReport report;

  /// This server's storage floor, checked before each write here.
  final StorageFloor? floor;

  /// Runs the sync.
  Future<void> run() async {
    final cursor = await db.syncCursor(peer);
    final there = await remote.changedSince(cursor?.remoteSince);
    final here = await local.changedSince(cursor?.localSince);
    final keys = {...there.keys, ...here.keys}
        .where((k) => !syncSkippedTypes.contains(k.split('/').first))
        .toList()
      ..sort();
    report.considered = keys.length;
    for (final key in keys) {
      try {
        await _syncOne(key);
      } on SyncFailure catch (e) {
        report.failures.add('$key: $e');
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

  Future<void> _syncOne(String key) async {
    final pair = await db.syncPair(peer, key);
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
    var json = merged.json;
    if (json != null) json = _withSource(json, mine, theirs);

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

  /// [json] with `meta.source` set to the server the resource was first
  /// saved on, when it carries none: the peer for one this server never
  /// had, this server for one the peer never had. R4B resource.html, Meta
  /// (hl7.org/fhir/R4B/resource.html, read 2026-11-19): source is "A uri
  /// that identifies the source system of the resource", and on a write
  /// "the server SHOULD generally leave this unchanged".
  Map<String, dynamic> _withSource(
    Map<String, dynamic> json,
    List<SyncVersion> mine,
    List<SyncVersion> theirs,
  ) {
    final meta = json['meta'];
    if (meta is Map && meta['source'] != null) return json;
    final String? origin;
    if (mine.isEmpty) {
      origin = peer;
    } else if (theirs.isEmpty) {
      origin = localBase;
    } else {
      origin = null;
    }
    if (origin == null) return json;
    return {
      ...json,
      'meta': {
        if (meta is Map) ...meta.cast<String, dynamic>(),
        'source': origin,
      },
    };
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
