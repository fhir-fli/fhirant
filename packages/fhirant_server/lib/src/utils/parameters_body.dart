import 'dart:convert';

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
/// object as it is, or a form-encoded body. An empty body is no
/// parameters.
Future<Map<String, dynamic>> readOperationParameters(Request request) async {
  if (request.method == 'GET') {
    return Map<String, dynamic>.from(request.url.queryParameters);
  }
  final body = await request.readAsString();
  if (body.isEmpty) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return Map<String, dynamic>.from(Uri.splitQueryString(body));
  }
  if (decoded is! Map<String, dynamic>) return {};
  return decoded['resourceType'] == 'Parameters'
      ? parametersToMap(decoded)
      : decoded;
}
