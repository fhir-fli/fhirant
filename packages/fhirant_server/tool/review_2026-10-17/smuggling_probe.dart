// HTTP/1.1 message framing probes (OWASP ASVS 5.0.0 V4.2.1, "determine
// boundaries of incoming HTTP messages using the appropriate mechanism for
// the HTTP version to prevent HTTP request smuggling"), against the stack
// fhirant serves on: shelf_io.serve over dart:io's HttpServer.
//
// Each case is a raw request with a plain `GET /health` appended on the same
// connection. One row per case to smuggling_probe.tsv, written and flushed as
// it runs: the RFC 9112 rule (read 2026-10-21, rfc-editor.org/rfc/rfc9112.txt),
// the status lines received, whether the server closed the connection, and
// the verdict against that rule. A second response means the bytes after the
// ambiguous request were read as a request of their own.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/smuggling_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../test/integration/test_helpers.dart';

const _tail = 'GET /health HTTP/1.1\r\nHost: x\r\n\r\n';

/// A case: its name, the rule, the request bytes, and the verdict from the
/// statuses and whether the connection was closed.
typedef _Case = ({
  String name,
  String rule,
  String request,
  String Function(List<String> statuses, bool closed, int bytes) verdict,
});

String _mustRefuseAndClose(List<String> s, bool closed, int _) =>
    s.length == 1 && s.first.contains(' 400 ') && closed ? 'PASS' : 'FAIL';

String _mustCloseAfter(List<String> s, bool closed, int _) =>
    s.length == 1 && closed ? 'PASS' : 'FAIL';

final List<_Case> _cases = [
  (
    name: 'HTTP/2 connection preface (h2c prior knowledge)',
    rule: 'V4.2.3-4 apply only if HTTP/2 is spoken: RFC 9113 3.4 preface',
    request: 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n',
    // An HTTP/2 server answers with a SETTINGS frame, not a status line.
    // An HTTP/1.1 status line, or a close with no bytes at all, is not it.
    verdict: (s, closed, bytes) =>
        s.isNotEmpty || (closed && bytes == 0) ? 'N/A: no HTTP/2' : 'FAIL',
  ),
  (
    name: 'control: two requests pipelined',
    rule: '9.3.2 pipelining: answered in order',
    request: _tail + _tail,
    verdict: (s, closed, _) => s.length == 2 ? 'PASS' : 'FAIL',
  ),
  (
    name: 'Content-Length and Transfer-Encoding: chunked',
    rule: '6.1: MAY reject or use TE alone; MUST close the connection after',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n'
        '0\r\n\r\n$_tail',
    verdict: _mustCloseAfter,
  ),
  (
    name: 'HTTP/1.0 with Transfer-Encoding',
    rule: '6.1: treat framing as faulty; close after processing',
    // Closed with nothing processed also leaves nothing on the connection.
    request: 'POST /Patient HTTP/1.0\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n'
        '0\r\n\r\n$_tail',
    verdict: (s, closed, _) => s.length <= 1 && closed ? 'PASS' : 'FAIL',
  ),
  (
    name: 'Transfer-Encoding: gzip (chunked not final)',
    rule: '6.3 item 4: MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding: gzip\r\n\r\n$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'Transfer-Encoding: chunked, gzip (chunked not final)',
    rule: '6.3 item 4: MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding: chunked, gzip\r\n\r\n0\r\n\r\n$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'two different Content-Length fields',
    rule: '6.3 item 5: invalid; MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: 2\r\nContent-Length: 40\r\n\r\n{}$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'Content-Length: 2, 40',
    rule: '6.3 item 5: invalid; MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: 2, 40\r\n\r\n{}$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'Content-Length: -2',
    rule: '6.3 item 5: invalid; MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: -2\r\n\r\n{}$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'Content-Length: +2',
    rule: '6.3 item 5: invalid (1*DIGIT); MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: +2\r\n\r\n{}$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'Content-Length: 0x2',
    rule: '6.3 item 5: invalid (1*DIGIT); MUST respond 400 and close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: 0x2\r\n\r\n{}$_tail',
    verdict: _mustRefuseAndClose,
  ),
  (
    name: 'Content-Length: 2, 2 (same values)',
    rule: '6.3 item 5: allowed, processed as 2',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length: 2, 2\r\n\r\n{}$_tail',
    // Refusing it too leaves nothing to smuggle; the RFC permits, not
    // requires, processing it.
    verdict: (s, closed, _) =>
        s.length == 2 || (s.length <= 1 && closed) ? 'PASS' : 'FAIL',
  ),
  (
    name: 'whitespace before the colon: Content-Length :',
    rule: '5.1: MUST reject with 400',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Content-Length : 2\r\n\r\n{}$_tail',
    verdict: (s, closed, _) =>
        s.isNotEmpty && s.first.contains(' 400 ') ? 'PASS' : 'FAIL',
  ),
  (
    name: 'whitespace before the colon: Transfer-Encoding :',
    rule: '5.1: MUST reject with 400',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding : chunked\r\n\r\n0\r\n\r\n$_tail',
    verdict: (s, closed, _) =>
        s.isNotEmpty && s.first.contains(' 400 ') ? 'PASS' : 'FAIL',
  ),
  (
    name: 'obs-fold in Transfer-Encoding',
    rule: '5.2: MUST reject 400, or replace the fold with SP',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding:\r\n chunked\r\n\r\n0\r\n\r\n$_tail',
    // Replaced with SP, the value is "chunked": framed as chunked (an empty
    // body, which fhirant answers 400 with an OperationOutcome), and the
    // tail is a second request. Refused by the parser: one bare 400, or a
    // closed connection.
    verdict: (s, closed, _) =>
        s.length == 2 || (s.length <= 1 && closed) ? 'PASS' : 'FAIL',
  ),
  (
    name: 'chunk size past 2^64',
    rule: '7.1: MUST prevent integer overflow in chunk-size',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding: chunked\r\n\r\n'
        '10000000000000002\r\n{}\r\n0\r\n\r\n$_tail',
    // Closed with no answer: no overflowed size was used to frame anything.
    verdict: (s, closed, _) => s.length <= 1 && closed ? 'PASS' : 'FAIL',
  ),
  (
    name: 'Transfer-Encoding: identity',
    rule: '6.1: coding not understood SHOULD 501; 6.3 item 4 400 + close',
    request: 'POST /Patient HTTP/1.1\r\nHost: x\r\n'
        'Content-Type: application/fhir+json\r\n'
        'Transfer-Encoding: identity\r\nContent-Length: 2\r\n\r\n{}$_tail',
    verdict: _mustRefuseAndClose,
  ),
];

Future<void> main() async {
  final out = File('tool/review_2026-10-17/smuggling_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('case\trule\tstatuses\tclosed\tbytes\tverdict\n')
    ..flushSync();
  final server = await createTestServer(devMode: true);
  final http = await shelf_io.serve(server.handler, '127.0.0.1', 0);
  try {
    for (final c in _cases) {
      final (statuses, closed, bytes) = await _send(http.port, c.request);
      final row = [
        c.name,
        c.rule,
        statuses.join(' | '),
        '$closed',
        '$bytes',
        c.verdict(statuses, closed, bytes),
      ].join('\t');
      out
        ..writeStringSync('$row\n')
        ..flushSync();
      stdout.writeln(row);
    }
  } finally {
    await http.close(force: true);
    await server.db.close();
    out.closeSync();
  }
}

/// The status lines the server sent for [request], whether it closed the
/// connection within 3 s of the last byte, and how many bytes it sent.
Future<(List<String>, bool, int)> _send(int port, String request) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final received = BytesBuilder();
  final done = Completer<bool>();
  socket
    ..listen(
      received.add,
      onDone: () => done.isCompleted ? null : done.complete(true),
      onError: (Object _) => done.isCompleted ? null : done.complete(true),
    )
    ..add(latin1.encode(request));
  await socket.flush();
  final closed = await done.future
      .timeout(const Duration(seconds: 3), onTimeout: () => false);
  socket.destroy();
  final bytes = received.takeBytes();
  final text = latin1.decode(bytes);
  final statuses = [
    for (final m in RegExp(r'HTTP/1\.[01] \d{3}[^\r\n]*').allMatches(text))
      m.group(0)!,
  ];
  return (statuses, closed, bytes.length);
}
