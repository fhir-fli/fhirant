import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final seen = Completer<String>();
  server.listen((req) async {
    if (!seen.isCompleted) {
      seen.complete('content-length=${req.headers.value('content-length')} '
          'transfer-encoding=${req.headers.value('transfer-encoding')} '
          'contentLength=${req.contentLength} '
          'chunked=${req.headers.chunkedTransferEncoding} '
          'persistent=${req.persistentConnection}');
    }
    await req.drain<void>();
    await req.response.close();
  });
  final socket = await Socket.connect('127.0.0.1', server.port)
    ..add(
      latin1.encode('POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n'
          'Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n'),
    );
  stdout.writeln(await seen.future);
  socket.destroy();
  await server.close(force: true);
}
