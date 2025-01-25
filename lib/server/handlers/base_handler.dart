import 'package:shelf/shelf.dart';

/// Base handler for the root route
Response baseHandler(Request request) {
  return Response.ok(
    'Welcome to FHIR ANT!\nServer is running.',
    headers: {'Content-Type': 'text/plain'},
  );
}
