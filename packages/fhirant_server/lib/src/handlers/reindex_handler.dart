import 'dart:async';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:shelf/shelf.dart';

/// `$reindex`: rebuild the search index from the stored resources, so a
/// SearchParameter uploaded after they were stored finds them (Azure FHIR
/// service "Create custom search parameters", read 2026-09-14: "Each time
/// you create, update, or delete a search parameter, you need to run a
/// reindex job to accept the changes"; Smile CDR: "Once an appropriate
/// $reindex operation has been run and completed").
///
/// Asynchronous, the way `$export` is: the rebuild of the MIMIC sample
/// (81,088 resources) took 17.9 s and a save made while it ran waited for
/// it (`tool/review_2026-09-06/reindex_bench.tsv`, 2026-09-14), so the
/// kickoff answers 202 with a `Content-Location` to poll and the work runs
/// on. One job at a time: a kickoff while one runs is 409. The job lives in
/// this process; a restart forgets it, and the index is whatever the
/// rebuild had written (the rebuild empties the index tables first and
/// refills them page by page, as every schema migration that rebuilds
/// does).
class ReindexJobs {
  ReindexJob? _current;

  /// The job in flight or last finished, or null when none was run.
  ReindexJob? get current => _current;

  /// Starts a rebuild on [db] unless one is running; returns the job, or
  /// null when one is already running.
  ReindexJob? start(FhirAntDb db) {
    if (_current?.running ?? false) return null;
    final job = ReindexJob._();
    _current = job;
    unawaited(job._run(db));
    return job;
  }
}

/// One rebuild: when it started, when it ended, how many resources it read
/// and what went wrong.
class ReindexJob {
  ReindexJob._();

  /// When the rebuild began.
  final DateTime started = DateTime.now();

  /// When it ended, null while running.
  DateTime? finished;

  /// Resources in the store when the rebuild began.
  int resources = 0;

  /// Why it failed, null when it succeeded or is running.
  String? error;

  /// Definitions the store holds but could not index by (id, reason),
  /// reported so an operator sees them.
  List<(String, String)> rejected = const [];

  /// Whether the rebuild is still running.
  bool get running => finished == null;

  Future<void> _run(FhirAntDb db) async {
    try {
      resources = (await db
              .customSelect('SELECT count(*) AS n FROM resources')
              .getSingle())
          .read<int>('n');
      await db.rebuildSearchIndex();
      rejected = (await db.customSearchParameters)?.rejected ?? const [];
    } catch (e, st) {
      error = '$e';
      FhirantLogging().logError('\$reindex failed: $e\n$st');
    } finally {
      finished = DateTime.now();
    }
  }
}

/// `POST /$reindex` (admin or a `system/` scope, enforced by the
/// authorization layer as for `$backup`): 202 with `Content-Location` to
/// `/$reindex-status`, or 409 while one is running.
Response reindexKickoffHandler(
  Request request,
  FhirAntDb db,
  ReindexJobs jobs,
) {
  final job = jobs.start(db);
  if (job == null) {
    return outcomeResponse(
      409,
      'conflict',
      r'A $reindex is already running; poll its status.',
    );
  }
  FhirantLogging()
      .logInfo('\$reindex started by ${Principal.of(request)?.username}');
  final base = request.requestedUri.replace(path: '/', query: '');
  return Response(
    202,
    headers: {
      'Content-Location': '$base\$reindex-status',
      'Content-Type': 'application/fhir+json',
    },
    body: _outcome(
      'information',
      'informational',
      'Reindex started ${job.started.toIso8601String()}.',
    ),
  );
}

/// `GET /$reindex-status`: 202 while the rebuild runs, 200 with an
/// OperationOutcome when it finished, 500 when it failed, 404 when none was
/// started in this process.
Response reindexStatusHandler(Request request, ReindexJobs jobs) {
  final job = jobs.current;
  if (job == null) {
    return outcomeResponse(404, 'not-found', r'No $reindex has been run.');
  }
  if (job.running) {
    return Response(
      202,
      headers: {
        'X-Progress': 'Reindexing ${job.resources} resources since '
            '${job.started.toIso8601String()}',
        'Retry-After': '5',
      },
    );
  }
  if (job.error != null) {
    return outcomeResponse(500, 'exception', 'Reindex failed: ${job.error}');
  }
  final took = job.finished!.difference(job.started);
  final rejected = job.rejected.isEmpty
      ? ''
      : ' ${job.rejected.length} stored SearchParameter(s) index nothing: '
          '${job.rejected.map((r) => '${r.$1} (${r.$2})').join('; ')}.';
  return Response(
    200,
    headers: {'Content-Type': 'application/fhir+json'},
    body: _outcome(
      'information',
      'informational',
      'Reindexed ${job.resources} resources in ${took.inMilliseconds} ms, '
          'finished ${job.finished!.toIso8601String()}.$rejected',
    ),
  );
}

String _outcome(String severity, String code, String diagnostics) =>
    '{"resourceType":"OperationOutcome","issue":[{"severity":"$severity",'
    '"code":"$code","diagnostics":${_json(diagnostics)}}]}';

String _json(String s) {
  final escaped =
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');
  return '"$escaped"';
}
