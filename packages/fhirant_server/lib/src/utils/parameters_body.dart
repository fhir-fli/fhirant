import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:shelf/shelf.dart';

/// A FHIR Parameters resource as a map: each `parameter.name` to its
/// `value[x]` (whichever is present) or its `resource`. Before 2026-09-22
/// this was written three times (terminology, CQL, backup), each reading
/// a different subset of the value types.
Map<String, dynamic> parametersToMap(Map<String, dynamic> parameters) {
  final result = <String, dynamic>{};
  final list = parameters['parameter'];
  if (list is! List) return result;
  for (final p in list) {
    if (p is! Map<String, dynamic>) continue;
    final name = p['name'];
    if (name is! String) continue;
    for (final key in p.keys) {
      if (key.startsWith('value')) {
        result[name] = p[key];
        break;
      }
    }
    if (p.containsKey('resource')) result[name] = p['resource'];
  }
  return result;
}

/// An operation's input parameters, however the client sent them: the
/// query string on a GET; on a POST a Parameters resource, any other JSON
/// object as it is, or (under a form content type) a form-encoded body.
/// An empty body is no parameters. A body that is none of those is the
/// client's 400, returned ready to send as [refusal]; every reader used
/// to fall back to reading it as a form, so `{this is not json` became a
/// parameter named `{this is not json`.
Future<({Map<String, dynamic> params, Response? refusal})>
    readOperationParameters(Request request) async {
  if (request.method == 'GET') {
    return (
      params: Map<String, dynamic>.from(request.url.queryParameters),
      refusal: null,
    );
  }
  final body = await request.readAsString();
  if (body.isEmpty) return (params: <String, dynamic>{}, refusal: null);
  final contentType = request.headers['content-type'] ?? '';
  if (contentType.contains('application/x-www-form-urlencoded')) {
    return (
      params: Map<String, dynamic>.from(Uri.splitQueryString(body)),
      refusal: null,
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    return (
      params: <String, dynamic>{},
      refusal: outcome(
        400,
        fhir.IssueType.invalid,
        'Request body is not JSON: ${e.message}',
      ),
    );
  }
  if (decoded is! Map<String, dynamic>) {
    return (
      params: <String, dynamic>{},
      refusal: outcome(
        400,
        fhir.IssueType.invalid,
        'Request body must be a JSON object',
      ),
    );
  }
  return (
    params: decoded['resourceType'] == 'Parameters'
        ? parametersToMap(decoded)
        : decoded,
    refusal: null,
  );
}
