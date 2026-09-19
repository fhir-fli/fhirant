import 'dart:async';
import 'dart:isolate';

/// The default deadline for a client's program: ten seconds. The review's
/// six-level nested select, 10^6 evaluations, took 1,002 ms on this
/// desktop; a phone is slower by a factor nobody here has measured.
const Duration kProgramDeadline = Duration(seconds: 10);

/// Runs a client's program off the server's isolate, under a deadline.
///
/// `$fhirpath`, `$cql`, `Library/$evaluate` and `$transform` evaluate what
/// the client sent. They ran on the server's isolate with no deadline: a
/// 293-character FHIRPath expression held the handler 1,002 ms, each
/// further 48 characters multiplied that by ten, and while it ran nothing
/// else was served (fhirant REVIEW-2026-09-17 A9).
///
/// [program] runs in a fresh isolate. It may capture only what a `SendPort`
/// can carry (strings, numbers, JSON maps and lists; no database, no
/// request, no engine), and returns a value the port can carry back. When
/// [deadline] passes the isolate is killed and [ProgramTimeout] is thrown;
/// a program that throws comes back as [ProgramFailed].
///
/// A fresh isolate per program, rather than a pool: spawn plus a FHIRPath
/// engine measured 6 + 22 ms cold and under 2 ms warm on this desktop
/// (`tool/review_2026-09-17/fix_a9/isolate_cost.tsv`), a killed worker
/// leaves nothing to repair, and a program cannot see another's state.
/// The kill is real: a worker in a tight loop cost 50 CPU ticks per 500 ms
/// and 0 after `kill(priority: immediate)` (`fix_a9/kill_cpu.tsv`).
Future<R> runProgram<R>(
  FutureOr<R> Function() program, {
  required Duration deadline,
}) =>
    _run<R>((_) => program(), deadline: deadline, host: null);

/// [runProgram] for a program that needs something only the server's
/// isolate holds, such as the database.
///
/// The program receives a `SendPort` and asks through [askHost]; each
/// request arrives at [host] on the server's isolate, and its answer (or
/// `null`) goes back. A request must be port-sendable, as must the answer.
/// If [host] throws, the program's failure is the server's, not the
/// client's, and surfaces here as [ProgramHostFailed].
Future<R> runHostedProgram<R>(
  FutureOr<R> Function(SendPort host) program, {
  required Duration deadline,
  required Future<Object?> Function(Object? request) host,
}) =>
    _run<R>(program, deadline: deadline, host: host);

/// Sends [request] from a program to its host and returns the answer.
/// Throws when the host failed to answer; that failure is recorded on the
/// host's side and reported as [ProgramHostFailed] there.
Future<Object?> askHost(SendPort host, Object? request) async {
  final reply = ReceivePort();
  host.send((reply.sendPort, request));
  try {
    return switch (await reply.first) {
      _HostOk(:final value) => value,
      _HostFailed(:final error) => throw StateError('host failed: $error'),
      final other => throw StateError('unexpected host reply $other'),
    };
  } finally {
    reply.close();
  }
}

Future<R> _run<R>(
  FutureOr<R> Function(SendPort host) program, {
  required Duration deadline,
  required Future<Object?> Function(Object? request)? host,
}) async {
  final port = ReceivePort();
  final hostPort = ReceivePort();
  Object? hostError;
  StackTrace? hostStack;
  hostPort.listen((message) async {
    final (SendPort reply, Object? request) = message as (SendPort, Object?);
    try {
      reply.send(_HostOk(await host!(request)));
    } catch (e, s) {
      hostError ??= e;
      hostStack ??= s;
      reply.send(_HostFailed('$e'));
    }
  });
  Isolate? isolate;
  try {
    // Spawning copies [program] and everything its scope captured. A
    // closure shares one context with every other closure of its scope, so
    // a database referenced by a sibling lambda rides along and the spawn
    // throws ArgumentError "object is unsendable". Build the program in a
    // function of its own. Spawn is inside the try so the ports close.
    isolate = await Isolate.spawn(
      _entry<R>,
      (program, port.sendPort, hostPort.sendPort),
      onError: port.sendPort,
    );
    final message = await port.first.timeout(deadline);
    if (hostError != null) {
      Error.throwWithStackTrace(ProgramHostFailed(hostError!), hostStack!);
    }
    switch (message) {
      case _Ok<R>(:final value):
        return value;
      case _Failed(:final error):
        throw ProgramFailed(error);
      case final List<Object?> uncaught:
        // The isolate's onError shape: [error string, stack string].
        throw ProgramFailed('${uncaught.first}');
      default:
        throw ProgramFailed('unexpected reply ${message.runtimeType}');
    }
  } on TimeoutException {
    throw ProgramTimeout(deadline);
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
    hostPort.close();
  }
}

Future<void> _entry<R>(
  (FutureOr<R> Function(SendPort), SendPort, SendPort) args,
) async {
  final (program, reply, host) = args;
  try {
    reply.send(_Ok<R>(await program(host)));
  } catch (e) {
    reply.send(_Failed('$e'));
  }
}

class _Ok<R> {
  const _Ok(this.value);
  final R value;
}

class _Failed {
  const _Failed(this.error);
  final String error;
}

class _HostOk {
  const _HostOk(this.value);
  final Object? value;
}

class _HostFailed {
  const _HostFailed(this.error);
  final String error;
}

/// The program did not finish within its deadline and was killed.
class ProgramTimeout implements Exception {
  /// Creates the failure for [deadline].
  const ProgramTimeout(this.deadline);

  /// The deadline the program was given.
  final Duration deadline;

  @override
  String toString() =>
      'The program did not finish within ${deadline.inMilliseconds} ms and '
      'was stopped.';
}

/// The program threw.
class ProgramFailed implements Exception {
  /// Creates the failure with the program's own error text.
  const ProgramFailed(this.error);

  /// The error, as text.
  final String error;

  @override
  String toString() => error;
}

/// The host could not answer the program: the server's failure, not the
/// client's. Carries the host's own error.
class ProgramHostFailed implements Exception {
  /// Creates the failure around the host's [error].
  const ProgramHostFailed(this.error);

  /// What the host threw.
  final Object error;

  @override
  String toString() => 'The server could not serve the program: $error';
}
