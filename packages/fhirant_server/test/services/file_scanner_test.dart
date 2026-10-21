import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fhirant_server/src/services/file_scanner.dart';
import 'package:test/test.dart';

import 'fake_clamd.dart';

void main() {
  late FakeClamd clamd;
  late ClamdScanner scanner;

  setUp(() async {
    clamd = await FakeClamd.start();
    scanner = ClamdScanner(
      '127.0.0.1',
      port: clamd.port,
      timeout: const Duration(seconds: 2),
    );
  });

  tearDown(() => clamd.close());

  Uint8List bytesOf(String s) => Uint8List.fromList(latin1.encode(s));

  test('a clean file is clean', () async {
    expect(await scanner.scan(bytesOf('hello')), isA<ScanClean>());
  });

  test('the EICAR file is a match, named by its signature', () async {
    final result = await scanner.scan(bytesOf(eicar));
    expect(result, isA<ScanFound>());
    expect((result as ScanFound).signature, 'Eicar-Test-Signature');
  });

  // clamd(8): INSTREAM must carry the z or n prefix, and its data arrives
  // as length-prefixed chunks. A file larger than one write is split, and
  // clamd must see it whole.
  test('sends zINSTREAM and the whole file across chunks', () async {
    final big = Uint8List.fromList(
      List<int>.generate(200 * 1024 + 7, (i) => i % 251),
    );
    await scanner.scan(big);
    expect(clamd.commands, ['zINSTREAM']);
    expect(clamd.streams.single, big);
  });

  test('an empty file is sent as an empty stream', () async {
    expect(await scanner.scan(Uint8List(0)), isA<ScanClean>());
    expect(clamd.streams.single, isEmpty);
  });

  group('no answer is never clean', () {
    test('the size limit', () async {
      clamd.mode = ClamdMode.sizeLimit;
      await expectLater(
        scanner.scan(bytesOf('x')),
        throwsA(isA<ScannerUnavailable>()),
      );
    });

    test('a reply that is neither OK nor FOUND', () async {
      clamd.mode = ClamdMode.garbled;
      await expectLater(
        scanner.scan(bytesOf('x')),
        throwsA(isA<ScannerUnavailable>()),
      );
    });

    test('no reply within the deadline', () async {
      clamd.mode = ClamdMode.silent;
      final quick = ClamdScanner(
        '127.0.0.1',
        port: clamd.port,
        timeout: const Duration(milliseconds: 300),
      );
      await expectLater(
        quick.scan(bytesOf('x')),
        throwsA(isA<ScannerUnavailable>()),
      );
    });

    test('the connection closed without a reply', () async {
      clamd.mode = ClamdMode.hangUp;
      await expectLater(
        scanner.scan(bytesOf('x')),
        throwsA(isA<ScannerUnavailable>()),
      );
    });

    test('nothing listening', () async {
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = free.port;
      await free.close();
      await expectLater(
        ClamdScanner(
          '127.0.0.1',
          port: port,
          timeout: const Duration(seconds: 2),
        ).scan(bytesOf('x')),
        throwsA(isA<ScannerUnavailable>()),
      );
    });
  });
}
