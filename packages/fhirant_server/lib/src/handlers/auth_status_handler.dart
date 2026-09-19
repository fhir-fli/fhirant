import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for auth status. Returns whether this is a first-user setup,
/// and whether the first registration must carry the server's bootstrap
/// token (`bootstrapTokenRequired`; REVIEW-2026-09-17 A15).
///
/// No authentication required — this endpoint only reveals whether any
/// users exist, not how many or who they are.
Future<Response> authStatusHandler(
  Request request,
  FhirAntDb dbInterface, {
  String? bootstrapToken,
}) async {
  try {
    final userCount = await dbInterface.getUserCount();
    return Response.ok(
      jsonEncode({
        'firstUser': userCount == 0,
        'bootstrapTokenRequired': userCount == 0 && bootstrapToken != null,
      }),
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Failed to check auth status', e, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to check auth status'}),
    );
  }
}
