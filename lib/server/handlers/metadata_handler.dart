import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final Logger _logger = Logger('MetadataHandler');

/// Handler for the metadata route
Response metadataHandler(Request request) {
  try {
    _logger.info('Fetching metadata request from ${request.requestedUri}');

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
          'resource':
              R4ResourceType.typesAsStrings
                  .map(
                    (type) => {
                      'type': type,
                      'interaction': [
                        {'code': 'read'},
                        {'code': 'vread'},
                        {'code': 'update'},
                        // {'code': 'delete'},
                        {'code': 'create'},
                        // {'code': 'search-type'},
                      ],
                    },
                  )
                  .toList(),
        },
      ],
    };

    _logger.info('Metadata response generated successfully');
    return Response.ok(
      jsonEncode(capabilityStatement),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    _logger.severe('Error fetching metadata', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({'error': 'Failed to fetch metadata'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
