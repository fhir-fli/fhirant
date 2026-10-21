// What a shelf handler sees of a request carrying both Content-Length and
// Transfer-Encoding (RFC 9112 6.1), served by shelf_io over dart:io: the
// headers it is given, and what a `connection: close` reply does to the
// connection. Prints one line per observation.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/te_headers_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final server = await shelf_io.serve(
    (r) {
      stdout.writeln('seen ${r.method} ${r.url}: '
          'content-length=${r.headers['content-length']} '
          'transfer-encoding=${r.headers['transfer-encoding']} '
          'contentLength=${r.contentLength}');
      return Response.ok('ok', headers: {'connection': 'close'});
    },
    '127.0.0.1',
    0,
  );
  final socket = await Socket.connect('127.0.0.1', server.port);
  final got = StringBuffer();
  final done = Completer<bool>();
  socket
    ..listen(
      (b) => got.write(latin1.decode(b)),
      onDone: () => done.isCompleted ? null : done.complete(true),
    )
    ..add(
      latin1.encode(
        'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n'
        'Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n'
        'GET /b HTTP/1.1\r\nHost: x\r\n\r\n',
      ),
    );
  final closed = await done.future
      .timeout(const Duration(seconds: 3), onTimeout: () => false);
  stdout.writeln('responses=${'HTTP/1.1 '.allMatches('$got').length} '
      'closed=$closed');
  socket.destroy();
  await server.close(force: true);
}
