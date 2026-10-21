import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The EICAR test file (eicar.org, "Anti-Malware Testfile"): 68 ASCII bytes
/// antivirus engines report, ClamAV 1.5.4 as `Eicar-Test-Signature`
/// (measured, tool/review_2026-10-17/clamd/scan_timing.tsv). Harmless; it is
/// the standard known positive.
const eicar =
    r'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*';

/// A stream holding this is answered as clamd with AlertEncrypted answers a
/// PDF that needs a password: `Heuristics.Encrypted.PDF` (measured,
/// tool/review_2026-10-17/clamd/encrypted_samples.tsv).
const encryptedMarker = 'FAKE-ENCRYPTED-PDF';

/// A stream holding this is answered as clamd with AlertExceedsMax answers a
/// scan cut short by MaxScanSize: `Heuristics.Limits.Exceeded.MaxScanSize`
/// (the name in ClamAV 1.5.4 libclamav/others.c).
const limitsMarker = 'FAKE-PAST-MAX-SCAN-SIZE';

/// How the fake answers.
enum ClamdMode {
  /// `stream: Eicar-Test-Signature FOUND` when the stream holds [eicar], else
  /// `stream: OK`, as clamd does.
  scan,

  /// `INSTREAM size limit exceeded. ERROR`, then close.
  sizeLimit,

  /// A reply that is neither clean, a match, nor an error.
  garbled,

  /// Reads everything and never answers.
  silent,

  /// Closes the connection without a word.
  hangUp,
}

/// A stand-in for clamd's INSTREAM over TCP (clamd(8), ClamAV
/// docs/man/clamd.8.in): `zINSTREAM\0`, then chunks of a 4-byte big-endian
/// length and that many bytes, ended by a zero length; the reply ends in a
/// NUL. Keeps what each stream carried so a test can check the framing.
class FakeClamd {
  FakeClamd._(this._server);

  static Future<FakeClamd> start() async =>
      FakeClamd._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0))
        .._listen();

  final ServerSocket _server;
  ClamdMode mode = ClamdMode.scan;

  /// The bytes of each stream received, in order.
  final List<Uint8List> streams = [];

  /// The command each connection opened with.
  final List<String> commands = [];

  int get port => _server.port;

  Future<void> close() => _server.close();

  void _listen() {
    _server.listen((socket) {
      if (mode == ClamdMode.hangUp) {
        socket.destroy();
        return;
      }
      final buffer = BytesBuilder();
      var commandDone = false;
      final stream = BytesBuilder();
      var finished = false;
      socket.listen(
        (data) {
          if (finished) return;
          buffer.add(data);
          var bytes = buffer.toBytes();
          if (!commandDone) {
            final nul = bytes.indexOf(0);
            if (nul < 0) return;
            commands.add(ascii.decode(bytes.sublist(0, nul)));
            commandDone = true;
            bytes = bytes.sublist(nul + 1);
          }
          var at = 0;
          while (bytes.length - at >= 4) {
            final length = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
            if (length == 0) {
              finished = true;
              streams.add(stream.takeBytes());
              _answer(socket, streams.last);
              return;
            }
            if (bytes.length - at - 4 < length) break;
            stream.add(bytes.sublist(at + 4, at + 4 + length));
            at += 4 + length;
          }
          buffer
            ..clear()
            ..add(bytes.sublist(at));
        },
        onError: (Object _) {},
        cancelOnError: true,
      );
    });
  }

  void _answer(Socket socket, Uint8List data) {
    switch (mode) {
      case ClamdMode.scan:
        final text = latin1.decode(data);
        final found = text.contains(eicar)
            ? 'Eicar-Test-Signature'
            : text.contains(encryptedMarker)
                ? 'Heuristics.Encrypted.PDF'
                : text.contains(limitsMarker)
                    ? 'Heuristics.Limits.Exceeded.MaxScanSize'
                    : null;
        socket.add(
          ascii.encode(
            found == null ? 'stream: OK\x00' : 'stream: $found FOUND\x00',
          ),
        );
        unawaited(socket.close());
      case ClamdMode.sizeLimit:
        socket.add(ascii.encode('INSTREAM size limit exceeded. ERROR\x00'));
        unawaited(socket.close());
      case ClamdMode.garbled:
        socket.add(ascii.encode('stream: maybe\x00'));
        unawaited(socket.close());
      case ClamdMode.silent:
      case ClamdMode.hangUp:
        break;
    }
  }
}
