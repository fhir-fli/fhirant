/// Static definitions of isSummary=true fields per FHIR R4 resource type.
///
/// These fields are included when `_summary=true` is requested. Fields
/// marked with `isSummary` in the FHIR R4 StructureDefinitions are listed
/// here. `resourceType`, `id`, and `meta` are always included regardless.
///
/// For resource types not listed here, the fallback behavior is to return
/// only resourceType, id, meta, and text (same as _summary=text).
class SummaryFields {
  SummaryFields._();

  /// Maps resource type name to the set of field names that have
  /// `isSummary=true` in the FHIR R4 StructureDefinitions.
  ///
  /// `resourceType`, `id`, and `meta` are implicitly included and need
  /// not be listed here.
  static const Map<String, Set<String>> fields = {
    'Patient': {
      'identifier', 'active', 'name', 'telecom', 'gender', 'birthDate',
      'deceasedBoolean', 'deceasedDateTime', 'address', 'maritalStatus',
      'multipleBirthBoolean', 'multipleBirthInteger', 'photo', 'contact',
      'communication', 'generalPractitioner', 'managingOrganization', 'link',
    },
    'Observation': {
      'identifier', 'status', 'category', 'code', 'subject', 'focus',
      'encounter', 'effectiveDateTime', 'effectivePeriod', 'effectiveTiming',
      'effectiveInstant', 'issued', 'performer',
      'valueQuantity', 'valueCodeableConcept', 'valueString', 'valueBoolean',
      'valueInteger', 'valueRange', 'valueSampledData', 'valueRatio',
      'valueTime', 'valueDateTime', 'valuePeriod',
      'dataAbsentReason', 'interpretation', 'note',
      'hasMember', 'derivedFrom', 'component',
    },
    'Condition': {
      'clinicalStatus', 'verificationStatus', 'category', 'severity', 'code',
      'bodySite', 'subject', 'encounter', 'onsetDateTime', 'onsetAge',
      'onsetPeriod', 'onsetRange', 'onsetString', 'abatementDateTime',
      'abatementAge', 'abatementPeriod', 'abatementRange', 'abatementString',
      'recordedDate', 'recorder', 'asserter',
    },
    'Encounter': {
      'identifier', 'status', 'statusHistory', 'class', 'classHistory',
      'type', 'serviceType', 'priority', 'subject', 'participant',
      'period', 'length', 'reasonCode', 'diagnosis', 'location',
      'serviceProvider',
    },
    'MedicationRequest': {
      'identifier', 'status', 'statusReason', 'intent', 'category',
      'priority', 'doNotPerform', 'reportedBoolean', 'reportedReference',
      'medicationCodeableConcept', 'medicationReference', 'subject',
      'encounter', 'authoredOn', 'requester', 'performer',
      'reasonCode', 'instantiatesCanonical', 'instantiatesUri',
    },
    'Procedure': {
      'identifier', 'instantiatesCanonical', 'instantiatesUri', 'status',
      'statusReason', 'category', 'code', 'subject', 'encounter',
      'performedDateTime', 'performedPeriod', 'performedString',
      'performedAge', 'performedRange',
    },
    'AllergyIntolerance': {
      'identifier', 'clinicalStatus', 'verificationStatus', 'type',
      'category', 'criticality', 'code', 'patient', 'encounter',
      'onsetDateTime', 'onsetAge', 'onsetPeriod', 'onsetRange',
      'onsetString', 'recordedDate', 'recorder', 'asserter',
      'lastOccurrence',
    },
    'DiagnosticReport': {
      'identifier', 'status', 'category', 'code', 'subject', 'encounter',
      'effectiveDateTime', 'effectivePeriod', 'issued', 'performer',
      'resultsInterpreter', 'result', 'conclusion', 'conclusionCode',
    },
    'Immunization': {
      'identifier', 'status', 'vaccineCode', 'patient', 'encounter',
      'occurrenceDateTime', 'occurrenceString', 'primarySource',
      'location', 'lotNumber', 'expirationDate', 'site', 'route',
      'doseQuantity', 'performer', 'isSubpotent',
    },
    'CarePlan': {
      'identifier', 'instantiatesCanonical', 'instantiatesUri', 'status',
      'intent', 'category', 'title', 'description', 'subject', 'encounter',
      'period', 'created', 'author', 'contributor', 'careTeam',
      'activity',
    },
    'CareTeam': {
      'identifier', 'status', 'category', 'name', 'subject', 'encounter',
      'period', 'participant', 'managingOrganization',
    },
    'Goal': {
      'identifier', 'lifecycleStatus', 'achievementStatus', 'category',
      'priority', 'description', 'subject',
      'startDate', 'startCodeableConcept',
      'target',
    },
    'MedicationStatement': {
      'identifier', 'status', 'statusReason', 'category',
      'medicationCodeableConcept', 'medicationReference', 'subject',
      'context', 'effectiveDateTime', 'effectivePeriod', 'dateAsserted',
      'informationSource', 'derivedFrom', 'reasonCode',
    },
    'ServiceRequest': {
      'identifier', 'instantiatesCanonical', 'instantiatesUri', 'status',
      'intent', 'category', 'priority', 'doNotPerform', 'code',
      'orderDetail', 'subject', 'encounter',
      'occurrenceDateTime', 'occurrencePeriod', 'occurrenceTiming',
      'authoredOn', 'requester', 'performer', 'locationCode',
    },
    'DocumentReference': {
      'masterIdentifier', 'identifier', 'status', 'docStatus', 'type',
      'category', 'subject', 'date', 'author', 'authenticator',
      'custodian', 'relatesTo', 'description', 'securityLabel', 'content',
    },
    'Organization': {
      'identifier', 'active', 'type', 'name', 'alias', 'telecom',
      'address', 'partOf', 'contact', 'endpoint',
    },
    'Practitioner': {
      'identifier', 'active', 'name', 'telecom', 'address', 'gender',
      'birthDate', 'qualification', 'communication',
    },
    'PractitionerRole': {
      'identifier', 'active', 'period', 'practitioner', 'organization',
      'code', 'specialty', 'location', 'healthcareService', 'telecom',
      'endpoint',
    },
    'Location': {
      'identifier', 'status', 'operationalStatus', 'name', 'alias',
      'description', 'mode', 'type', 'telecom', 'address',
      'physicalType', 'position', 'managingOrganization', 'partOf',
      'endpoint',
    },
    'Device': {
      'identifier', 'udiCarrier', 'status', 'distinctIdentifier',
      'manufacturer', 'manufactureDate', 'expirationDate', 'lotNumber',
      'serialNumber', 'deviceName', 'modelNumber', 'type', 'patient',
      'owner', 'url',
    },
    'Group': {
      'identifier', 'active', 'type', 'actual', 'code', 'name', 'quantity',
      'managingEntity', 'characteristic',
    },
    'Composition': {
      'identifier', 'status', 'type', 'category', 'subject', 'encounter',
      'date', 'author', 'title', 'confidentiality', 'attester',
      'custodian', 'relatesTo', 'event', 'section',
    },
    'Bundle': {
      'identifier', 'type', 'timestamp', 'total', 'link',
    },
    'Medication': {
      'identifier', 'code', 'status', 'manufacturer', 'form', 'amount',
      'ingredient', 'batch',
    },
  };

  /// Returns the set of summary fields for a given resource type,
  /// or null if the resource type is not in the map.
  static Set<String>? forType(String resourceType) => fields[resourceType];
}
