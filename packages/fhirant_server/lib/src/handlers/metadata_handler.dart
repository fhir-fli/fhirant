import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

import '../utils/search_param_definitions.dart';

/// Handler for the metadata route — returns a CapabilityStatement.
Response metadataHandler(Request request) {
  try {
    FhirantLogging().logInfo(
      'Fetching metadata request from ${request.requestedUri}',
    );

    final host = request.requestedUri.hasPort
        ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
        : '${request.requestedUri.scheme}://${request.requestedUri.host}';

    final capabilityStatement = CapabilityStatement(
      status: PublicationStatus.active,
      date: DateTime.now().toFhirDateTime,
      kind: CapabilityStatementKind.instance,
      fhirVersion: FHIRVersion.value401,
      format: [FhirCode('json')],
      patchFormat: [FhirCode('application/json-patch+json')],
      software: CapabilityStatementSoftware(
        name: 'FHIRant'.toFhirString,
        version: '1.0.0'.toFhirString,
      ),
      implementation: CapabilityStatementImplementation(
        description: 'FHIRant FHIR R4 Server'.toFhirString,
      ),
      rest: [
        CapabilityStatementRest(
          mode: RestfulCapabilityMode.server,
          documentation:
              'FHIR RESTful API with SMART on FHIR authentication.'
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
                    url: 'token'.toFhirString,
                    valueUri: FhirUri('$host/auth/login'),
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
            final specificParams =
                SearchParamDefinitions.resourceSpecific[type];
            final allParams = [
              ...SearchParamDefinitions.commonSearchParams,
              if (specificParams != null) ...specificParams,
            ];

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
            ];

            final includeList =
                SearchParamDefinitions.searchInclude[type];
            final revIncludeList =
                SearchParamDefinitions.searchRevInclude[type];

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
              conditionalDelete: ConditionalDeleteStatus.single,
              searchParam: allParams,
              operation: operations,
              searchInclude: includeList
                  ?.map((s) => s.toFhirString)
                  .toList(),
              searchRevInclude: revIncludeList
                  ?.map((s) => s.toFhirString)
                  .toList(),
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
