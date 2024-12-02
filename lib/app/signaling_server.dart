// ignore_for_file: avoid_print

import 'dart:io';

class SignalingServer {
  HttpServer? _server;

  Future<void> startServer({int port = 3000}) async {
    if (_server != null) return;

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Signaling server running on ws://${_server!.address.address}:$port');

    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        print('Client connected.');

        socket.listen((message) {
          print('Message received: $message');
        });
      } else {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..write('WebSocket connections only.');
          await request.response.close();
      }
    });
  }

  Future<void> stopServer() async {
    if (_server == null) return;
    await _server!.close();
    _server = null;
    print('Signaling server stopped.');
  }
}
