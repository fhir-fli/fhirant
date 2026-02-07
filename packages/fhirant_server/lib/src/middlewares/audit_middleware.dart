import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';

/// Middleware that creates FHIR AuditEvent resources for auditable requests.
///
/// Place after auth middleware so that `auth_user` context is available.
/// AuditEvents are saved fire-and-forget so they don't slow down responses.
Middleware auditMiddleware(FhirAntDb dbInterface) {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);

      if (_shouldAudit(request)) {
        // Fire-and-forget — don't await
        _createAuditEvent(request, response, dbInterface);
      }

      return response;
    };
  };
}

/// Returns false for paths that should not be audited.
bool _shouldAudit(Request request) {
  final path = request.url.path;

  // Skip empty path (root), metadata, favicon
  if (path.isEmpty || path == 'metadata' || path == 'favicon.ico') {
    return false;
  }

  // Skip POST AuditEvent to prevent infinite loop
  if (request.method == 'POST' && path == 'AuditEvent') {
    return false;
  }

  return true;
}

/// Maps an HTTP method to a FHIR AuditEvent action code.
String _mapAction(String method) {
  switch (method) {
    case 'POST':
      return 'C';
    case 'GET':
      return 'R';
    case 'PUT':
      return 'U';
    case 'PATCH':
      return 'U';
    case 'DELETE':
      return 'D';
    default:
      return 'E';
  }
}

/// Maps an HTTP method to a FHIR AuditEvent subtype display.
String _mapSubtype(String method) {
  switch (method) {
    case 'POST':
      return 'create';
    case 'GET':
      return 'read';
    case 'PUT':
      return 'update';
    case 'PATCH':
      return 'patch';
    case 'DELETE':
      return 'delete';
    default:
      return 'execute';
  }
}

/// Maps an HTTP response status to a FHIR AuditEvent outcome code.
String _mapOutcome(int statusCode) {
  if (statusCode >= 200 && statusCode < 400) {
    return '0'; // Success
  } else if (statusCode >= 400 && statusCode < 500) {
    return '4'; // Minor failure (client error)
  } else {
    return '8'; // Serious failure (server error)
  }
}

/// Extracts an entity reference from the URL path (e.g., `Patient/123`).
String? _entityReference(Request request) {
  final path = request.url.path;
  // Match ResourceType or ResourceType/id
  final segments = path.split('/');
  if (segments.isNotEmpty) {
    if (segments.length >= 2) {
      return '${segments[0]}/${segments[1]}';
    }
    return segments[0];
  }
  return null;
}

/// Creates and saves a FHIR AuditEvent resource.
Future<void> _createAuditEvent(
  Request request,
  Response response,
  FhirAntDb dbInterface,
) async {
  try {
    final authUser =
        request.context['auth_user'] as Map<String, dynamic>?;
    final username = authUser?['username'] as String? ?? 'anonymous';

    final action = _mapAction(request.method);
    final subtype = _mapSubtype(request.method);
    final outcome = _mapOutcome(response.statusCode);
    final entityRef = _entityReference(request);

    final auditEventJson = <String, dynamic>{
      'resourceType': 'AuditEvent',
      'type': {
        'system': 'http://dicom.nema.org/resources/ontology/DCM',
        'code': '110112',
        'display': 'Query',
      },
      'subtype': [
        {
          'system': 'http://hl7.org/fhir/restful-interaction',
          'code': subtype,
          'display': subtype,
        },
      ],
      'action': action,
      'recorded': DateTime.now().toUtc().toIso8601String(),
      'outcome': outcome,
      'agent': [
        {
          'who': {
            'display': username,
            'reference': '#$username',
          },
          'requestor': true,
        },
      ],
      'source': {
        'observer': {
          'display': 'FHIRant Server',
          'reference': '#fhirant-server',
        },
      },
      if (entityRef != null)
        'entity': [
          {
            'what': {'reference': entityRef},
          },
        ],
    };

    final auditEvent = fhir.Resource.fromJson(auditEventJson);
    await dbInterface.saveResource(auditEvent);
  } catch (_) {
    // Audit logging must never break the response pipeline
  }
}
