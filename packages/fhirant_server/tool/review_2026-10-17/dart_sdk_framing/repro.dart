import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((req) async {
    await req.drain<void>();
    req.response.write('served ${req.uri}');
    await req.response.close();
  });
  const tail = 'GET /second HTTP/1.1\r\nHost: x\r\n\r\n';
  final cases = {
    'CL + TE: chunked': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Content-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n$tail',
    'TE: gzip (chunked not final)': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Transfer-Encoding: gzip\r\n\r\n$tail',
    'two Content-Length values': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Content-Length: 2\r\nContent-Length: 40\r\n\r\n{}$tail',
    'space before colon': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Content-Length : 2\r\n\r\n{}$tail',
  };
  for (final MapEntry(key: name, value: request) in cases.entries) {
    final socket = await Socket.connect('127.0.0.1', server.port);
    final got = StringBuffer();
    final done = Completer<bool>();
    socket
      ..listen(
        (b) => got.write(latin1.decode(b)),
        onDone: () => done.isCompleted ? null : done.complete(true),
      )
      ..add(latin1.encode(request));
    final closed = await done.future
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    socket.destroy();
    final statuses =
        RegExp(r'HTTP/1\.1 \d{3}').allMatches('$got').map((m) => m[0]).toList();
    stdout.writeln('$name: responses=$statuses closed=$closed '
        'second-served=${'$got'.contains('served /second')}');
  }
  await server.close(force: true);
}
