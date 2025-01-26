import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Handler for the metadata route
Response metadataHandler(Request request) {
  final capabilityStatement = {
    'resourceType': 'CapabilityStatement',
    'status': 'active',
    'date': DateTime.now().toIso8601String(),
    'fhirVersion': '4.3.0',
    'format': ['json'],
    'rest': [
      {
        'mode': 'server',
        'documentation': 'FHIR RESTful API.',
        'resource': [
          {
            'type': 'Patient',
            'interaction': [
              {'code': 'read'},
              {'code': 'vread'},
              {'code': 'update'},
              {'code': 'delete'},
              {'code': 'create'},
              {'code': 'search-type'},
            ],
          }
        ],
      }
    ],
  };

  return Response.ok(
    jsonEncode(capabilityStatement),
    headers: {'Content-Type': 'application/json'},
  );
}
