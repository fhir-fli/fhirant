import 'dart:io';

import 'package:shelf/shelf.dart';

/// Favicon Handler
Future<Response> favicoHandler(Request request) async {
  try {
    final faviconBytes = await File('assets/fhirant_logo.png').readAsBytes();
    return Response.ok(
      faviconBytes,
      headers: {'Content-Type': 'image/png'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: 'Error serving favicon: $e',
    );
  }
}
