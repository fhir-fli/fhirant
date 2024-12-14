import 'dart:async';
import 'dart:convert';
import 'package:fhirant/fhir_database.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class FhirRouter {
  FhirRouter(this.db);

  final FhirDatabase db;

  Router get router {
    final router = Router()

      // Get resource by resourceType and ID
      ..get('/fhir/<resourceType>/<id>', _getResource)

      // Create a new resource
      ..post('/fhir/<resourceType>', _createResource)

      // Update or create a resource
      ..put('/fhir/<resourceType>/<id>', _updateResource)

      // Delete a resource
      ..delete('/fhir/<resourceType>/<id>', _deleteResource);

    return router;
  }

  /// GET Handler: Retrieve a resource
  Future<Response> _getResource(
    Request request,
    String resourceType,
    String id,
  ) async {
    try {
      final resource = await db.getResource(resourceType, id);
      if (resource == null) {
        return Response.notFound(jsonEncode({'error': 'Resource not found'}));
      }
      return Response.ok(
        jsonEncode(resource),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode(
          {'error': 'Error retrieving resource', 'details': e.toString()},
        ),
      );
    }
  }

  /// POST Handler: Create a new resource
  Future<Response> _createResource(Request request, String resourceType) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = await db.createResource(resourceType, body);
      return Response(
        201,
        body: jsonEncode({'message': 'Resource created', 'id': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode(
          {'error': 'Error creating resource', 'details': e.toString()},
        ),
      );
    }
  }

  /// PUT Handler: Update or create a resource
  Future<Response> _updateResource(Request request, String resourceType) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      await db.updateResource(resourceType, body);
      return Response.ok(jsonEncode({'message': 'Resource updated'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode(
          {'error': 'Error updating resource', 'details': e.toString()},
        ),
      );
    }
  }

  /// DELETE Handler: Remove a resource
  Future<Response> _deleteResource(
    Request request,
    String resourceType,
    String id,
  ) async {
    try {
      await db.deleteResource(resourceType, id);
      return Response(204);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode(
          {'error': 'Error deleting resource', 'details': e.toString()},
        ),
      );
    }
  }
}
