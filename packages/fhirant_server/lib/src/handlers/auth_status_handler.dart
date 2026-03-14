import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';

/// Handler for auth status. Returns whether this is a first-user setup.
///
/// No authentication required — this endpoint only reveals whether any
/// users exist, not how many or who they are.
Future<Response> authStatusHandler(
    Request request, FhirAntDb dbInterface) async {
  try {
    final userCount = await dbInterface.getUserCount();
    return Response.ok(
      jsonEncode({'firstUser': userCount == 0}),
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to check auth status: $e'}));
  }
}
