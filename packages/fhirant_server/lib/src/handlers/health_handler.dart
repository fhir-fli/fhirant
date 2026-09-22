import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

const _version = '1.0.0';

/// Health check endpoint. Returns server status, uptime, and DB connectivity.
Future<Response> healthHandler(
  Request request,
  FhirAntDb dbInterface,
  DateTime serverStartTime,
) async {
  final now = DateTime.now();
  final uptime = now.difference(serverStartTime);

  String status;
  try {
    await dbInterface.getUserCount();
    status = 'ok';
  } catch (e, stackTrace) {
    // Degraded, and the log says why; this used to say nothing.
    FhirantLogging().logWarning(
      'Health check: the store did not answer',
      e,
      stackTrace,
    );
    status = 'degraded';
  }

  return Response.ok(
    jsonEncode({
      'status': status,
      'uptime': uptime.inSeconds,
      'version': _version,
      'database': status == 'ok' ? 'connected' : 'error',
      'timestamp': now.toUtc().toIso8601String(),
    }),
    headers: {'content-type': 'application/json'},
  );
}
