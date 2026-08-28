import 'dart:async';

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
        unawaited(_createAuditEvent(request, response, dbInterface));
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
/// Returns null for type-level operations (no resource ID) since bare
/// resource type names are not valid FHIR references.
///
/// An operation whose path names no resource can declare what it actually
/// read by putting `audit_entity` in its response context. `$fhirpath` reads
/// a record straight out of the database, and the path `/$fhirpath` says
/// nothing about which one.
String? _entityReference(Request request, Response response) {
  final declared = response.context['audit_entity'];
  if (declared is String && declared.isNotEmpty) return declared;

  final path = request.url.path;
  final segments = path.split('/');
  if (segments.length >= 2 &&
      segments[1].isNotEmpty &&
      !segments[1].startsWith('_')) {
    return '${segments[0]}/${segments[1]}';
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
    final authUser = request.context['auth_user'] as Map<String, dynamic>?;
    final username = authUser?['username'] as String? ?? 'anonymous';

    final action = _mapAction(request.method);
    final subtype = _mapSubtype(request.method);
    final outcome = _mapOutcome(response.statusCode);
    final entityRef = _entityReference(request, response);

    // ISO 27789:2021 requires an audit record to identify the subject of care.
    // The resource in the URL is often not that person: reading
    // `Observation/123` is an access to a patient's record, and until the
    // Observation is resolved back to its subject the trail cannot say whose.
    String? patientRef;
    if (entityRef != null) {
      final parts = entityRef.split('/');
      if (parts.length == 2) {
        final subject = await dbInterface.subjectOfCare(parts[0], parts[1]);
        if (subject != null) {
          patientRef = 'Patient/$subject';
        }
      }
    }

    // Set by _trustedClientIpMiddleware from the socket, not by the caller.
    final clientIp = request.headers['x-forwarded-for'];

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
          },
          'requestor': true,
          if (clientIp != null)
            'network': {
              'address': clientIp,
              'type': '2', // IP address
            },
        },
      ],
      'source': {
        'observer': {
          'display': 'FHIRant Server',
        },
      },
      if (entityRef != null || patientRef != null)
        'entity': [
          if (entityRef != null)
            {
              'what': {'reference': entityRef},
            },
          // R4 has no `AuditEvent.patient` element; the `patient` search
          // parameter is defined over `agent.who` and `entity.what`, so the
          // subject of care is carried as an entity with the Patient role.
          if (patientRef != null && patientRef != entityRef)
            {
              'what': {'reference': patientRef},
              'type': {
                'system':
                    'http://terminology.hl7.org/CodeSystem/audit-entity-type',
                'code': '1',
                'display': 'Person',
              },
              'role': {
                'system': 'http://terminology.hl7.org/CodeSystem/object-role',
                'code': '1',
                'display': 'Patient',
              },
            },
        ],
    };

    final auditEvent = fhir.Resource.fromJson(auditEventJson);
    await dbInterface.saveResource(auditEvent);
  } catch (_) {
    // Audit logging must never break the response pipeline
  }
}
