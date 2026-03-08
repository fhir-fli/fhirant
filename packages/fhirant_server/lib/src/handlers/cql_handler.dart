import 'dart:convert';

import 'package:antlr4/antlr4.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_cql/fhir_r4_cql.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Library/$evaluate — evaluate a stored CQL Library resource.
///
/// Route: `POST /Library/<id>/$evaluate`
///
/// Standard parameters (in request body as FHIR Parameters):
/// - `subject` (string): Patient reference (e.g. "Patient/123")
/// - `parameters` (Parameters resource): Input parameters for the library
/// - `data` (Bundle resource): Additional data for evaluation context
///
/// The Library resource must have CQL or ELM content in its `content[]`
/// attachments with contentType `text/cql` or `application/elm+json`.
Future<Response> libraryEvaluateHandler(
  Request request,
  String libraryId,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Library/${'evaluate'}: loading Library/$libraryId');

    // Load the Library resource from the database
    final libraryResource = await dbInterface.getResource(
      fhir.R4ResourceType.Library,
      libraryId,
    );
    if (libraryResource == null) {
      return _errorResponse(404, 'not-found', 'Library/$libraryId not found');
    }

    final library = libraryResource as fhir.Library;

    // Extract CQL or ELM from the Library's content attachments
    final cqlLibrary = _extractCqlFromLibrary(library);
    if (cqlLibrary == null) {
      return _errorResponse(
        422,
        'invalid',
        'Library/$libraryId has no evaluable content. '
            'Expected content with contentType text/cql or application/elm+json',
      );
    }

    // Parse request body for evaluation parameters
    final evalParams = await _parseEvaluateParams(request);

    // Build execution context
    final context = await _buildContext(
      evalParams,
      dbInterface,
    );

    // Execute
    final result = await cqlLibrary.execute(context);

    FhirantLogging()
        .logInfo('Library/$libraryId/${'evaluate'} completed successfully');

    return Response.ok(
      jsonEncode(_buildParametersResponse(result)),
      headers: {'Content-Type': 'application/fhir+json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Library/${'evaluate'} failed', e, stackTrace);
    return _errorResponse(
      500,
      'exception',
      'CQL evaluation error: ${e.toString()}',
    );
  }
}

/// Library/$evaluate without an ID — evaluate by canonical URL or inline.
///
/// Route: `POST /Library/$evaluate`
///
/// Parameters (FHIR Parameters body):
/// - `url` (uri): Canonical URL of a Library resource to look up
/// - `library` (Library resource): Inline Library resource
/// - `subject` (string): Patient reference
/// - `parameters` (Parameters resource): Input parameters
/// - `data` (Bundle resource): Additional data
Future<Response> libraryEvaluateByUrlHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Library/${'evaluate'} (by URL/inline)');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return _errorResponse(400, 'invalid', 'Request body is required');
    }

    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResponse(400, 'invalid', 'Invalid JSON in request body');
    }

    final evalParams = _parseParametersResource(bodyJson);

    // Resolve the Library — by URL, inline resource, or inline CQL/ELM
    CqlLibrary? cqlLibrary;

    if (evalParams.libraryResource != null) {
      // Inline Library resource
      final library = fhir.Library.fromJson(evalParams.libraryResource!);
      cqlLibrary = _extractCqlFromLibrary(library);
    } else if (evalParams.url != null) {
      // Look up by canonical URL
      final results = await dbInterface.search(
        resourceType: fhir.R4ResourceType.Library,
        searchParameters: {'url': [evalParams.url!]},
      );
      if (results.isEmpty) {
        return _errorResponse(
          404,
          'not-found',
          'No Library found with url: ${evalParams.url}',
        );
      }
      cqlLibrary = _extractCqlFromLibrary(results.first as fhir.Library);
    } else if (evalParams.cqlSource != null) {
      // Convenience: inline CQL source
      cqlLibrary = _parseCql(evalParams.cqlSource!);
    } else if (evalParams.elmJson != null) {
      // Convenience: inline ELM JSON
      final elmMap = jsonDecode(evalParams.elmJson!) as Map<String, dynamic>;
      cqlLibrary = CqlLibrary.fromJson(elmMap);
    }

    if (cqlLibrary == null) {
      return _errorResponse(
        400,
        'invalid',
        'No evaluable library provided. Supply a Library id, url, '
            'inline library resource, cql, or elm parameter',
      );
    }

    final context = await _buildContext(evalParams, dbInterface);
    final result = await cqlLibrary.execute(context);

    FhirantLogging().logInfo('Library/${'evaluate'} (by URL/inline) completed');

    return Response.ok(
      jsonEncode(_buildParametersResponse(result)),
      headers: {'Content-Type': 'application/fhir+json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Library/${'evaluate'} failed', e, stackTrace);
    return _errorResponse(
      500,
      'exception',
      'CQL evaluation error: ${e.toString()}',
    );
  }
}

/// Convenience endpoint: `POST /$cql`
///
/// Ad-hoc CQL evaluation without needing a stored Library resource.
/// Accepts plain JSON or FHIR Parameters with:
/// - `cql` (string): CQL source text
/// - `elm` (string): ELM JSON
/// - `subject` or `patientId` (string): Patient reference
/// - `data` (Bundle): Resource context
/// - `parameters` (Parameters): Input parameters
Future<Response> cqlHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Received \$cql request');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return _errorResponse(400, 'invalid', 'Request body is required');
    }

    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResponse(400, 'invalid', 'Invalid JSON in request body');
    }

    final evalParams = bodyJson['resourceType'] == 'Parameters'
        ? _parseParametersResource(bodyJson)
        : _parsePlainJson(bodyJson);

    if (evalParams.cqlSource == null && evalParams.elmJson == null) {
      return _errorResponse(
        400,
        'invalid',
        'Either "cql" (CQL source text) or "elm" (ELM JSON) parameter '
            'is required',
      );
    }

    CqlLibrary cqlLibrary;
    try {
      if (evalParams.elmJson != null) {
        final elmMap =
            jsonDecode(evalParams.elmJson!) as Map<String, dynamic>;
        cqlLibrary = CqlLibrary.fromJson(elmMap);
      } else {
        cqlLibrary = _parseCql(evalParams.cqlSource!);
      }
    } catch (e) {
      return _errorResponse(
        400,
        'invalid',
        'Failed to parse CQL/ELM: ${e.toString()}',
      );
    }

    final context = await _buildContext(evalParams, dbInterface);
    final result = await cqlLibrary.execute(context);

    FhirantLogging().logInfo('CQL expression evaluated successfully');

    return Response.ok(
      jsonEncode(_buildParametersResponse(result)),
      headers: {'Content-Type': 'application/fhir+json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('CQL evaluation failed', e, stackTrace);
    return _errorResponse(
      500,
      'exception',
      'CQL evaluation error: ${e.toString()}',
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Parsed evaluation parameters shared across all three endpoints.
class _EvalParams {
  final String? subject;
  final Map<String, dynamic>? dataBundle;
  final Map<String, dynamic>? inputParameters;
  final String? cqlSource;
  final String? elmJson;
  final String? url;
  final Map<String, dynamic>? libraryResource;

  _EvalParams({
    this.subject,
    this.dataBundle,
    this.inputParameters,
    this.cqlSource,
    this.elmJson,
    this.url,
    this.libraryResource,
  });
}

/// Parse evaluation parameters from a FHIR Parameters resource body.
_EvalParams _parseParametersResource(Map<String, dynamic> bodyJson) {
  String? subject;
  Map<String, dynamic>? dataBundle;
  Map<String, dynamic>? inputParameters;
  String? cqlSource;
  String? elmJson;
  String? url;
  Map<String, dynamic>? libraryResource;

  final params = bodyJson['parameter'] as List<dynamic>? ?? [];
  for (final param in params) {
    if (param is! Map<String, dynamic>) continue;
    final name = param['name'] as String?;
    switch (name) {
      case 'subject':
        subject = param['valueString'] as String?;
        break;
      case 'patientId':
        // Convenience alias — auto-prefix with Patient/
        final id = param['valueString'] as String?;
        if (id != null) {
          subject = id.startsWith('Patient/') ? id : 'Patient/$id';
        }
        break;
      case 'data':
        dataBundle = param['resource'] as Map<String, dynamic>?;
        break;
      case 'parameters':
        inputParameters = param['resource'] as Map<String, dynamic>?;
        break;
      case 'cql':
        cqlSource = param['valueString'] as String?;
        break;
      case 'elm':
        elmJson = param['valueString'] as String?;
        break;
      case 'url':
        url = (param['valueUri'] ?? param['valueString']) as String?;
        break;
      case 'library':
        libraryResource = param['resource'] as Map<String, dynamic>?;
        break;
    }
  }

  return _EvalParams(
    subject: subject,
    dataBundle: dataBundle,
    inputParameters: inputParameters,
    cqlSource: cqlSource,
    elmJson: elmJson,
    url: url,
    libraryResource: libraryResource,
  );
}

/// Parse evaluation parameters from a plain JSON object (convenience).
_EvalParams _parsePlainJson(Map<String, dynamic> json) {
  String? subject = json['subject'] as String?;
  final patientId = json['patientId'] as String?;
  if (subject == null && patientId != null) {
    subject = patientId.startsWith('Patient/') ? patientId : 'Patient/$patientId';
  }

  return _EvalParams(
    subject: subject,
    dataBundle: json['data'] as Map<String, dynamic>?,
    inputParameters: json['parameters'] as Map<String, dynamic>?,
    cqlSource: json['cql'] as String?,
    elmJson: json['elm'] as String?,
    url: json['url'] as String?,
    libraryResource: json['library'] as Map<String, dynamic>?,
  );
}

/// Parse evaluation parameters from the request body (for Library/$evaluate).
Future<_EvalParams> _parseEvaluateParams(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) return _EvalParams();

  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['resourceType'] == 'Parameters') {
      return _parseParametersResource(json);
    }
    return _parsePlainJson(json);
  } catch (_) {
    return _EvalParams();
  }
}

/// Extract a CqlLibrary from a FHIR Library resource's content attachments.
CqlLibrary? _extractCqlFromLibrary(fhir.Library library) {
  final contents = library.content;
  if (contents == null || contents.isEmpty) return null;

  // Prefer ELM JSON over CQL source (already compiled)
  for (final attachment in contents) {
    final contentType = attachment.contentType?.primitiveValue;
    final data = attachment.data?.primitiveValue;
    if (data == null) continue;

    final decoded = _base64Decode(data);
    if (decoded == null) continue;

    if (contentType == 'application/elm+json') {
      try {
        final elmMap = jsonDecode(decoded) as Map<String, dynamic>;
        return CqlLibrary.fromJson(elmMap);
      } catch (_) {
        continue;
      }
    }
  }

  // Fall back to CQL source
  for (final attachment in contents) {
    final contentType = attachment.contentType?.primitiveValue;
    final data = attachment.data?.primitiveValue;
    if (data == null) continue;

    final decoded = _base64Decode(data);
    if (decoded == null) continue;

    if (contentType == 'text/cql') {
      try {
        return _parseCql(decoded);
      } catch (_) {
        continue;
      }
    }
  }

  return null;
}

/// Safely decode base64 content.
String? _base64Decode(String encoded) {
  try {
    return utf8.decode(base64Decode(encoded));
  } catch (_) {
    return null;
  }
}

/// Build a CQL execution context from evaluation parameters.
Future<Map<String, dynamic>> _buildContext(
  _EvalParams params,
  FhirAntDb dbInterface,
) async {
  final context = <String, dynamic>{};

  // Load data from inline bundle
  if (params.dataBundle != null) {
    context.addAll(BundleDataProvider.fromBundle(params.dataBundle!));
  }

  // Load patient context from subject reference
  if (params.subject != null) {
    final patientId = params.subject!.startsWith('Patient/')
        ? params.subject!.substring(8)
        : params.subject!;

    final patient = await dbInterface.getResource(
      fhir.R4ResourceType.Patient,
      patientId,
    );
    if (patient != null) {
      context['Patient'] = patient.toJson();

      // Auto-load common resource types if no data bundle was provided
      if (params.dataBundle == null) {
        await _loadPatientData(context, patientId, dbInterface);
      }
    }
  }

  // Add input parameters
  if (params.inputParameters != null &&
      params.inputParameters!['resourceType'] == 'Parameters') {
    final paramList =
        params.inputParameters!['parameter'] as List<dynamic>? ?? [];
    for (final param in paramList) {
      if (param is! Map<String, dynamic>) continue;
      final name = param['name'] as String?;
      if (name == null) continue;
      final value = _extractParameterValue(param);
      if (value != null) {
        context[name] = value;
      }
    }
  }

  return context;
}

/// Parse CQL source text into a CqlLibrary using the ANTLR pipeline.
CqlLibrary _parseCql(String cqlSource) {
  final input = InputStream.fromString(cqlSource);
  final lexer = cqlLexer(input);
  final tokens = CommonTokenStream(lexer);
  final parser = cqlParser(tokens);
  parser.addErrorListener(ElmErrorListener());
  parser.buildParseTree = true;

  final libraryContext = parser.library_();
  final visitor = CqlBaseVisitor();
  visitor.visitLibrary(libraryContext);
  return visitor.library;
}

/// Load common resource types for a patient from the database.
Future<void> _loadPatientData(
  Map<String, dynamic> context,
  String patientId,
  FhirAntDb dbInterface,
) async {
  const resourceTypes = [
    fhir.R4ResourceType.Condition,
    fhir.R4ResourceType.Observation,
    fhir.R4ResourceType.MedicationRequest,
    fhir.R4ResourceType.Procedure,
    fhir.R4ResourceType.Encounter,
    fhir.R4ResourceType.Immunization,
    fhir.R4ResourceType.AllergyIntolerance,
    fhir.R4ResourceType.DiagnosticReport,
    fhir.R4ResourceType.MedicationStatement,
    fhir.R4ResourceType.CarePlan,
  ];

  for (final type in resourceTypes) {
    try {
      final results = await dbInterface.search(
        resourceType: type,
        searchParameters: {'patient': ['Patient/$patientId']},
      );
      if (results.isNotEmpty) {
        context[type.name] = results.map((r) => r.toJson()).toList();
      }
    } catch (_) {
      // Skip resource types that don't have a patient search param
    }
  }
}

/// Extract a typed value from a FHIR Parameters parameter entry.
dynamic _extractParameterValue(Map<String, dynamic> param) {
  if (param.containsKey('valueString')) return param['valueString'];
  if (param.containsKey('valueBoolean')) return param['valueBoolean'];
  if (param.containsKey('valueInteger')) return param['valueInteger'];
  if (param.containsKey('valueDecimal')) return param['valueDecimal'];
  if (param.containsKey('valueDate')) return param['valueDate'];
  if (param.containsKey('valueDateTime')) return param['valueDateTime'];
  if (param.containsKey('valueCode')) return param['valueCode'];
  if (param.containsKey('valueUri')) return param['valueUri'];
  if (param.containsKey('resource')) return param['resource'];
  return null;
}

/// Build a FHIR Parameters response from CQL execution results.
Map<String, dynamic> _buildParametersResponse(dynamic result) {
  final parameters = <Map<String, dynamic>>[];

  if (result is Map<String, dynamic>) {
    for (final entry in result.entries) {
      final param = _resultToParameter(entry.key, entry.value);
      if (param != null) parameters.add(param);
    }
  } else {
    final param = _resultToParameter('result', result);
    if (param != null) parameters.add(param);
  }

  return {
    'resourceType': 'Parameters',
    'parameter': parameters,
  };
}

/// Convert a CQL result value to a FHIR Parameters parameter entry.
Map<String, dynamic>? _resultToParameter(String name, dynamic value) {
  if (value == null) {
    return {'name': name, 'valueString': 'null'};
  }
  if (value is bool) {
    return {'name': name, 'valueBoolean': value};
  }
  if (value is int) {
    return {'name': name, 'valueInteger': value};
  }
  if (value is double) {
    return {'name': name, 'valueDecimal': value};
  }
  if (value is String) {
    return {'name': name, 'valueString': value};
  }

  // FHIR primitive types
  if (value is fhir.FhirBoolean) {
    return {'name': name, 'valueBoolean': value.primitiveValue == 'true'};
  }
  if (value is fhir.FhirInteger) {
    return {
      'name': name,
      'valueInteger': int.tryParse(value.primitiveValue ?? ''),
    };
  }
  if (value is fhir.FhirDecimal) {
    return {
      'name': name,
      'valueDecimal': double.tryParse(value.primitiveValue ?? ''),
    };
  }
  if (value is fhir.FhirString) {
    return {'name': name, 'valueString': value.primitiveValue};
  }
  if (value is fhir.FhirDateTime) {
    return {'name': name, 'valueDateTime': value.primitiveValue};
  }
  if (value is fhir.FhirDate) {
    return {'name': name, 'valueDate': value.primitiveValue};
  }
  if (value is fhir.PrimitiveType) {
    return {'name': name, 'valueString': value.primitiveValue};
  }

  // Lists
  if (value is List) {
    final parts = <Map<String, dynamic>>[];
    for (var i = 0; i < value.length; i++) {
      final part = _resultToParameter('item', value[i]);
      if (part != null) parts.add(part);
    }
    return {'name': name, 'part': parts};
  }

  // FHIR Resources
  if (value is fhir.Resource) {
    return {'name': name, 'resource': value.toJson()};
  }

  // Maps (resource JSON or CQL tuples)
  if (value is Map<String, dynamic>) {
    if (value.containsKey('resourceType')) {
      return {'name': name, 'resource': value};
    }
    final parts = <Map<String, dynamic>>[];
    for (final entry in value.entries) {
      final part = _resultToParameter(entry.key, entry.value);
      if (part != null) parts.add(part);
    }
    return {'name': name, 'part': parts};
  }

  return {'name': name, 'valueString': value.toString()};
}

Response _errorResponse(int status, String code, String diagnostics) {
  return Response(
    status,
    body: jsonEncode({
      'resourceType': 'OperationOutcome',
      'issue': [
        {
          'severity': 'error',
          'code': code,
          'diagnostics': diagnostics,
        }
      ],
    }),
    headers: {'Content-Type': 'application/fhir+json'},
  );
}
