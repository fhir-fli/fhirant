import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a scan of one file found.
sealed class ScanResult {
  const ScanResult();
}

/// No known malicious content.
final class ScanClean extends ScanResult {
  const ScanClean();
}

/// Known malicious content, named by the scanner's signature.
final class ScanFound extends ScanResult {
  const ScanFound(this.signature);

  final String signature;
}

/// The scanner could not give an answer: unreachable, too slow, or a reply
/// that is neither clean nor a match. A file is never taken as clean on
/// this.
class ScannerUnavailable implements Exception {
  const ScannerUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ScannerUnavailable: $message';
}

/// Scans the files clients send before they are stored (OWASP ASVS 5.0.0
/// V5.4.3: "files obtained from untrusted sources are scanned by antivirus
/// scanners to prevent serving of known malicious content").
// ignore: one_member_abstracts, a seam for the test double and the phone
abstract interface class FileScanner {
  /// Throws [ScannerUnavailable] when there is no answer.
  Future<ScanResult> scan(Uint8List bytes);
}

/// A clamd daemon over TCP, by its INSTREAM command.
///
/// The protocol is clamd(8) (ClamAV docs/man/clamd.8.in, read 2026-10-21):
/// INSTREAM "is mandatory to prefix ... with n or z"; the data follows in
/// chunks, each "`'<length><data>'` where `<length>` is the size of the
/// following data in bytes expressed as a 4 byte unsigned integer in network
/// byte order"; "Streaming is terminated by sending a zero-length chunk";
/// past StreamMaxLength "clamd will reply with INSTREAM size limit exceeded
/// and close the connection". With the z prefix, "Clamd replies will honour
/// the requested terminator", a NUL.
///
/// The reply is matched exactly: `stream: OK` is clean,
/// `stream: <name> FOUND` is a match, and anything else (an ERROR, the size
/// limit, a closed socket, nothing within [timeout]) is
/// [ScannerUnavailable]. The pub.dev
/// `clamav` 0.1.0 client was read and not used: it scans only a file on
/// disk, treats a reply with neither FOUND nor ERROR in it as clean, and
/// waits on the socket with no deadline.
class ClamdScanner implements FileScanner {
  ClamdScanner(this.host, {this.port = 3310, required this.timeout});

  final String host;

  /// clamd's TCP port; 3310 is the clamav/clamav image's.
  final int port;

  /// The whole scan, connect to reply.
  final Duration timeout;

  /// clamd takes any chunk length up to StreamMaxLength; this only bounds
  /// what one write holds.
  static const int _chunk = 64 * 1024;

  static final _found = RegExp(r'^stream: (.+) FOUND$');

  @override
  Future<ScanResult> scan(Uint8List bytes) async {
    final String reply;
    try {
      reply = await _instream(bytes).timeout(timeout);
    } on TimeoutException {
      throw ScannerUnavailable('no reply from clamd at $host:$port '
          'within ${timeout.inMilliseconds} ms');
    } on SocketException catch (e) {
      throw ScannerUnavailable('clamd at $host:$port: ${e.message}');
    }
    if (reply == 'stream: OK') return const ScanClean();
    final match = _found.firstMatch(reply);
    if (match != null) return ScanFound(match[1]!);
    throw ScannerUnavailable('clamd at $host:$port answered "$reply"');
  }

  Future<String> _instream(Uint8List bytes) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    // A write clamd has hung up on fails three times: in flush, which is
    // caught below, on `done`, and on the reply's listener, neither awaited
    // once flush has thrown (measured: an uncaught broken pipe, each).
    socket.done.ignore();
    try {
      final reply = BytesBuilder(copy: false);
      final done = Completer<void>();
      done.future.ignore();
      socket
        ..listen(
          (data) {
            final nul = data.indexOf(0);
            reply.add(nul < 0 ? data : data.sublist(0, nul));
            if (nul >= 0 && !done.isCompleted) done.complete();
          },
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        )
        ..add(ascii.encode('zINSTREAM\x00'));
      for (var at = 0; at < bytes.length; at += _chunk) {
        final end = at + _chunk < bytes.length ? at + _chunk : bytes.length;
        socket
          ..add(_length(end - at))
          ..add(Uint8List.sublistView(bytes, at, end));
      }
      socket.add(_length(0));
      await socket.flush();
      await done.future;
      return latin1.decode(reply.takeBytes());
    } finally {
      socket.destroy();
    }
  }

  static Uint8List _length(int n) =>
      (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
}
