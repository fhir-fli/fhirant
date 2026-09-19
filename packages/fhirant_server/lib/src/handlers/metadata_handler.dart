import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant_db/fhirant_db.dart'
    show
        CustomSearchParameter,
        CustomSearchParameters,
        FhirAntDb,
        searchParameterTypes;
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/search_param_definitions.dart';
import 'package:shelf/shelf.dart';

/// The search parameters the store defines for [type]: its own, then the
/// ones published on Resource and DomainResource, which every type takes.
/// Read from `searchParameterTypes` (generated from search-parameters.json),
/// so the CapabilityStatement says what the search actually accepts. This
/// used to be a hand-typed list for a few types.
List<CapabilityStatementSearchParam> _searchParamsFor(
  String type,
  CustomSearchParameters? custom,
) {
  final own = searchParameterTypes[type] ?? const {};
  final common = {
    ...?searchParameterTypes['Resource'],
    ...?searchParameterTypes['DomainResource'],
  };
  // Uploaded definitions that apply to this type, after the
  // specification's (fhir_db refuses an upload that redefines one of
  // those, so the names do not collide).
  final uploaded = {
    for (final p in custom?.forType(type) ?? const <CustomSearchParameter>[])
      p.code: p,
  };
  final names = <String>{...own.keys, ...common.keys, ...uploaded.keys}.toList()
    ..sort();
  return [
    for (final name in names)
      () {
        final url = uploaded[name]?.url;
        return CapabilityStatementSearchParam(
          name: name.toFhirString,
          definition: url == null ? null : FhirCanonical(url),
          type: SearchParamType(
            (own[name] ?? common[name])?.type ?? uploaded[name]!.type,
          ),
        );
      }(),
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
Future<Response> metadataHandler(
  Request request, {
  bool corsEnabled = false,
  FhirAntDb? db,
}) async {
  // The uploaded SearchParameters, so the statement says what the search
  // accepts (Azure: "The new search parameter appears in the capability
  // statement of the FHIR service after you POST the search parameter to
  // the database and reindex your database").
  final custom = db == null ? null : await db.customSearchParameters;
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
              // The scheme follows the request: `wss` under TLS. It used to
              // say `ws` under https too (REVIEW-2026-09-08 row 31).
              valueX: FhirUri(
                '${request.requestedUri.scheme == 'https' ? 'wss' : 'ws'}'
                '://${request.requestedUri.authority}/ws',
              ),
            ),
          ],
          mode: RestfulCapabilityMode.server,
          documentation: 'FHIR RESTful API with SMART on FHIR authentication.'
              .toFhirMarkdown,
          security: CapabilityStatementSecurity(
            // What the server is configured to do, not a constant: CORS is
            // off unless an origin is configured (REVIEW-2026-09-08 row 31).
            cors: FhirBoolean(corsEnabled),
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
                  // No `register`: in oauth-uris that is the dynamic CLIENT
                  // registration endpoint, and /auth/register creates user
                  // accounts. Removed from .well-known/smart-configuration
                  // on 2026-09-08 (row 20) for that reason; it stayed here
                  // (REVIEW-2026-09-17 C4).
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
              // This server's own operation: R4B publishes no
              // OperationDefinition/Resource-fhirpath (profiles-resources.json
              // read 2026-09-08 lists Resource-convert/graph/graphql/meta/
              // meta-add/meta-delete/validate), and the CapabilityStatement
              // used to cite that non-existent canonical (row 31).
              definition: FhirCanonical(
                // Published by this server: assets/fhir_spec/
                // fhirant-operations.ndjson, loaded with the specification
                // (REVIEW-2026-09-17 C3; the old canonical was held nowhere).
                'http://fhirfli.dev/fhirant/OperationDefinition/fhirpath',
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
            final allParams = _searchParamsFor(type, custom);

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
              // $everything on every compartment type. R4B publishes an
              // OperationDefinition for Patient and Encounter (and Group,
              // MedicinalProductDefinition, which are not compartments);
              // for Practitioner, RelatedPerson and Device this server
              // cites its own, shipped in assets/fhir_spec/
              // fhirant-operations.ndjson and loaded with the specification.
              // It used to cite `$type-everything` under hl7.org for all
              // five, three of which do not exist (REVIEW-2026-09-17 C3).
              if (SearchParamDefinitions.everythingTypes.contains(type))
                CapabilityStatementOperation(
                  name: 'everything'.toFhirString,
                  definition: FhirCanonical(
                    const {'Patient', 'Encounter'}.contains(type)
                        ? 'http://hl7.org/fhir/OperationDefinition/'
                            '$type-everything'
                        : 'http://fhirfli.dev/fhirant/OperationDefinition/'
                            '$type-everything',
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
