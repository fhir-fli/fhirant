import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Encryption at rest for the files a bulk export writes.
///
/// An export's NDJSON files are the export's snapshot: Bulk Data 2.0.0
/// export.html (read whole 2026-09-18) on `transactionTime`, "The response
/// SHOULD NOT include any resources modified after this instant, and SHALL
/// include any matching resources modified up to and including this
/// instant". So the files stay on disk until they expire, and they used to
/// stay in the clear beside an encrypted store, under Documents in the app,
/// which iOS backs up (fhirant REVIEW-2026-09-17 A8).
///
/// Each job has its own random 256-bit key, kept in its `export_jobs` row
/// inside the encrypted store; the file carries no key material. The file
/// is a sequence of frames, each AES-256-GCM over one chunk of the
/// plaintext with its own nonce and tag, so a multi-gigabyte export is
/// written and served in bounded memory and a download is refused at the
/// first frame that fails its tag rather than served in part:
///
///     magic "FHXP" · version 1 · 8-byte nonce prefix
///     frame: 4-byte big-endian length L · L bytes of ciphertext + 16-byte tag
///
/// The nonce of frame i is the prefix followed by i as a 4-byte counter;
/// the associated data of every frame is the header plus a byte saying
/// whether the frame is the last, so a file cut short after a frame
/// boundary, or with frames reordered, fails too.
class ExportFileCrypto {
  ExportFileCrypto._();

  /// The plaintext bytes per frame.
  static const int chunkSize = 64 * 1024;

  static const int _keyLength = 32;
  static const int _prefixLength = 8;
  static const int _tagBits = 128;
  static const int _tagLength = _tagBits ~/ 8;
  static const List<int> _magic = [0x46, 0x48, 0x58, 0x50]; // FHXP
  static const int _version = 1;
  static final int headerLength = _magic.length + 1 + _prefixLength;

  /// A fresh key for one job, from the platform's secure random source.
  static Uint8List newKey() => _randomBytes(_keyLength);

  /// Writes [plaintext] to [out] as an encrypted file under [key], frame by
  /// frame as the chunks arrive.
  static Future<void> encrypt(
    Stream<List<int>> plaintext,
    Sink<List<int>> out,
    Uint8List key,
  ) async {
    final prefix = _randomBytes(_prefixLength);
    final header = Uint8List.fromList([..._magic, _version, ...prefix]);
    out.add(header);
    final buffer = BytesBuilder(copy: false);
    var counter = 0;
    void emit(Uint8List chunk, {required bool last}) {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(
            KeyParameter(key),
            _tagBits,
            _nonce(prefix, counter),
            _associated(header, last: last),
          ),
        );
      final body = cipher.process(chunk);
      out
        ..add(_length(body.length))
        ..add(body);
      counter++;
    }

    await for (final bytes in plaintext) {
      buffer.add(bytes);
      while (buffer.length > chunkSize) {
        final all = buffer.takeBytes();
        emit(Uint8List.sublistView(all, 0, chunkSize), last: false);
        buffer.add(Uint8List.sublistView(all, chunkSize));
      }
    }
    // The last frame, possibly empty: a file with none is not a whole file.
    emit(buffer.takeBytes(), last: true);
  }

  /// The plaintext of the encrypted file [ciphertext], under [key], frame
  /// by frame. A frame that fails its tag, a file cut short, or a file that
  /// is not one of these ends the stream with an [ExportFileCorrupt] and
  /// nothing of that frame is yielded.
  static Stream<List<int>> decrypt(
    Stream<List<int>> ciphertext,
    Uint8List key,
  ) async* {
    final reader = _Reader(ciphertext);
    final header = await reader.take(headerLength);
    if (header == null ||
        !_startsWith(header, _magic) ||
        header[_magic.length] != _version) {
      throw const ExportFileCorrupt('not an encrypted export file');
    }
    final prefix = Uint8List.sublistView(header, _magic.length + 1);
    var counter = 0;
    var sawLast = false;
    while (!sawLast) {
      final lengthBytes = await reader.take(4);
      if (lengthBytes == null) {
        throw const ExportFileCorrupt('the file ends before its last frame');
      }
      final length = ByteData.sublistView(lengthBytes).getUint32(0);
      if (length < _tagLength) {
        throw const ExportFileCorrupt('a frame is shorter than its tag');
      }
      final body = await reader.take(length);
      if (body == null) {
        throw const ExportFileCorrupt('the file ends inside a frame');
      }
      // Whether this is the last frame is what the tag authenticates; it is
      // tried as the last only when the file has nothing after it.
      final last = await reader.atEnd;
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            _tagBits,
            _nonce(prefix, counter),
            _associated(header, last: last),
          ),
        );
      final Uint8List plain;
      try {
        plain = cipher.process(body);
      } on InvalidCipherTextException {
        throw const ExportFileCorrupt('a frame fails its authentication tag');
      }
      counter++;
      sawLast = last;
      if (plain.isNotEmpty) yield plain;
    }
  }

  /// The plaintext's length in bytes, from the frame lengths alone: the
  /// header and each frame's 4-byte length are read, the frames' bodies
  /// are skipped. A file that is not one of these, or ends inside a frame,
  /// is an [ExportFileCorrupt]; a changed body is not seen here and is
  /// caught by [decrypt].
  static Future<int> plaintextLength(RandomAccessFile file) async {
    final size = await file.length();
    final header = await file.read(headerLength);
    if (header.length < headerLength ||
        !_startsWith(header, _magic) ||
        header[_magic.length] != _version) {
      throw const ExportFileCorrupt('not an encrypted export file');
    }
    var total = 0;
    var at = headerLength;
    while (at < size) {
      await file.setPosition(at);
      final lengthBytes = await file.read(4);
      if (lengthBytes.length < 4) {
        throw const ExportFileCorrupt('the file ends before its last frame');
      }
      final length = ByteData.sublistView(lengthBytes).getUint32(0);
      if (length < _tagLength || at + 4 + length > size) {
        throw const ExportFileCorrupt('the file ends inside a frame');
      }
      total += length - _tagLength;
      at += 4 + length;
    }
    return total;
  }

  static Uint8List _nonce(Uint8List prefix, int counter) {
    final nonce = Uint8List(12)..setRange(0, _prefixLength, prefix);
    ByteData.sublistView(nonce).setUint32(_prefixLength, counter);
    return nonce;
  }

  static Uint8List _associated(Uint8List header, {required bool last}) =>
      Uint8List.fromList([...header, if (last) 1 else 0]);

  static Uint8List _length(int n) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, n);

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// A file under the export directory that is not, or is no longer, the
/// file the job wrote.
class ExportFileCorrupt implements Exception {
  /// Creates the failure with what was found.
  const ExportFileCorrupt(this.reason);

  /// What was found.
  final String reason;

  @override
  String toString() => 'Export file corrupt: $reason';
}

/// Reads exact byte counts from a stream of chunks.
class _Reader {
  _Reader(Stream<List<int>> source) : _iterator = StreamIterator(source);

  final StreamIterator<List<int>> _iterator;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  bool _sourceDone = false;

  /// The next [n] bytes, or null when the stream ends before them.
  Future<Uint8List?> take(int n) async {
    while (_pending.length < n && !_sourceDone) {
      if (await _iterator.moveNext()) {
        _pending.add(_iterator.current);
      } else {
        _sourceDone = true;
      }
    }
    if (_pending.length < n) return null;
    final all = _pending.takeBytes();
    _pending.add(Uint8List.sublistView(all, n));
    return Uint8List.sublistView(all, 0, n);
  }

  /// Whether nothing follows what has been taken.
  Future<bool> get atEnd async {
    while (_pending.isEmpty && !_sourceDone) {
      if (await _iterator.moveNext()) {
        _pending.add(_iterator.current);
      } else {
        _sourceDone = true;
      }
    }
    return _pending.isEmpty;
  }
}
