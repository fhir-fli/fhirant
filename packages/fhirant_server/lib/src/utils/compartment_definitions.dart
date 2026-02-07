// ignore_for_file: lines_longer_than_80_chars

/// Static compartment definitions per the FHIR R4 specification.
///
/// Each entry maps a resource type to the search paths **as stored in the
/// `reference_search_parameters` table** that link it to the compartment's
/// focal resource. An empty list means the resource type IS the focal
/// resource (Patient for Patient compartment, Encounter for Encounter).
///
/// These paths are the JSON field paths (e.g. `Observation.subject`), not
/// the FHIR search parameter names (e.g. `patient`). The DB query uses
/// `LIKE path%` so paths like `Observation.subject.where(resolve() is Patient)`
/// are matched automatically.
class CompartmentDefinitions {
  CompartmentDefinitions._();

  /// Patient compartment — resources linked to a Patient.
  /// See: https://hl7.org/fhir/R4/compartmentdefinition-patient.html
  ///
  /// Paths verified against the generated `search_parameters.dart`.
  static const Map<String, List<String>> patient = {
    'Patient': [], // focal
    'Account': ['Account.subject'],
    'AdverseEvent': ['AdverseEvent.subject'],
    'AllergyIntolerance': ['AllergyIntolerance.patient', 'AllergyIntolerance.recorder', 'AllergyIntolerance.asserter'],
    'Appointment': ['Appointment.participant.actor'],
    'AppointmentResponse': ['AppointmentResponse.actor'],
    'AuditEvent': ['AuditEvent.patient'],
    'Basic': ['Basic.subject', 'Basic.author'],
    'BodyStructure': ['BodyStructure.patient'],
    'CarePlan': ['CarePlan.subject'],
    'CareTeam': ['CareTeam.subject'],
    'ChargeItem': ['ChargeItem.subject'],
    'Claim': ['Claim.patient', 'Claim.payee.party'],
    'ClaimResponse': ['ClaimResponse.patient'],
    'ClinicalImpression': ['ClinicalImpression.subject'],
    'Communication': ['Communication.subject', 'Communication.sender', 'Communication.recipient'],
    'CommunicationRequest': ['CommunicationRequest.subject', 'CommunicationRequest.sender', 'CommunicationRequest.recipient', 'CommunicationRequest.requester'],
    'Composition': ['Composition.subject', 'Composition.author'],
    'Condition': ['Condition.subject', 'Condition.asserter'],
    'Consent': ['Consent.patient'],
    'Coverage': ['Coverage.policyHolder', 'Coverage.subscriber', 'Coverage.beneficiary', 'Coverage.payor'],
    'CoverageEligibilityRequest': ['CoverageEligibilityRequest.patient'],
    'CoverageEligibilityResponse': ['CoverageEligibilityResponse.patient'],
    'DetectedIssue': ['DetectedIssue.patient'],
    'DeviceRequest': ['DeviceRequest.subject'],
    'DeviceUseStatement': ['DeviceUseStatement.subject'],
    'DiagnosticReport': ['DiagnosticReport.subject'],
    'DocumentManifest': ['DocumentManifest.subject', 'DocumentManifest.author', 'DocumentManifest.recipient'],
    'DocumentReference': ['DocumentReference.subject', 'DocumentReference.author'],
    'Encounter': ['Encounter.subject'],
    'EnrollmentRequest': ['EnrollmentRequest.subject'],
    'EpisodeOfCare': ['EpisodeOfCare.patient'],
    'ExplanationOfBenefit': ['ExplanationOfBenefit.patient', 'ExplanationOfBenefit.payee.party'],
    'FamilyMemberHistory': ['FamilyMemberHistory.patient'],
    'Flag': ['Flag.subject'],
    'Goal': ['Goal.subject'],
    'Group': ['Group.member'],
    'ImagingStudy': ['ImagingStudy.patient'],
    'Immunization': ['Immunization.patient'],
    'ImmunizationEvaluation': ['ImmunizationEvaluation.patient'],
    'ImmunizationRecommendation': ['ImmunizationRecommendation.patient'],
    'Invoice': ['Invoice.subject', 'Invoice.patient', 'Invoice.recipient'],
    'List': ['List.subject', 'List.source'],
    'MeasureReport': ['MeasureReport.patient'],
    'Media': ['Media.subject'],
    'MedicationAdministration': ['MedicationAdministration.subject'],
    'MedicationDispense': ['MedicationDispense.subject', 'MedicationDispense.patient', 'MedicationDispense.receiver'],
    'MedicationRequest': ['MedicationRequest.subject'],
    'MedicationStatement': ['MedicationStatement.subject'],
    'MolecularSequence': ['MolecularSequence.patient'],
    'NutritionOrder': ['NutritionOrder.patient'],
    'Observation': ['Observation.subject', 'Observation.performer'],
    'Person': ['Person.patient'],
    'Procedure': ['Procedure.subject'],
    'Provenance': ['Provenance.patient'],
    'QuestionnaireResponse': ['QuestionnaireResponse.subject', 'QuestionnaireResponse.author'],
    'RelatedPerson': ['RelatedPerson.patient'],
    'RequestGroup': ['RequestGroup.subject'],
    'ResearchSubject': ['ResearchSubject.individual'],
    'RiskAssessment': ['RiskAssessment.subject'],
    'Schedule': ['Schedule.actor'],
    'ServiceRequest': ['ServiceRequest.subject'],
    'Specimen': ['Specimen.subject'],
    'SupplyDelivery': ['SupplyDelivery.patient'],
    'SupplyRequest': ['SupplyRequest.subject'],
    'VisionPrescription': ['VisionPrescription.patient'],
  };

  /// Encounter compartment — resources linked to an Encounter.
  /// See: https://hl7.org/fhir/R4/compartmentdefinition-encounter.html
  ///
  /// Paths verified against the generated `search_parameters.dart`.
  static const Map<String, List<String>> encounter = {
    'Encounter': [], // focal
    'CarePlan': ['CarePlan.encounter'],
    'CareTeam': ['CareTeam.encounter'],
    'ChargeItem': ['ChargeItem.context'],
    'Claim': ['Claim.item.encounter'],
    'ClinicalImpression': ['ClinicalImpression.encounter'],
    'Communication': ['Communication.encounter'],
    'CommunicationRequest': ['CommunicationRequest.encounter'],
    'Composition': ['Composition.encounter'],
    'Condition': ['Condition.encounter'],
    'DiagnosticReport': ['DiagnosticReport.encounter'],
    'DocumentReference': ['DocumentReference.context.encounter'],
    'ExplanationOfBenefit': ['ExplanationOfBenefit.item.encounter'],
    'Flag': ['Flag.encounter'],
    'ImagingStudy': ['ImagingStudy.encounter'],
    'List': ['List.encounter'],
    'Media': ['Media.encounter'],
    'MedicationAdministration': ['MedicationAdministration.context'],
    'MedicationDispense': ['MedicationDispense.context'],
    'MedicationRequest': ['MedicationRequest.encounter'],
    'MedicationStatement': ['MedicationStatement.context'],
    'NutritionOrder': ['NutritionOrder.encounter'],
    'Observation': ['Observation.encounter'],
    'Procedure': ['Procedure.encounter'],
    'QuestionnaireResponse': ['QuestionnaireResponse.encounter'],
    'RequestGroup': ['RequestGroup.encounter'],
    'RiskAssessment': ['RiskAssessment.encounter'],
    'ServiceRequest': ['ServiceRequest.encounter'],
    'VisionPrescription': ['VisionPrescription.encounter'],
  };

  /// Returns the compartment definition for the given type, or null if unsupported.
  static Map<String, List<String>>? getDefinition(String compartmentType) {
    switch (compartmentType) {
      case 'Patient':
        return patient;
      case 'Encounter':
        return encounter;
      default:
        return null;
    }
  }
}
