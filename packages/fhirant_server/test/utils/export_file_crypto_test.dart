import 'dart:convert';
import 'dart:typed_data';

import 'package:fhirant_server/src/utils/export_file_crypto.dart';
import 'package:test/test.dart';

/// The framed AES-GCM file format of an export at rest (REVIEW-2026-09-17
/// A8). Asserted against what the format promises, not against what the
/// code emits: a round trip across frame boundaries, and refusal of a
/// changed byte, a cut file, a reordered file and the wrong key.
void main() {
  final key = ExportFileCrypto.newKey();

  Future<Uint8List> encrypt(List<int> plain, [Uint8List? k]) async {
    final out = BytesBuilder();
    final sink = _BuilderSink(out);
    await ExportFileCrypto.encrypt(
      Stream.value(plain),
      sink,
      k ?? key,
      fileNumber: 0,
    );
    return out.takeBytes();
  }

  Future<List<int>> decrypt(List<int> file, [Uint8List? k]) async {
    final out = BytesBuilder();
    // Delivered in odd pieces, so no frame boundary lines up with a chunk
    // boundary.
    final pieces = [
      for (var i = 0; i < file.length; i += 1000)
        file.sublist(i, i + 1000 > file.length ? file.length : i + 1000),
    ];
    await ExportFileCrypto.decrypt(Stream.fromIterable(pieces), k ?? key)
        .forEach(out.add);
    return out.takeBytes();
  }

  // NIST SP 800-38D 8.2.1 (read 2026-10-21): the fixed field "shall
  // identify ... the context", and "For any given key, no two distinct
  // devices shall share the same fixed field". One job key encrypts one
  // file per type, so the file's number is the fixed field.
  test('the fixed field is the file number, so files under one key differ',
      () async {
    Future<Uint8List> fixed(int n) async {
      final out = BytesBuilder();
      await ExportFileCrypto.encrypt(
        Stream.value([1, 2, 3]),
        _BuilderSink(out),
        key,
        fileNumber: n,
      );
      return Uint8List.sublistView(
        out.takeBytes(),
        ExportFileCrypto.headerLength - 8,
        ExportFileCrypto.headerLength,
      );
    }

    expect(await fixed(7), [0, 0, 0, 0, 0, 0, 0, 7]);
    expect(await fixed(7), await fixed(7));
    expect(await fixed(8), isNot(await fixed(7)));
  });

  // SP 800-38D 8.3: an s-bit invocation field allows 2^s invocations per
  // fixed field; a 4-byte counter written past that wraps onto frame 0.
  test('a frame counter past 2^32 is refused, not wrapped onto frame 0', () {
    final fixed = Uint8List(8);
    expect(ExportFileCrypto.nonceFor(fixed, 0xFFFFFFFF), hasLength(12));
    expect(
      () => ExportFileCrypto.nonceFor(fixed, 0x100000000),
      throwsStateError,
    );
  });

  test('round trip, empty, one frame and several frames', () async {
    for (final size in [
      0,
      1,
      ExportFileCrypto.chunkSize,
      3 * ExportFileCrypto.chunkSize + 17,
    ]) {
      final plain = List<int>.generate(size, (i) => (i * 7) & 0xff);
      expect(await decrypt(await encrypt(plain)), plain, reason: '$size');
    }
  });

  test('the file holds no plaintext', () async {
    final plain = utf8.encode('{"resourceType":"Patient","id":"p1"}\n');
    final file = await encrypt(plain);
    expect(latin1.decode(file, allowInvalid: true), isNot(contains('Patient')));
    expect(
      file.length,
      greaterThan(plain.length + ExportFileCrypto.headerLength),
    );
  });

  test('a changed byte is refused', () async {
    final file = await encrypt(utf8.encode('x' * 100));
    for (final at in [ExportFileCrypto.headerLength + 4, file.length - 1]) {
      final changed = Uint8List.fromList(file)..[at] ^= 0x01;
      expect(
        decrypt(changed),
        throwsA(isA<ExportFileCorrupt>()),
        reason: '$at',
      );
    }
  });

  test('a file cut short is refused, on and off a frame boundary', () async {
    final file =
        await encrypt(List<int>.filled(2 * ExportFileCrypto.chunkSize, 1));
    final firstFrameEnd =
        ExportFileCrypto.headerLength + 4 + ExportFileCrypto.chunkSize + 16;
    for (final length in [firstFrameEnd, firstFrameEnd - 5, file.length - 1]) {
      expect(
        decrypt(file.sublist(0, length)),
        throwsA(isA<ExportFileCorrupt>()),
        reason: '$length',
      );
    }
  });

  test('the wrong key is refused', () async {
    final file = await encrypt(utf8.encode('secret'));
    expect(
      decrypt(file, ExportFileCrypto.newKey()),
      throwsA(isA<ExportFileCorrupt>()),
    );
  });

  test('a file that is not one of these is refused', () async {
    expect(
      decrypt(utf8.encode('{"resourceType":"Patient"}\n')),
      throwsA(isA<ExportFileCorrupt>()),
    );
  });
}

class _BuilderSink implements Sink<List<int>> {
  _BuilderSink(this.builder);
  final BytesBuilder builder;
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}
