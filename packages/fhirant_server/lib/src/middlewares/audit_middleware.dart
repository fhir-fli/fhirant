import 'dart:async';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Identifier system for fhirant's own user accounts.
///
/// The accounts live in fhirant's `users` table, not as FHIR resources, so
/// there is no URL to reference. This names the namespace the id belongs to,
/// which is what makes the id meaningful to a later reader.
const _userIdentifierSystem = 'urn:fhirant:users';

/// Collects AuditEvents and writes them in one transaction per tick.
///
/// Every audited request used to be its own `saveResource`, one commit
/// each, started from the response path and never waited for
/// (REVIEW-2026-09-06 finding 40; F11 measured a commit at 71.7 ms on this
/// desktop's disk). The events now wait here and go to the store together:
/// after [tick] at the latest, or at once when [flushAt] are pending. Nothing
/// is dropped; an audit trail that loses records under load is not one.
/// [drain] writes what is pending and is what the server calls on stop.
class AuditQueue {
  /// Creates a queue writing to [db]. [tick] and [flushAt] are choices, not
  /// specification numbers: a quarter second is below what a client notices
  /// when it reads its own trail back, and 200 events are one transaction of
  /// a few hundred kilobytes.
  AuditQueue(
    this.db, {
    this.tick = const Duration(milliseconds: 250),
    this.flushAt = 200,
  });

  /// Where the events are written.
  final FhirAntDb db;

  /// How long an event waits at most before its transaction.
  final Duration tick;

  /// How many pending events trigger a transaction at once.
  final int flushAt;

  final List<fhir.Resource> _pending = [];
  Timer? _timer;
  Future<void>? _writing;

  /// How many events are waiting for a transaction.
  int get pending => _pending.length;

  /// Queues [event]. Returns at once.
  void add(fhir.Resource event) {
    _pending.add(event);
    if (_pending.length >= flushAt) {
      _timer?.cancel();
      _timer = null;
      unawaited(_flush());
      return;
    }
    _timer ??= Timer(tick, () {
      _timer = null;
      unawaited(_flush());
    });
  }

  /// Writes everything pending, including what arrives while writing.
  Future<void> drain() async {
    _timer?.cancel();
    _timer = null;
    while (_pending.isNotEmpty || _writing != null) {
      await _flush();
    }
  }

  Future<void> _flush() async {
    // One writer at a time; a flush that finds one running waits for it and
    // then takes whatever has arrived since.
    while (_writing != null) {
      await _writing;
    }
    if (_pending.isEmpty) return;
    final batch = List<fhir.Resource>.of(_pending);
    _pending.clear();
    final write = _write(batch);
    _writing = write;
    try {
      await write;
    } finally {
      if (identical(_writing, write)) _writing = null;
    }
  }

  Future<void> _write(List<fhir.Resource> batch) async {
    try {
      await db.saveResources(batch);
    } catch (e, stack) {
      // The events are already built; a failed write is logged with what it
      // held rather than lost silently. Never thrown into the timer.
      FhirantLogging().logError(
        'Audit write of ${batch.length} event(s) failed',
        e,
        stack,
      );
    }
  }
}

/// Middleware that creates FHIR AuditEvent resources for auditable requests.
///
/// Place after auth middleware so that `auth_user` context is available.
/// The event is built after the response is decided and handed to [queue],
/// which writes events in one transaction per tick; the response never
/// waits for the store. A caller that passes no [queue] gets one of its own.
Middleware auditMiddleware(FhirAntDb dbInterface, {AuditQueue? queue}) {
  final events = queue ?? AuditQueue(dbInterface);
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);

      // A request that presented no credential and was refused for that is
      // not an access attempt by anyone the trail could name; recording it
      // gave any unauthenticated caller an unbounded write into the
      // database. A refused TOKEN is still recorded.
      final bareRefusal = response.statusCode == 401 &&
          request.headers['authorization'] == null;
      if (_shouldAudit(request) && !bareRefusal) {
        // Built off the response path, queued, written per tick.
        unawaited(_queueAuditEvent(request, response, dbInterface, events));
      }

      return response;
    };
  };
}

/// Returns false for paths that should not be audited.
bool _shouldAudit(Request request) {
  final path = request.url.path;

  // Skip empty path (root), metadata, favicon, and the health poll, which
  // reads no record and was written as an anonymous access on every poll
  // (REVIEW-2026-09-08 row 45).
  if (path.isEmpty ||
      path == 'metadata' ||
      path == 'favicon.ico' ||
      path == 'health' ||
      path == '.well-known/smart-configuration') {
    return false;
  }

  // Skip POST AuditEvent to prevent infinite loop
  if (request.method == 'POST' && path == 'AuditEvent') {
    return false;
  }

  return true;
}

/// Maps a request to a FHIR AuditEvent action code (audit-event-action:
/// C R U D E). A `POST …/_search` is a read, and a `POST …/$operation` an
/// execute; both used to be recorded as a create (REVIEW-2026-09-08 row
/// 46).
String _mapAction(String method, String path) {
  final segments = path.split('/');
  if (segments.isNotEmpty && segments.last == '_search') return 'R';
  if (segments.any((s) => s.startsWith(r'$'))) return 'E';
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

/// Maps a request to a FHIR AuditEvent subtype display.
String _mapSubtype(String method, String path) {
  final segments = path.split('/');
  if (segments.isNotEmpty && segments.last == '_search') return 'search';
  if (segments.any((s) => s.startsWith(r'$'))) return 'execute';
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

  // Only `[ResourceType]/[id]`: `auth/login`, `admin/unlock/3`,
  // `Patient/$export` and `ValueSet/$expand` are not references to a record
  // and used to be recorded as if they were (REVIEW-2026-09-08 row 46).
  final path = request.url.path;
  final segments = path.split('/');
  if (segments.length >= 2 &&
      fhir.R4ResourceType.fromString(segments[0]) != null &&
      segments[1].isNotEmpty &&
      !segments[1].startsWith('_') &&
      !segments[1].startsWith(r'$')) {
    return '${segments[0]}/${segments[1]}';
  }
  return null;
}

/// Builds the AuditEvent for one request and queues it.
Future<void> _queueAuditEvent(
  Request request,
  Response response,
  FhirAntDb dbInterface,
  AuditQueue queue,
) async {
  try {
    final authUser = request.context['auth_user'] as Map<String, dynamic>?;
    final username = authUser?['username'] as String? ?? 'anonymous';
    // ISO 27789 requires the audit record to identify the user. A display
    // name does not: two clinicians who share a name are indistinguishable in
    // a record kept for legal purposes. FHIR lets a Reference identify by
    // `identifier` without any resource existing, so the account id from the
    // token identifies the actor without inventing Practitioner resources.
    final userId = authUser?['userId'];

    final action = _mapAction(request.method, request.url.path);
    final subtype = _mapSubtype(request.method, request.url.path);
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
            if (userId != null)
              'identifier': {
                'system': _userIdentifierSystem,
                'value': '$userId',
              },
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

    queue.add(fhir.Resource.fromJson(auditEventJson));
  } catch (_) {
    // Audit logging must never break the response pipeline
  }
}
