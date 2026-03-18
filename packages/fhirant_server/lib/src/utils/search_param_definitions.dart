import 'package:fhir_r4/fhir_r4.dart';

/// Static search parameter definitions for the CapabilityStatement.
///
/// Provides common and resource-specific search parameters, plus
/// _include/_revinclude declarations for clinically important types.
class SearchParamDefinitions {
  SearchParamDefinitions._();

  /// Common search parameters that apply to ALL resource types.
  static final List<CapabilityStatementSearchParam> commonSearchParams = [
    CapabilityStatementSearchParam(
      name: '_id'.toFhirString,
      type: SearchParamType.token,
    ),
    CapabilityStatementSearchParam(
      name: '_lastUpdated'.toFhirString,
      type: SearchParamType.date,
    ),
    CapabilityStatementSearchParam(
      name: '_tag'.toFhirString,
      type: SearchParamType.token,
    ),
    CapabilityStatementSearchParam(
      name: '_profile'.toFhirString,
      type: SearchParamType.uri,
    ),
    CapabilityStatementSearchParam(
      name: '_security'.toFhirString,
      type: SearchParamType.token,
    ),
    CapabilityStatementSearchParam(
      name: '_source'.toFhirString,
      type: SearchParamType.uri,
    ),
  ];

  static CapabilityStatementSearchParam _sp(String name, SearchParamType type) {
    return CapabilityStatementSearchParam(
      name: name.toFhirString,
      type: type,
    );
  }

  /// Resource-specific search parameters for clinically important types.
  static final Map<String, List<CapabilityStatementSearchParam>>
      resourceSpecific = {
    'Patient': [
      _sp('name', SearchParamType.string),
      _sp('family', SearchParamType.string),
      _sp('given', SearchParamType.string),
      _sp('identifier', SearchParamType.token),
      _sp('gender', SearchParamType.token),
      _sp('birthdate', SearchParamType.date),
      _sp('address', SearchParamType.string),
      _sp('address-city', SearchParamType.string),
      _sp('address-state', SearchParamType.string),
      _sp('address-postalcode', SearchParamType.string),
      _sp('address-country', SearchParamType.string),
      _sp('telecom', SearchParamType.token),
      _sp('email', SearchParamType.token),
      _sp('phone', SearchParamType.token),
      _sp('organization', SearchParamType.reference),
      _sp('general-practitioner', SearchParamType.reference),
      _sp('active', SearchParamType.token),
      _sp('deceased', SearchParamType.token),
      _sp('link', SearchParamType.reference),
    ],
    'Observation': [
      _sp('code', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('value-quantity', SearchParamType.quantity),
      _sp('value-concept', SearchParamType.token),
      _sp('encounter', SearchParamType.reference),
      _sp('performer', SearchParamType.reference),
    ],
    'Condition': [
      _sp('code', SearchParamType.token),
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('clinical-status', SearchParamType.token),
      _sp('verification-status', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('severity', SearchParamType.token),
      _sp('onset-date', SearchParamType.date),
      _sp('encounter', SearchParamType.reference),
      _sp('asserter', SearchParamType.reference),
    ],
    'Encounter': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('class', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('participant', SearchParamType.reference),
      _sp('location', SearchParamType.reference),
      _sp('service-provider', SearchParamType.reference),
      _sp('reason-code', SearchParamType.token),
    ],
    'MedicationRequest': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('intent', SearchParamType.token),
      _sp('medication', SearchParamType.reference),
      _sp('code', SearchParamType.token),
      _sp('requester', SearchParamType.reference),
      _sp('encounter', SearchParamType.reference),
      _sp('authoredon', SearchParamType.date),
    ],
    'Procedure': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('code', SearchParamType.token),
      _sp('status', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('encounter', SearchParamType.reference),
      _sp('performer', SearchParamType.reference),
    ],
    'AllergyIntolerance': [
      _sp('patient', SearchParamType.reference),
      _sp('code', SearchParamType.token),
      _sp('clinical-status', SearchParamType.token),
      _sp('verification-status', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('criticality', SearchParamType.token),
      _sp('date', SearchParamType.date),
    ],
    'DiagnosticReport': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('code', SearchParamType.token),
      _sp('status', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('encounter', SearchParamType.reference),
      _sp('result', SearchParamType.reference),
      _sp('performer', SearchParamType.reference),
    ],
    'Immunization': [
      _sp('patient', SearchParamType.reference),
      _sp('vaccine-code', SearchParamType.token),
      _sp('status', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('location', SearchParamType.reference),
      _sp('performer', SearchParamType.reference),
    ],
    'CarePlan': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('encounter', SearchParamType.reference),
    ],
    'CareTeam': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('participant', SearchParamType.reference),
      _sp('encounter', SearchParamType.reference),
    ],
    'Goal': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('lifecycle-status', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('target-date', SearchParamType.date),
    ],
    'MedicationStatement': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('medication', SearchParamType.reference),
      _sp('code', SearchParamType.token),
      _sp('effective', SearchParamType.date),
    ],
    'ServiceRequest': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('code', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('intent', SearchParamType.token),
      _sp('authored', SearchParamType.date),
      _sp('encounter', SearchParamType.reference),
      _sp('requester', SearchParamType.reference),
      _sp('performer', SearchParamType.reference),
    ],
    'DocumentReference': [
      _sp('patient', SearchParamType.reference),
      _sp('subject', SearchParamType.reference),
      _sp('status', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('category', SearchParamType.token),
      _sp('date', SearchParamType.date),
      _sp('author', SearchParamType.reference),
      _sp('encounter', SearchParamType.reference),
    ],
    'Organization': [
      _sp('name', SearchParamType.string),
      _sp('identifier', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('address', SearchParamType.string),
      _sp('address-city', SearchParamType.string),
      _sp('address-state', SearchParamType.string),
      _sp('active', SearchParamType.token),
      _sp('partof', SearchParamType.reference),
    ],
    'Practitioner': [
      _sp('name', SearchParamType.string),
      _sp('family', SearchParamType.string),
      _sp('given', SearchParamType.string),
      _sp('identifier', SearchParamType.token),
      _sp('active', SearchParamType.token),
      _sp('telecom', SearchParamType.token),
    ],
    'PractitionerRole': [
      _sp('practitioner', SearchParamType.reference),
      _sp('organization', SearchParamType.reference),
      _sp('role', SearchParamType.token),
      _sp('specialty', SearchParamType.token),
      _sp('active', SearchParamType.token),
      _sp('location', SearchParamType.reference),
    ],
    'Location': [
      _sp('name', SearchParamType.string),
      _sp('identifier', SearchParamType.token),
      _sp('status', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('address', SearchParamType.string),
      _sp('address-city', SearchParamType.string),
      _sp('address-state', SearchParamType.string),
      _sp('organization', SearchParamType.reference),
    ],
    'Device': [
      _sp('patient', SearchParamType.reference),
      _sp('identifier', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('status', SearchParamType.token),
      _sp('manufacturer', SearchParamType.string),
      _sp('organization', SearchParamType.reference),
      _sp('location', SearchParamType.reference),
    ],
    'Group': [
      _sp('identifier', SearchParamType.token),
      _sp('type', SearchParamType.token),
      _sp('actual', SearchParamType.token),
      _sp('code', SearchParamType.token),
      _sp('name', SearchParamType.string),
      _sp('member', SearchParamType.reference),
      _sp('managing-entity', SearchParamType.reference),
    ],
  };

  /// _include declarations per resource type.
  static const Map<String, List<String>> searchInclude = {
    'Patient': ['Patient:organization', 'Patient:general-practitioner', 'Patient:link'],
    'Observation': ['Observation:patient', 'Observation:subject', 'Observation:encounter', 'Observation:performer'],
    'Condition': ['Condition:patient', 'Condition:subject', 'Condition:encounter', 'Condition:asserter'],
    'Encounter': ['Encounter:patient', 'Encounter:subject', 'Encounter:participant', 'Encounter:location', 'Encounter:service-provider'],
    'MedicationRequest': ['MedicationRequest:patient', 'MedicationRequest:subject', 'MedicationRequest:medication', 'MedicationRequest:requester', 'MedicationRequest:encounter'],
    'Procedure': ['Procedure:patient', 'Procedure:subject', 'Procedure:encounter', 'Procedure:performer'],
    'AllergyIntolerance': ['AllergyIntolerance:patient'],
    'DiagnosticReport': ['DiagnosticReport:patient', 'DiagnosticReport:subject', 'DiagnosticReport:encounter', 'DiagnosticReport:result', 'DiagnosticReport:performer'],
    'Immunization': ['Immunization:patient', 'Immunization:location', 'Immunization:performer'],
    'CarePlan': ['CarePlan:patient', 'CarePlan:subject', 'CarePlan:encounter'],
    'CareTeam': ['CareTeam:patient', 'CareTeam:subject', 'CareTeam:participant', 'CareTeam:encounter'],
    'Goal': ['Goal:patient', 'Goal:subject'],
    'MedicationStatement': ['MedicationStatement:patient', 'MedicationStatement:subject', 'MedicationStatement:medication'],
    'ServiceRequest': ['ServiceRequest:patient', 'ServiceRequest:subject', 'ServiceRequest:encounter', 'ServiceRequest:requester', 'ServiceRequest:performer'],
    'DocumentReference': ['DocumentReference:patient', 'DocumentReference:subject', 'DocumentReference:author', 'DocumentReference:encounter'],
    'Organization': ['Organization:partof'],
    'PractitionerRole': ['PractitionerRole:practitioner', 'PractitionerRole:organization', 'PractitionerRole:location'],
    'Location': ['Location:organization'],
    'Device': ['Device:patient', 'Device:organization', 'Device:location'],
    'Group': ['Group:member', 'Group:managing-entity'],
  };

  /// _revinclude declarations per resource type.
  static const Map<String, List<String>> searchRevInclude = {
    'Patient': ['Observation:patient', 'Condition:patient', 'Encounter:patient', 'MedicationRequest:patient', 'Procedure:patient', 'AllergyIntolerance:patient', 'DiagnosticReport:patient', 'Immunization:patient', 'CarePlan:patient', 'DocumentReference:patient'],
    'Encounter': ['Observation:encounter', 'Condition:encounter', 'MedicationRequest:encounter', 'Procedure:encounter', 'DiagnosticReport:encounter'],
    'Practitioner': ['PractitionerRole:practitioner', 'Encounter:participant'],
    'Organization': ['Patient:organization', 'PractitionerRole:organization', 'Location:organization', 'Device:organization'],
    'Location': ['Encounter:location', 'PractitionerRole:location', 'Device:location'],
    'Observation': ['DiagnosticReport:result'],
  };

  /// Resource types that support $everything (compartment types).
  static const Set<String> everythingTypes = {
    'Patient',
    'Encounter',
    'Practitioner',
    'RelatedPerson',
    'Device',
  };

  /// Resource types that support $export.
  static const Set<String> exportTypes = {'Patient', 'Group'};

  /// Resource types that support $document.
  static const Set<String> documentTypes = {'Composition'};

  /// Resource types that support $validate-code.
  static const Set<String> validateCodeTypes = {'CodeSystem', 'ValueSet'};

  /// Resource types that support $lookup.
  static const Set<String> lookupTypes = {'CodeSystem'};

  /// Resource types that support $expand.
  static const Set<String> expandTypes = {'ValueSet'};

  /// Resource types that support $subsumes.
  static const Set<String> subsumesTypes = {'CodeSystem'};

  /// Resource types that support $translate.
  static const Set<String> translateTypes = {'ConceptMap'};

  /// Resource types that support $preferred-id.
  static const Set<String> preferredIdTypes = {'NamingSystem'};
}
