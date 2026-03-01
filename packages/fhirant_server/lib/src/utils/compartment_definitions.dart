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

  /// Practitioner compartment — resources linked to a Practitioner.
  /// See: https://hl7.org/fhir/R4/compartmentdefinition-practitioner.html
  ///
  /// Paths verified against the generated `search_parameters.dart`.
  static const Map<String, List<String>> practitioner = {
    'Practitioner': [], // focal
    'Account': ['Account.subject'],
    'AdverseEvent': ['AdverseEvent.recorder'],
    'AllergyIntolerance': ['AllergyIntolerance.recorder', 'AllergyIntolerance.asserter'],
    'Appointment': ['Appointment.participant.actor'],
    'AppointmentResponse': ['AppointmentResponse.actor'],
    'AuditEvent': ['AuditEvent.agent.who'],
    'Basic': ['Basic.author'],
    'CarePlan': ['CarePlan.performer'],
    'CareTeam': ['CareTeam.participant.member'],
    'ChargeItem': ['ChargeItem.enterer', 'ChargeItem.performer.actor'],
    'Claim': ['Claim.enterer', 'Claim.provider', 'Claim.payee.party', 'Claim.careTeam.provider'],
    'ClaimResponse': ['ClaimResponse.requestor'],
    'ClinicalImpression': ['ClinicalImpression.assessor'],
    'Communication': ['Communication.sender', 'Communication.recipient'],
    'CommunicationRequest': ['CommunicationRequest.sender', 'CommunicationRequest.recipient', 'CommunicationRequest.requester'],
    'Composition': ['Composition.subject', 'Composition.author', 'Composition.attester.party'],
    'Condition': ['Condition.asserter'],
    'CoverageEligibilityRequest': ['CoverageEligibilityRequest.enterer', 'CoverageEligibilityRequest.provider'],
    'CoverageEligibilityResponse': ['CoverageEligibilityResponse.requestor'],
    'DetectedIssue': ['DetectedIssue.author'],
    'DeviceRequest': ['DeviceRequest.requester', 'DeviceRequest.performer'],
    'DiagnosticReport': ['DiagnosticReport.performer'],
    'DocumentManifest': ['DocumentManifest.subject', 'DocumentManifest.author', 'DocumentManifest.recipient'],
    'DocumentReference': ['DocumentReference.subject', 'DocumentReference.author', 'DocumentReference.authenticator'],
    'Encounter': ['Encounter.participant.individual'],
    'EpisodeOfCare': ['EpisodeOfCare.careManager'],
    'ExplanationOfBenefit': ['ExplanationOfBenefit.enterer', 'ExplanationOfBenefit.provider', 'ExplanationOfBenefit.payee.party', 'ExplanationOfBenefit.careTeam.provider'],
    'Flag': ['Flag.author'],
    'Group': ['Group.member.entity'],
    'Immunization': ['Immunization.performer.actor'],
    'Invoice': ['Invoice.participant.actor'],
    'Linkage': ['Linkage.author'],
    'List': ['List.source'],
    'Media': ['Media.subject', 'Media.operator'],
    'MedicationAdministration': ['MedicationAdministration.performer.actor'],
    'MedicationDispense': ['MedicationDispense.performer.actor', 'MedicationDispense.receiver'],
    'MedicationRequest': ['MedicationRequest.requester'],
    'MedicationStatement': ['MedicationStatement.source'],
    'MessageHeader': ['MessageHeader.destination.receiver', 'MessageHeader.author', 'MessageHeader.responsible', 'MessageHeader.enterer'],
    'NutritionOrder': ['NutritionOrder.orderer'],
    'Observation': ['Observation.performer'],
    'Patient': ['Patient.generalPractitioner'],
    'PaymentNotice': ['PaymentNotice.provider'],
    'PaymentReconciliation': ['PaymentReconciliation.requestor'],
    'Person': ['Person.practitioner'],
    'PractitionerRole': ['PractitionerRole.practitioner'],
    'Procedure': ['Procedure.performer.actor'],
    'Provenance': ['Provenance.agent.who'],
    'QuestionnaireResponse': ['QuestionnaireResponse.author', 'QuestionnaireResponse.source'],
    'RequestGroup': ['RequestGroup.participant', 'RequestGroup.author'],
    'ResearchStudy': ['ResearchStudy.principalInvestigator'],
    'RiskAssessment': ['RiskAssessment.performer'],
    'Schedule': ['Schedule.actor'],
    'ServiceRequest': ['ServiceRequest.performer', 'ServiceRequest.requester'],
    'Specimen': ['Specimen.collector'],
    'SupplyDelivery': ['SupplyDelivery.supplier', 'SupplyDelivery.receiver'],
    'SupplyRequest': ['SupplyRequest.requester'],
    'VisionPrescription': ['VisionPrescription.prescriber'],
  };

  /// RelatedPerson compartment — resources linked to a RelatedPerson.
  /// See: https://hl7.org/fhir/R4/compartmentdefinition-relatedperson.html
  ///
  /// Paths verified against the generated `search_parameters.dart`.
  static const Map<String, List<String>> relatedPerson = {
    'RelatedPerson': [], // focal
    'AdverseEvent': ['AdverseEvent.recorder'],
    'AllergyIntolerance': ['AllergyIntolerance.asserter'],
    'Appointment': ['Appointment.participant.actor'],
    'AppointmentResponse': ['AppointmentResponse.actor'],
    'Basic': ['Basic.author'],
    'CarePlan': ['CarePlan.performer'],
    'CareTeam': ['CareTeam.participant.member'],
    'ChargeItem': ['ChargeItem.enterer', 'ChargeItem.performer.actor'],
    'Claim': ['Claim.payee.party'],
    'Communication': ['Communication.sender', 'Communication.recipient'],
    'CommunicationRequest': ['CommunicationRequest.sender', 'CommunicationRequest.recipient', 'CommunicationRequest.requester'],
    'Composition': ['Composition.author'],
    'Condition': ['Condition.asserter'],
    'Coverage': ['Coverage.policyHolder', 'Coverage.subscriber', 'Coverage.payor'],
    'DocumentManifest': ['DocumentManifest.author', 'DocumentManifest.recipient'],
    'DocumentReference': ['DocumentReference.author'],
    'Encounter': ['Encounter.participant.individual'],
    'ExplanationOfBenefit': ['ExplanationOfBenefit.payee.party'],
    'Invoice': ['Invoice.recipient'],
    'MedicationAdministration': ['MedicationAdministration.performer.actor'],
    'MedicationStatement': ['MedicationStatement.source'],
    'Observation': ['Observation.performer'],
    'Patient': ['Patient.link.other'],
    'Person': ['Person.link.target'],
    'Procedure': ['Procedure.performer.actor'],
    'Provenance': ['Provenance.agent.who'],
    'QuestionnaireResponse': ['QuestionnaireResponse.author', 'QuestionnaireResponse.source'],
    'RequestGroup': ['RequestGroup.participant'],
    'Schedule': ['Schedule.actor'],
    'ServiceRequest': ['ServiceRequest.performer'],
    'SupplyRequest': ['SupplyRequest.requester'],
  };

  /// Device compartment — resources linked to a Device.
  /// See: https://hl7.org/fhir/R4/compartmentdefinition-device.html
  ///
  /// Paths verified against the generated `search_parameters.dart`.
  static const Map<String, List<String>> device = {
    'Device': [], // focal
    'Account': ['Account.subject'],
    'Appointment': ['Appointment.participant.actor'],
    'AppointmentResponse': ['AppointmentResponse.actor'],
    'AuditEvent': ['AuditEvent.agent.who'],
    'ChargeItem': ['ChargeItem.enterer', 'ChargeItem.performer.actor'],
    'Claim': ['Claim.procedure.udi', 'Claim.item.udi', 'Claim.item.detail.udi', 'Claim.item.detail.subDetail.udi'],
    'Communication': ['Communication.sender', 'Communication.recipient'],
    'CommunicationRequest': ['CommunicationRequest.sender', 'CommunicationRequest.recipient'],
    'Composition': ['Composition.author'],
    'DetectedIssue': ['DetectedIssue.author'],
    'DeviceRequest': ['DeviceRequest.subject', 'DeviceRequest.requester', 'DeviceRequest.performer'],
    'DeviceUseStatement': ['DeviceUseStatement.device'],
    'DiagnosticReport': ['DiagnosticReport.subject'],
    'DocumentManifest': ['DocumentManifest.subject', 'DocumentManifest.author'],
    'DocumentReference': ['DocumentReference.subject', 'DocumentReference.author'],
    'ExplanationOfBenefit': ['ExplanationOfBenefit.procedure.udi', 'ExplanationOfBenefit.item.udi', 'ExplanationOfBenefit.item.detail.udi', 'ExplanationOfBenefit.item.detail.subDetail.udi'],
    'Flag': ['Flag.author'],
    'Group': ['Group.member.entity'],
    'Invoice': ['Invoice.participant.actor'],
    'List': ['List.subject', 'List.source'],
    'Media': ['Media.subject'],
    'MedicationAdministration': ['MedicationAdministration.device'],
    'MessageHeader': ['MessageHeader.destination.target'],
    'Observation': ['Observation.subject', 'Observation.device'],
    'Provenance': ['Provenance.agent.who'],
    'QuestionnaireResponse': ['QuestionnaireResponse.author'],
    'RequestGroup': ['RequestGroup.author'],
    'RiskAssessment': ['RiskAssessment.performer'],
    'Schedule': ['Schedule.actor'],
    'ServiceRequest': ['ServiceRequest.performer', 'ServiceRequest.requester'],
    'Specimen': ['Specimen.subject'],
    'SupplyRequest': ['SupplyRequest.requester'],
  };

  /// Returns the compartment definition for the given type, or null if unsupported.
  static Map<String, List<String>>? getDefinition(String compartmentType) {
    switch (compartmentType) {
      case 'Patient':
        return patient;
      case 'Encounter':
        return encounter;
      case 'Practitioner':
        return practitioner;
      case 'RelatedPerson':
        return relatedPerson;
      case 'Device':
        return device;
      default:
        return null;
    }
  }
}
