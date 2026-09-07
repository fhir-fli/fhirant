import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant_db/fhirant_db.dart' show searchParameterTypes;
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/search_param_definitions.dart';
import 'package:shelf/shelf.dart';

/// The search parameters the store defines for [type]: its own, then the
/// ones published on Resource and DomainResource, which every type takes.
/// Read from `searchParameterTypes` (generated from search-parameters.json),
/// so the CapabilityStatement says what the search actually accepts. This
/// used to be a hand-typed list for a few types.
List<CapabilityStatementSearchParam> _searchParamsFor(String type) {
  final own = searchParameterTypes[type] ?? const {};
  final common = {
    ...?searchParameterTypes['Resource'],
    ...?searchParameterTypes['DomainResource'],
  };
  final names = <String>{...own.keys, ...common.keys}.toList()..sort();
  return [
    for (final name in names)
      CapabilityStatementSearchParam(
        name: name.toFhirString,
        type: SearchParamType((own[name] ?? common[name]!).type),
      ),
  ];
}

/// `[type]:[parameter]` for every reference parameter of [type]: what
/// `_include` accepts here (search.html 3.1.1.5.4, a join by search
/// parameter).
List<FhirString> _searchIncludesFor(String type) {
  final own = searchParameterTypes[type] ?? const {};
  final names = own.entries
      .where((e) => e.value.type == 'reference')
      .map((e) => e.key)
      .toList()
    ..sort();
  return [for (final name in names) '$type:$name'.toFhirString];
}

/// `[other type]:[parameter]` for every reference parameter, on any type,
/// whose declared targets (SearchParameter.target) include [type]: what
/// `_revinclude` can join to a [type] match. A reference parameter that
/// declares no target is left out, since nothing says it can point here.
Map<String, List<FhirString>> _searchRevIncludes() {
  final byTarget = <String, List<String>>{};
  for (final entry in searchParameterTypes.entries) {
    final source = entry.key;
    if (source == 'Resource' || source == 'DomainResource') continue;
    for (final param in entry.value.entries) {
      if (param.value.type != 'reference') continue;
      for (final target in param.value.targets) {
        (byTarget[target] ??= <String>[]).add('$source:${param.key}');
      }
    }
  }
  return {
    for (final e in byTarget.entries)
      e.key: (e.value..sort()).map((s) => s.toFhirString).toList(),
  };
}

/// Handler for the metadata route — returns a CapabilityStatement.
Response metadataHandler(Request request) {
  try {
    FhirantLogging().logInfo(
      'Fetching metadata request from ${request.requestedUri}',
    );

    final host = request.requestedUri.hasPort
        ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
        : '${request.requestedUri.scheme}://${request.requestedUri.host}';

    final revIncludes = _searchRevIncludes();
    final capabilityStatement = CapabilityStatement(
      status: PublicationStatus.active,
      date: DateTime.now().toFhirDateTime,
      kind: CapabilityStatementKind.instance,
      fhirVersion: FHIRVersion.value430,
      format: [FhirCode('json')],
      patchFormat: [FhirCode('application/json-patch+json')],
      software: CapabilityStatementSoftware(
        name: 'FHIRant'.toFhirString,
        version: '1.0.0'.toFhirString,
      ),
      implementation: CapabilityStatementImplementation(
        description: 'FHIRant FHIR R4B Server'.toFhirString,
      ),
      rest: [
        CapabilityStatementRest(
          // Without this a client has no way to find the websocket a
          // Subscription binds over. The extension is HL7's own:
          // capabilitystatement-websocket, context CapabilityStatement.rest,
          // value uri, "Where the server provides its web socket end-point"
          // (read from the published StructureDefinition, not from memory).
          extension_: [
            FhirExtension(
              url: FhirString(
                'http://hl7.org/fhir/StructureDefinition/'
                'capabilitystatement-websocket',
              ),
              valueX: FhirUri(
                'ws://${request.requestedUri.authority}/ws',
              ),
            ),
          ],
          mode: RestfulCapabilityMode.server,
          documentation: 'FHIR RESTful API with SMART on FHIR authentication.'
              .toFhirMarkdown,
          security: CapabilityStatementSecurity(
            cors: FhirBoolean(true),
            service: [
              CodeableConcept(
                coding: [
                  Coding(
                    system: FhirUri(
                      'http://terminology.hl7.org/CodeSystem/restful-security-service',
                    ),
                    code: FhirCode('SMART-on-FHIR'),
                    display: 'SMART-on-FHIR'.toFhirString,
                  ),
                ],
                text: 'SMART on FHIR with JWT Bearer Token Authentication'
                    .toFhirString,
              ),
            ],
            description:
                'Server uses SMART on FHIR scopes with JWT Bearer tokens. '
                        'See /.well-known/smart-configuration for details.'
                    .toFhirMarkdown,
            extension_: [
              FhirExtension(
                url:
                    'http://fhir-registry.smarthealthit.org/StructureDefinition/oauth-uris'
                        .toFhirString,
                extension_: [
                  FhirExtension(
                    url: 'authorize'.toFhirString,
                    valueUri: FhirUri('$host/auth/authorize'),
                  ),
                  FhirExtension(
                    url: 'token'.toFhirString,
                    valueUri: FhirUri('$host/auth/token'),
                  ),
                  FhirExtension(
                    url: 'register'.toFhirString,
                    valueUri: FhirUri('$host/auth/register'),
                  ),
                ],
              ),
            ],
          ),
          interaction: [
            const CapabilityStatementInteraction(
              code: TypeRestfulInteraction.transaction,
            ),
            const CapabilityStatementInteraction(
              code: TypeRestfulInteraction.batch,
            ),
            const CapabilityStatementInteraction(
              code: TypeRestfulInteraction.historySystem,
            ),
            const CapabilityStatementInteraction(
              code: TypeRestfulInteraction.searchSystem,
            ),
          ],
          operation: [
            CapabilityStatementOperation(
              name: 'validate'.toFhirString,
              definition: FhirCanonical(
                'http://hl7.org/fhir/OperationDefinition/Resource-validate',
              ),
            ),
            CapabilityStatementOperation(
              name: 'fhirpath'.toFhirString,
              definition: FhirCanonical(
                'http://hl7.org/fhir/OperationDefinition/Resource-fhirpath',
              ),
            ),
            CapabilityStatementOperation(
              name: 'transform'.toFhirString,
              definition: FhirCanonical(
                'http://hl7.org/fhir/OperationDefinition/StructureMap-transform',
              ),
            ),
            CapabilityStatementOperation(
              name: 'export'.toFhirString,
              definition: FhirCanonical(
                'http://hl7.org/fhir/uv/bulkdata/OperationDefinition/export',
              ),
            ),
          ],
          compartment: [
            FhirCanonical(
              'http://hl7.org/fhir/CompartmentDefinition/patient',
            ),
            FhirCanonical(
              'http://hl7.org/fhir/CompartmentDefinition/encounter',
            ),
            FhirCanonical(
              'http://hl7.org/fhir/CompartmentDefinition/practitioner',
            ),
            FhirCanonical(
              'http://hl7.org/fhir/CompartmentDefinition/relatedPerson',
            ),
            FhirCanonical(
              'http://hl7.org/fhir/CompartmentDefinition/device',
            ),
          ],
          resource: R4ResourceType.typesAsStrings.map((type) {
            final allParams = _searchParamsFor(type);

            // Per-resource operations
            final operations = <CapabilityStatementOperation>[
              // $meta on all resources
              CapabilityStatementOperation(
                name: 'meta'.toFhirString,
                definition: FhirCanonical(
                  'http://hl7.org/fhir/OperationDefinition/Resource-meta',
                ),
              ),
              CapabilityStatementOperation(
                name: 'meta-add'.toFhirString,
                definition: FhirCanonical(
                  'http://hl7.org/fhir/OperationDefinition/Resource-meta-add',
                ),
              ),
              CapabilityStatementOperation(
                name: 'meta-delete'.toFhirString,
                definition: FhirCanonical(
                  'http://hl7.org/fhir/OperationDefinition/Resource-meta-delete',
                ),
              ),
              CapabilityStatementOperation(
                name: 'validate'.toFhirString,
                definition: FhirCanonical(
                  'http://hl7.org/fhir/OperationDefinition/Resource-validate',
                ),
              ),
              // $everything on compartment types
              if (SearchParamDefinitions.everythingTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'everything'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/$type-everything',
                  ),
                ),
              // $export on Patient and Group
              if (SearchParamDefinitions.exportTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'export'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/uv/bulkdata/OperationDefinition/export',
                  ),
                ),
              // $document on Composition
              if (SearchParamDefinitions.documentTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'document'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/Composition-document',
                  ),
                ),
              // $validate-code on CodeSystem/ValueSet
              if (SearchParamDefinitions.validateCodeTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'validate-code'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/$type-validate-code',
                  ),
                ),
              // $lookup on CodeSystem
              if (SearchParamDefinitions.lookupTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'lookup'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/CodeSystem-lookup',
                  ),
                ),
              // $expand on ValueSet
              if (SearchParamDefinitions.expandTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'expand'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/ValueSet-expand',
                  ),
                ),
              // $subsumes on CodeSystem
              if (SearchParamDefinitions.subsumesTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'subsumes'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/CodeSystem-subsumes',
                  ),
                ),
              // $translate on ConceptMap
              if (SearchParamDefinitions.translateTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'translate'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/ConceptMap-translate',
                  ),
                ),
              // $preferred-id on NamingSystem
              if (SearchParamDefinitions.preferredIdTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'preferred-id'.toFhirString,
                  definition: FhirCanonical(
                    'http://hl7.org/fhir/OperationDefinition/NamingSystem-preferred-id',
                  ),
                ),
            ];

            final includeList = _searchIncludesFor(type);
            final revIncludeList = revIncludes[type];

            return CapabilityStatementResource(
              type: FhirCode(type),
              interaction: const [
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.read,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.vread,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.update,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.patch,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.delete,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.create,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.searchType,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.historyInstance,
                ),
                CapabilityStatementInteraction(
                  code: TypeRestfulInteraction.historyType,
                ),
              ],
              versioning: ResourceVersionPolicy.versioned,
              readHistory: FhirBoolean(true),
              updateCreate: FhirBoolean(true),
              conditionalCreate: FhirBoolean(true),
              conditionalRead: ConditionalReadStatus.fullSupport,
              conditionalUpdate: FhirBoolean(true),
              conditionalDelete: ConditionalDeleteStatus.multiple,
              searchParam: allParams,
              operation: operations,
              searchInclude: includeList.isEmpty ? null : includeList,
              searchRevInclude: revIncludeList,
            );
          }).toList(),
        ),
      ],
    );

    FhirantLogging().logInfo('Metadata response generated successfully');
    return Response.ok(
      capabilityStatement.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error fetching metadata', e, stackTrace);
    return Response(
      500,
      body: OperationOutcome(
        issue: [
          OperationOutcomeIssue(
            severity: IssueSeverity.error,
            code: IssueType.exception,
            diagnostics: 'Failed to generate metadata'.toFhirString,
          ),
        ],
      ).toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
