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
      // saveResources answers false for a batch the store refused without
      // throwing; that answer was ignored and the events were lost with
      // no line in the log (REVIEW-2026-09-17 A16).
      final written = await db.saveResources(batch);
      if (!written) {
        FhirantLogging().logError(
          'Audit write of ${batch.length} event(s) failed: the store '
          'refused the batch',
        );
      }
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
/// Place BEFORE (outside) the auth middleware, so that a request it refuses
/// is still recorded. Who made the request is read from the response
/// context under `audit_agent`, which the auth middleware sets. The event
/// is built after the response is decided and handed to [queue], which
/// writes events in one transaction per tick; the response never waits for
/// the store. A caller that passes no [queue] gets one of its own.
Middleware auditMiddleware(FhirAntDb dbInterface, {AuditQueue? queue}) {
  final events = queue ?? AuditQueue(dbInterface);
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);

      // A request that presented no credential and was refused for that is
      // not an access attempt by anyone the trail could name; recording it
      // gave any unauthenticated caller an unbounded write into the
      // database. A refused TOKEN is still recorded (this middleware runs
      // outside the auth check, so it sees the refusal). So is a refused LOGIN
      // (the handler puts the claimed name in the response context): the
      // trail can name whose account was tried, and the credential
      // endpoints are rate limited, so the write is bounded
      // (REVIEW-2026-09-17 A16: failed logins used to leave no record).
      final bareRefusal = response.statusCode == 401 &&
          request.headers['authorization'] == null &&
          response.context['attempted_username'] == null;
      if (_shouldAudit(request) && !bareRefusal) {
        // Built off the response path, queued, written per tick. A Bundle
        // handler declares its entries in the response context and gets one
        // event per entry after the envelope's own (REVIEW-2026-09-06
        // finding 15).
        unawaited(_queueAuditEvent(request, response, dbInterface, events));
        final entries = response.context['audit_entries'];
        if (entries is List) {
          unawaited(
            _queueBundleEntryEvents(
              request,
              response,
              entries,
              dbInterface,
              events,
            ),
          );
        }
      }

      return response;
    };
  };
}

/// Returns false for paths that should not be audited.
bool _shouldAudit(Request request) {
  final path = request.url.path;

  // Skip the public root (a bare GET /), metadata, favicon, and the health
  // poll, which reads no record and was written as an anonymous access on
  // every poll (REVIEW-2026-09-08 row 45). A POST to the root is a Bundle
  // and is audited; the empty-path skip used to swallow it, so a
  // transaction left no trail at all (REVIEW-2026-09-06 finding 15).
  // `GET /?…` is the system search (R4B search.html 3.1.1.2) and is
  // audited as one; only the bare welcome page is skipped
  // (REVIEW-2026-10-06 finding 11).
  final bareRoot = path.isEmpty &&
      request.method != 'POST' &&
      !(request.method == 'GET' && request.url.hasQuery);
  if (bareRoot ||
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

/// A coding as AuditEvent JSON.
typedef _Coding = Map<String, String>;

_Coding _coding(String system, String code, String display) =>
    {'system': system, 'code': code, 'display': display};

const _dcm = 'http://dicom.nema.org/resources/ontology/DCM';
const _restfulInteraction = 'http://hl7.org/fhir/restful-interaction';

/// `rest`, "RESTful Operation" (R4B CodeSystem audit-event-type,
/// valuesets.json): the type IHE BALP fixes on its Create, Read, Update,
/// Delete and Query profiles (IHE.BasicAudit.*, StructureDefinition JSON
/// read 2026-11-21) and the R4B examples audit-event-example-search and
/// -vread carry.
final _Coding _restType = _coding(
  'http://terminology.hl7.org/CodeSystem/audit-event-type',
  'rest',
  'RESTful Operation',
);

/// What kind of event a request is, as AuditEvent records it.
///
/// Every event used to be `type` DCM 110112 "Query", a create and a failed
/// login included (REVIEW-2026-09-17-TRIAGE.md), with a subtype from
/// restful-interaction even where the request was not a FHIR interaction.
/// A FHIR interaction is now `rest` with its R4B restful-interaction code;
/// fhirant's own account routes take the DICOM PS3.15 audit message whose
/// definition they meet (PS3.15 A.5.3.10 Query, A.5.3.11 Security Alert,
/// A.5.3.12 User Authentication, and the codes in PS3.16 CID 400, 401 and
/// 403 with their Annex D definitions, read 2026-11-21). Each of those
/// three messages says of EventActionCode "Shall be: E Execute".
({_Coding type, _Coding? subtype, String action}) _classify(
  String method,
  String path,
) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments[0] == 'auth') {
    return _authEvent(method, segments.skip(1).join('/'));
  }
  if (segments.isNotEmpty && segments[0] == 'admin') {
    return _adminEvent(method, segments);
  }
  final interaction = _restfulInteractionOf(method, segments);
  return (
    type: _restType,
    subtype: interaction == null
        ? null
        : _coding(_restfulInteraction, interaction, interaction),
    action: interaction == null
        ? _actionOfMethod(method)
        : _actionOfInteraction(interaction),
  );
}

/// The `auth/` routes. Login and logout are DICOM 110114 "User
/// Authentication" ("User Authentication has been attempted"), subtypes
/// 110122 "Login" and 110123 "Logout" (PS3.15 A.5.3.12: "a user has
/// attempted to log on or log off ... regardless of whether the attempt was
/// successful or not"). `POST auth/authorize` is the sign-in form of the
/// authorization-code flow, so it is a login. Revoking a refresh token ends
/// the session it opened, so it is a logout. The token endpoint is IHE
/// IUA's ITI-71 Get Access Token, whose audit profile IHE.IUA.71 fixes type
/// 110114, subtype `urn:ihe:event-type-code#ITI-71` and action E (BALP
/// package StructureDefinition JSON, read 2026-11-21). Registering,
/// claiming or changing a password change a user's security attributes:
/// 110113 "Security Alert" with 110137 "User security Attributes Changed"
/// (CID 403; Annex D: "Security attributes of a user have been changed").
/// What reads only (`GET auth/status`, the sign-in page) is a query:
/// PS3.15 A.5.3.10, "Non-DICOM queries may also be captured by this
/// message".
({_Coding type, _Coding? subtype, String action}) _authEvent(
  String method,
  String route,
) {
  final authentication = _coding(_dcm, '110114', 'User Authentication');
  final login = _coding(_dcm, '110122', 'Login');
  final logout = _coding(_dcm, '110123', 'Logout');
  if (method == 'POST') {
    switch (route) {
      case 'login':
      case 'authorize':
        return (type: authentication, subtype: login, action: 'E');
      case 'logout':
      case 'revoke':
        return (type: authentication, subtype: logout, action: 'E');
      case 'token':
        return (
          type: authentication,
          subtype:
              _coding('urn:ihe:event-type-code', 'ITI-71', 'Get Access Token'),
          action: 'E',
        );
      case 'register':
      case 'password':
      case 'claim':
        return _userSecurityChanged;
    }
  }
  return _query;
}

/// The `admin/` routes. A role change is 110136 "Security Roles Changed"
/// ("Security roles have been changed"); a password reset, approving a
/// claim, unlocking, activating, deactivating or setting scopes change one
/// user's security attributes (110137). Registering, changing or removing
/// an app (`admin/clients/<id>`) is 110129 "Security Configuration": it
/// decides who may sign people in, and no user's attributes change.
/// Listing accounts or apps is a query. (DICOM codes from R4B
/// valuesets.json, read 2026-11-22.)
({_Coding type, _Coding? subtype, String action}) _adminEvent(
  String method,
  List<String> segments,
) {
  if (method == 'GET') return _query;
  if (segments.length >= 2 && segments[1] == 'clients') {
    return (
      type: _securityAlert,
      subtype: _coding(_dcm, '110129', 'Security Configuration'),
      action: 'E',
    );
  }
  if (segments.length == 4 && segments[3] == 'role') {
    return (
      type: _securityAlert,
      subtype: _coding(_dcm, '110136', 'Security Roles Changed'),
      action: 'E',
    );
  }
  return _userSecurityChanged;
}

final _Coding _securityAlert = _coding(_dcm, '110113', 'Security Alert');

final ({_Coding type, _Coding? subtype, String action}) _userSecurityChanged = (
  type: _securityAlert,
  subtype: _coding(_dcm, '110137', 'User security Attributes Changed'),
  action: 'E',
);

final ({_Coding type, _Coding? subtype, String action}) _query = (
  type: _coding(_dcm, '110112', 'Query'),
  subtype: null,
  action: 'E',
);

/// The R4B restful-interaction code (valuesets.json, CodeSystem
/// restful-interaction 4.3.0, read whole 2026-11-21) for [method] on the
/// path [segments], or null when the path is no FHIR interaction (an
/// unknown first segment).
///
/// R4B has no `search-compartment` (it is R5's); a compartment search is
/// the parent code `search`. An operation is `operation`: `execute` is no
/// code there. A history read is `history-instance`, `-type` or `-system`
/// and a version read `vread`; all used to be `read`.
String? _restfulInteractionOf(String method, List<String> segments) {
  bool isType(String s) => fhir.R4ResourceType.fromString(s) != null;
  bool isOperation(String s) => s.startsWith(r'$');
  if (segments.isEmpty) {
    if (method == 'GET') return 'search-system';
    // A POST to the base is a Bundle; the handler declares transaction or
    // batch and that wins over this.
    return null;
  }
  final first = segments[0];
  if (isOperation(first)) return 'operation';
  if (segments.length == 1 && first == '_search') return 'search-system';
  if (segments.length == 1 && first == '_history') return 'history-system';
  if (!isType(first)) return null;
  if (segments.length == 1) {
    return switch (method) {
      'GET' => 'search-type',
      'POST' => 'create',
      'PUT' => 'update',
      'PATCH' => 'patch',
      'DELETE' => 'delete',
      _ => null,
    };
  }
  final second = segments[1];
  if (isOperation(second)) return 'operation';
  if (segments.length == 2 && second == '_search') return 'search-type';
  if (segments.length == 2 && second == '_history') return 'history-type';
  if (second.startsWith('_')) return null;
  if (segments.length == 2) {
    return switch (method) {
      'GET' => 'read',
      'PUT' => 'update',
      'PATCH' => 'patch',
      'DELETE' => 'delete',
      _ => null,
    };
  }
  final third = segments[2];
  if (isOperation(third)) return 'operation';
  if (third == '_history') {
    if (segments.length == 3) return 'history-instance';
    if (segments.length == 4) return 'vread';
    return null;
  }
  if (isType(third) || third == '*') {
    if (segments.length == 3) return 'search';
    if (segments.length == 4 && segments[3] == '_search') return 'search';
  }
  return null;
}

/// The action for a restful interaction. A search is E: the R4B
/// audit-event-action definition of E includes "perform a query/search
/// operation", BALP's Query profile fixes action E, and the R4B example
/// audit-event-example-search carries E. A read, version read or history
/// read is R ("Display or print data"; audit-event-example-vread carries
/// R). An operation, transaction or batch is E.
String _actionOfInteraction(String interaction) {
  switch (interaction) {
    case 'create':
      return 'C';
    case 'read':
    case 'vread':
    case 'history-instance':
    case 'history-type':
    case 'history-system':
      return 'R';
    case 'update':
    case 'patch':
      return 'U';
    case 'delete':
      return 'D';
    default:
      return 'E';
  }
}

/// The action for a request that names no interaction (an unknown path),
/// from its method alone.
String _actionOfMethod(String method) => switch (method) {
      'POST' => 'C',
      'GET' => 'R',
      'PUT' || 'PATCH' => 'U',
      'DELETE' => 'D',
      _ => 'E',
    };

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
  return _entityFromPath(request.url.path);
}

/// `[ResourceType]/[id]` from a request path, or null.
///
/// Only that shape: `auth/login`, `admin/unlock/3`, `Patient/$export` and
/// `ValueSet/$expand` are not references to a record and used to be
/// recorded as if they were (REVIEW-2026-09-08 row 46).
String? _entityFromPath(String path) {
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

/// Who the auth check established for this request, as it declared on the
/// response (auth_middleware.dart, `auditAgentKey`), or null.
Map<String, dynamic>? _agentOf(Response response) {
  final agent = response.context['audit_agent'];
  return agent is Map<String, dynamic> ? agent : null;
}

/// Builds the AuditEvent for one request and queues it.
Future<void> _queueAuditEvent(
  Request request,
  Response response,
  FhirAntDb dbInterface,
  AuditQueue queue,
) async {
  // A Bundle request is recorded as the `transaction` or `batch` interaction
  // it is (restful-interaction has both codes), not as a `create` of
  // nothing; its entries follow as events of their own.
  final bundleSubtype = response.context['audit_subtype'];
  final attempted = response.context['attempted_username'];
  await _queueEvent(
    request,
    dbInterface,
    queue,
    method: request.method,
    path: request.url.path,
    statusCode: response.statusCode,
    entityRef: _entityReference(request, response),
    interaction: bundleSubtype is String ? bundleSubtype : null,
    attemptedUsername: attempted is String ? attempted : null,
    agent: _agentOf(response),
  );
}

/// One event per Bundle entry, as declared by the Bundle handler: each
/// carries the entry's own method, status, record and subject of care, so
/// a transaction touching N patients leaves N patients in the trail
/// (REVIEW-2026-09-06 finding 15).
Future<void> _queueBundleEntryEvents(
  Request request,
  Response response,
  List<dynamic> entries,
  FhirAntDb dbInterface,
  AuditQueue queue,
) async {
  for (final entry in entries) {
    if (entry is! Map) continue;
    final method = entry['method'];
    final url = entry['url'];
    final status = entry['status'];
    final patient = entry['patient'];
    if (method is! String || url is! String || status is! int) continue;
    final path = url.split('?').first;
    final entityRef = _entityFromPath(path);
    // A created entry is declared by its new id (`Patient/new-id`), which as
    // a request path would name no interaction.
    final created = method == 'POST' && entityRef != null;
    await _queueEvent(
      request,
      dbInterface,
      queue,
      method: method,
      path: path,
      statusCode: status,
      entityRef: entityRef,
      patientRef: patient is String ? patient : null,
      interaction: created ? 'create' : null,
      agent: _agentOf(response),
    );
  }
}

/// Builds one AuditEvent for [request] and queues it. [method], [path] and
/// [statusCode] are the request recorded (the request's own, or one
/// Bundle entry's); [entityRef] the record it touched; [patientRef] the
/// subject of care when the caller already knows it (a deleted resource's,
/// read before the delete), else resolved from the record.
Future<void> _queueEvent(
  Request request,
  FhirAntDb dbInterface,
  AuditQueue queue, {
  required String method,
  required String path,
  required int statusCode,
  String? entityRef,
  String? patientRef,
  String? interaction,
  String? attemptedUsername,
  Map<String, dynamic>? agent,
}) async {
  try {
    final authUser = agent;
    // A refused login names the account that was tried. It goes in
    // agent.name (R4B AuditEvent.agent.name, profiles-resources.json:
    // "Human-meaningful name for the agent") and in who.display, with no
    // identifier: nothing was proven about who typed it.
    final username =
        authUser?['username'] as String? ?? attemptedUsername ?? 'anonymous';
    // ISO 27789 requires the audit record to identify the user. A display
    // name does not: two clinicians who share a name are indistinguishable in
    // a record kept for legal purposes. FHIR lets a Reference identify by
    // `identifier` without any resource existing, so the account id from the
    // token identifies the actor without inventing Practitioner resources.
    final userId = authUser?['userId'];

    // [interaction] is a restful-interaction code the caller knows better
    // than the path does: a Bundle's `transaction` or `batch`, or a created
    // entry.
    final kind = interaction == null
        ? _classify(method, path)
        : (
            type: _restType,
            subtype: _coding(_restfulInteraction, interaction, interaction),
            action: _actionOfInteraction(interaction),
          );
    final outcome = _mapOutcome(statusCode);
    var subjectRef = patientRef;

    // ISO 27789:2021 requires an audit record to identify the subject of care.
    // The resource in the URL is often not that person: reading
    // `Observation/123` is an access to a patient's record, and until the
    // Observation is resolved back to its subject the trail cannot say whose.
    if (subjectRef == null && entityRef != null) {
      final parts = entityRef.split('/');
      if (parts.length == 2) {
        final subject = await dbInterface.subjectOfCare(parts[0], parts[1]);
        if (subject != null) {
          subjectRef = 'Patient/$subject';
        }
      }
    }

    // Set by _trustedClientIpMiddleware from the socket, not by the caller.
    final clientIp = request.headers['x-forwarded-for'];

    final auditEventJson = <String, dynamic>{
      'resourceType': 'AuditEvent',
      'type': kind.type,
      if (kind.subtype != null) 'subtype': [kind.subtype],
      'action': kind.action,
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
          if (attemptedUsername != null && authUser == null)
            'name': attemptedUsername,
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
      if (entityRef != null || subjectRef != null)
        'entity': [
          if (entityRef != null)
            {
              'what': {'reference': entityRef},
            },
          // R4 has no `AuditEvent.patient` element; the `patient` search
          // parameter is defined over `agent.who` and `entity.what`, so the
          // subject of care is carried as an entity with the Patient role.
          if (subjectRef != null && subjectRef != entityRef)
            {
              'what': {'reference': subjectRef},
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
  } catch (e, stackTrace) {
    // Never thrown into the response pipeline; never silent either. An
    // event that cannot be built is a use of the record with no trace, and
    // this used to drop it without a word.
    FhirantLogging().logError(
      'Audit event could not be built for $method $path',
      e,
      stackTrace,
    );
  }
}
