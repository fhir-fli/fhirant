import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for the metadata route
Response metadataHandler(Request request) {
  try {
    FhirantLogging().logInfo(
      'Fetching metadata request from ${request.requestedUri}',
    );

        // Common search parameters for all resources
    final commonSearchParams = [
      {
        'name': '_id',
        'type': 'token',
        'documentation': 'Logical id of this artifact',
      },
      {
        'name': '_lastUpdated',
        'type': 'date',
        'documentation': 'When the resource version last changed. Supports modifiers: eq, ne, gt, lt, ge, le, sa, eb, ap',
      },
      {
        'name': '_tag',
        'type': 'token',
        'documentation': 'Tags applied to this resource. Format: system|code or just code',
      },
      {
        'name': '_profile',
        'type': 'uri',
        'documentation': 'Profiles this resource claims to conform to',
      },
      {
        'name': '_security',
        'type': 'token',
        'documentation': 'Security Labels applied to this resource. Format: system|code or just code',
      },
      {
        'name': '_source',
        'type': 'uri',
        'documentation': 'Identifies where the resource comes from',
      },
      {
        'name': '_sort',
        'type': 'special',
        'documentation': 'Specify the order of results. Format: field or -field for descending',
      },
      {
        'name': '_include',
        'type': 'special',
        'documentation':
            'Include resources referenced by the search results. '
                'Format: ResourceType:searchParam[:targetType]. '
                'Use * as searchParam for wildcard.',
      },
      {
        'name': '_include:iterate',
        'type': 'special',
        'documentation':
            'Iteratively include resources referenced by included resources. '
                'Format: ResourceType:searchParam[:targetType].',
      },
      {
        'name': '_revinclude',
        'type': 'special',
        'documentation':
            'Include resources that reference the search results. '
                'Format: ResourceType:searchParam.',
      },
      {
        'name': '_revinclude:iterate',
        'type': 'special',
        'documentation':
            'Iteratively include resources that reference included resources. '
                'Format: ResourceType:searchParam.',
      },
    ];

    // Resource-specific search parameters (simplified - can be expanded)
    //
    // Advanced Search Features Supported:
    // - Reference Chaining: Use dot notation (e.g., organization.name=Hospital)
    // - Composite Parameters: Use $ separator (e.g., code-value-quantity=8480-6\$gt100)
    // - OR Logic: Use comma-separated values (e.g., name=Smith,Jones)
    // - Sorting: Use _sort parameter (e.g., _sort=name,-date)
    // - Includes: Use _include and _revinclude for related resources
    Map<String, List<Map<String, dynamic>>> resourceSearchParams = {
      'Patient': [
        {'name': 'name', 'type': 'string', 'documentation': 'A portion of either family or given name'},
        {'name': 'family', 'type': 'string', 'documentation': 'A portion of the family name'},
        {'name': 'given', 'type': 'string', 'documentation': 'A portion of the given name'},
        {'name': 'identifier', 'type': 'token', 'documentation': 'A patient identifier'},
        {'name': 'gender', 'type': 'token', 'documentation': 'Gender of the patient'},
        {'name': 'birthdate', 'type': 'date', 'documentation': 'The patient date date of birth'},
        {'name': 'address', 'type': 'string', 'documentation': 'A server defined search that may match any of the string fields in the Address'},
        {'name': 'address-city', 'type': 'string', 'documentation': 'A city specified in an address'},
        {'name': 'address-state', 'type': 'string', 'documentation': 'A state specified in an address'},
        {'name': 'address-postalcode', 'type': 'string', 'documentation': 'A postal code specified in an address'},
        {'name': 'address-country', 'type': 'string', 'documentation': 'A country specified in an address'},
              {'name': 'organization', 'type': 'reference', 'documentation': 'Organization that is the custodian of the patient record. Supports chaining (e.g., organization.name=Hospital)'},
        ],
      'Observation': [
        {'name': 'code', 'type': 'token', 'documentation': 'The code of the observation type'},
        {'name': 'date', 'type': 'date', 'documentation': 'Obtained date/time'},
        {'name': 'patient', 'type': 'reference', 'documentation': 'The subject that the observation is about'},
        {'name': 'status', 'type': 'token', 'documentation': 'The status of the observation'},
        {'name': 'value-quantity', 'type': 'quantity', 'documentation': 'The value of the observation'},
      ],
      'Condition': [
        {'name': 'code', 'type': 'token', 'documentation': 'Code for the condition'},
        {'name': 'patient', 'type': 'reference', 'documentation': 'Who has the condition'},
        {'name': 'clinical-status', 'type': 'token', 'documentation': 'The clinical status of the condition'},
      ],
    };

    final capabilityStatement = {
      'resourceType': 'CapabilityStatement',
      'status': 'active',
      'date': DateTime.now().toIso8601String(),
      'kind': 'instance',
      'fhirVersion': '4.0.1',
      'format': ['json'],
      'patchFormat': ['application/json-patch+json'],
      'software': {
        'name': 'FHIRant',
        'version': '1.0.0',
      },
      'implementation': {
        'description': 'FHIRant FHIR R4 Server',
      },
      'rest': [
        {
          'mode': 'server',
          'documentation': 'FHIR RESTful API.',
          'security': {
            'cors': true,
            'service': [
              {
                'coding': [
                  {
                    'system':
                        'http://terminology.hl7.org/CodeSystem/restful-security-service',
                    'code': 'SMART-on-FHIR',
                    'display': 'SMART-on-FHIR',
                  },
                ],
                'text': 'JWT Bearer Token Authentication',
              },
            ],
            'description':
                'Server uses JWT Bearer tokens for authentication. '
                    'Obtain a token via POST /auth/login.',
          },
          'interaction': [
            {'code': 'transaction'},
            {'code': 'batch'},
            {'code': 'history-system'},
          ],
          'operation': [
            {
              'name': 'validate',
              'definition':
                  'http://hl7.org/fhir/OperationDefinition/Resource-validate',
              'documentation': 'Validate a resource',
            },
            {
              'name': 'fhirpath',
              'definition':
                  'http://hl7.org/fhir/OperationDefinition/Resource-fhirpath',
              'documentation':
                  'Evaluate a FHIRPath expression against a resource',
            },
            {
              'name': 'transform',
              'definition':
                  'http://hl7.org/fhir/OperationDefinition/StructureMap-transform',
              'documentation':
                  'Transform a resource using FHIR Mapping Language',
            },
            {
              'name': 'everything',
              'definition':
                  'http://hl7.org/fhir/OperationDefinition/Patient-everything',
              'documentation':
                  'Fetch all resources in a Patient or Encounter compartment. '
                      'Supports _type, _since, _count, _offset parameters.',
            },
            {
              'name': 'export',
              'definition':
                  'http://hl7.org/fhir/uv/bulkdata/OperationDefinition/export',
              'documentation':
                  'Bulk Data Export (async). System-level: GET /\$export, '
                      'Patient-level: GET /Patient/\$export, '
                      'Group-level: GET /Group/<id>/\$export. '
                      'Supports _type, _since, _outputFormat parameters. '
                      'Returns 202 Accepted with Content-Location for status polling.',
            },
          ],
          'compartment': [
            'http://hl7.org/fhir/CompartmentDefinition/patient',
            'http://hl7.org/fhir/CompartmentDefinition/encounter',
          ],
          'resource': R4ResourceType.typesAsStrings
              .map(
                (type) {
                  final resourceParams = [
                    ...commonSearchParams,
                    ...(resourceSearchParams[type] ?? []),
                  ];

                  return {
                    'type': type,
                    'interaction': [
                      {'code': 'read'},
                      {'code': 'vread'},
                      {'code': 'update'},
                      {'code': 'patch'},
                      {'code': 'delete'},
                      {'code': 'create'},
                      {'code': 'search-type'},
                      {'code': 'history-instance'},
                      {'code': 'history-type'},
                    ],
                    'versioning': 'versioned',
                    'readHistory': true,
                    'updateCreate': true,
                    'conditionalCreate': true,
                    'conditionalRead': 'modified-since',
                    'conditionalUpdate': true,
                    'conditionalDelete': 'single',
                    if (resourceParams.isNotEmpty)
                      'searchParam': resourceParams,
                  };
                },
              )
              .toList(),
        },
      ],
    };

    FhirantLogging().logInfo('Metadata response generated successfully');
    return Response.ok(
      jsonEncode(capabilityStatement),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error fetching metadata', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({'error': 'Failed to fetch metadata'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
