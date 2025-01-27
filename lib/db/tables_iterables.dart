import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';

/// Iterable list of all FHIR tables
const tablesList = [
  AccountTable,
  AccountHistoryTable,
  ActivityDefinitionTable,
  ActivityDefinitionHistoryTable,
  AdministrableProductDefinitionTable,
  AdministrableProductDefinitionHistoryTable,
  AdverseEventTable,
  AdverseEventHistoryTable,
  AllergyIntoleranceTable,
  AllergyIntoleranceHistoryTable,
  AppointmentTable,
  AppointmentHistoryTable,
  AppointmentResponseTable,
  AppointmentResponseHistoryTable,
  AuditEventTable,
  AuditEventHistoryTable,
  BasicTable,
  BasicHistoryTable,
  BinaryTable,
  BinaryHistoryTable,
  BiologicallyDerivedProductTable,
  BiologicallyDerivedProductHistoryTable,
  BodyStructureTable,
  BodyStructureHistoryTable,
  BundleTable,
  BundleHistoryTable,
  CapabilityStatementTable,
  CapabilityStatementHistoryTable,
  CarePlanTable,
  CarePlanHistoryTable,
  CareTeamTable,
  CareTeamHistoryTable,
  CatalogEntryTable,
  CatalogEntryHistoryTable,
  ChargeItemTable,
  ChargeItemHistoryTable,
  ChargeItemDefinitionTable,
  ChargeItemDefinitionHistoryTable,
  CitationTable,
  CitationHistoryTable,
  ClaimTable,
  ClaimHistoryTable,
  ClaimResponseTable,
  ClaimResponseHistoryTable,
  ClinicalImpressionTable,
  ClinicalImpressionHistoryTable,
  ClinicalUseDefinitionTable,
  ClinicalUseDefinitionHistoryTable,
  CodeSystemTable,
  CodeSystemHistoryTable,
  CommunicationTable,
  CommunicationHistoryTable,
  CommunicationRequestTable,
  CommunicationRequestHistoryTable,
  CompartmentDefinitionTable,
  CompartmentDefinitionHistoryTable,
  CompositionTable,
  CompositionHistoryTable,
  ConceptMapTable,
  ConceptMapHistoryTable,
  ConditionTable,
  ConditionHistoryTable,
  ConsentTable,
  ConsentHistoryTable,
  ContractTable,
  ContractHistoryTable,
  CoverageTable,
  CoverageHistoryTable,
  CoverageEligibilityRequestTable,
  CoverageEligibilityRequestHistoryTable,
  CoverageEligibilityResponseTable,
  CoverageEligibilityResponseHistoryTable,
  DetectedIssueTable,
  DetectedIssueHistoryTable,
  DeviceTable,
  DeviceHistoryTable,
  DeviceDefinitionTable,
  DeviceDefinitionHistoryTable,
  DeviceMetricTable,
  DeviceMetricHistoryTable,
  DeviceRequestTable,
  DeviceRequestHistoryTable,
  DeviceUseStatementTable,
  DeviceUseStatementHistoryTable,
  DiagnosticReportTable,
  DiagnosticReportHistoryTable,
  DocumentManifestTable,
  DocumentManifestHistoryTable,
  DocumentReferenceTable,
  DocumentReferenceHistoryTable,
  EncounterTable,
  EncounterHistoryTable,
  EnrollmentRequestTable,
  EnrollmentRequestHistoryTable,
  EnrollmentResponseTable,
  EnrollmentResponseHistoryTable,
  EpisodeOfCareTable,
  EpisodeOfCareHistoryTable,
  EventDefinitionTable,
  EventDefinitionHistoryTable,
  EvidenceTable,
  EvidenceHistoryTable,
  EvidenceReportTable,
  EvidenceReportHistoryTable,
  EvidenceVariableTable,
  EvidenceVariableHistoryTable,
  ExampleScenarioTable,
  ExampleScenarioHistoryTable,
  ExplanationOfBenefitTable,
  ExplanationOfBenefitHistoryTable,
  FamilyMemberHistoryTable,
  FamilyMemberHistoryHistoryTable,
  FhirEndpointTable,
  FhirEndpointHistoryTable,
  FhirGroupTable,
  FhirGroupHistoryTable,
  FhirListTable,
  FhirListHistoryTable,
  FlagTable,
  FlagHistoryTable,
  GoalTable,
  GoalHistoryTable,
  GraphDefinitionTable,
  GraphDefinitionHistoryTable,
  GuidanceResponseTable,
  GuidanceResponseHistoryTable,
  HealthcareServiceTable,
  HealthcareServiceHistoryTable,
  ImagingStudyTable,
  ImagingStudyHistoryTable,
  ImmunizationTable,
  ImmunizationHistoryTable,
  ImmunizationEvaluationTable,
  ImmunizationEvaluationHistoryTable,
  ImmunizationRecommendationTable,
  ImmunizationRecommendationHistoryTable,
  ImplementationGuideTable,
  ImplementationGuideHistoryTable,
  IngredientTable,
  IngredientHistoryTable,
  InsurancePlanTable,
  InsurancePlanHistoryTable,
  InvoiceTable,
  InvoiceHistoryTable,
  LibraryTable,
  LibraryHistoryTable,
  LinkageTable,
  LinkageHistoryTable,
  LocationTable,
  LocationHistoryTable,
  ManufacturedItemDefinitionTable,
  ManufacturedItemDefinitionHistoryTable,
  MeasureTable,
  MeasureHistoryTable,
  MeasureReportTable,
  MeasureReportHistoryTable,
  MediaTable,
  MediaHistoryTable,
  MedicationTable,
  MedicationHistoryTable,
  MedicationAdministrationTable,
  MedicationAdministrationHistoryTable,
  MedicationDispenseTable,
  MedicationDispenseHistoryTable,
  MedicationKnowledgeTable,
  MedicationKnowledgeHistoryTable,
  MedicationRequestTable,
  MedicationRequestHistoryTable,
  MedicationStatementTable,
  MedicationStatementHistoryTable,
  MedicinalProductDefinitionTable,
  MedicinalProductDefinitionHistoryTable,
  MessageDefinitionTable,
  MessageDefinitionHistoryTable,
  MessageHeaderTable,
  MessageHeaderHistoryTable,
  MolecularSequenceTable,
  MolecularSequenceHistoryTable,
  NamingSystemTable,
  NamingSystemHistoryTable,
  NutritionOrderTable,
  NutritionOrderHistoryTable,
  NutritionProductTable,
  NutritionProductHistoryTable,
  ObservationTable,
  ObservationHistoryTable,
  ObservationDefinitionTable,
  ObservationDefinitionHistoryTable,
  OperationDefinitionTable,
  OperationDefinitionHistoryTable,
  OperationOutcomeTable,
  OperationOutcomeHistoryTable,
  OrganizationTable,
  OrganizationHistoryTable,
  OrganizationAffiliationTable,
  OrganizationAffiliationHistoryTable,
  PackagedProductDefinitionTable,
  PackagedProductDefinitionHistoryTable,
  ParametersTable,
  ParametersHistoryTable,
  PatientTable,
  PatientHistoryTable,
  PaymentNoticeTable,
  PaymentNoticeHistoryTable,
  PaymentReconciliationTable,
  PaymentReconciliationHistoryTable,
  PersonTable,
  PersonHistoryTable,
  PlanDefinitionTable,
  PlanDefinitionHistoryTable,
  PractitionerTable,
  PractitionerHistoryTable,
  PractitionerRoleTable,
  PractitionerRoleHistoryTable,
  ProcedureTable,
  ProcedureHistoryTable,
  ProvenanceTable,
  ProvenanceHistoryTable,
  QuestionnaireTable,
  QuestionnaireHistoryTable,
  QuestionnaireResponseTable,
  QuestionnaireResponseHistoryTable,
  RegulatedAuthorizationTable,
  RegulatedAuthorizationHistoryTable,
  RelatedPersonTable,
  RelatedPersonHistoryTable,
  RequestGroupTable,
  RequestGroupHistoryTable,
  ResearchDefinitionTable,
  ResearchDefinitionHistoryTable,
  ResearchElementDefinitionTable,
  ResearchElementDefinitionHistoryTable,
  ResearchStudyTable,
  ResearchStudyHistoryTable,
  ResearchSubjectTable,
  ResearchSubjectHistoryTable,
  RiskAssessmentTable,
  RiskAssessmentHistoryTable,
  ScheduleTable,
  ScheduleHistoryTable,
  SearchParameterTable,
  SearchParameterHistoryTable,
  ServiceRequestTable,
  ServiceRequestHistoryTable,
  SlotTable,
  SlotHistoryTable,
  SpecimenTable,
  SpecimenHistoryTable,
  SpecimenDefinitionTable,
  SpecimenDefinitionHistoryTable,
  StructureDefinitionTable,
  StructureDefinitionHistoryTable,
  StructureMapTable,
  StructureMapHistoryTable,
  SubscriptionTable,
  SubscriptionHistoryTable,
  SubscriptionStatusTable,
  SubscriptionStatusHistoryTable,
  SubscriptionTopicTable,
  SubscriptionTopicHistoryTable,
  SubstanceTable,
  SubstanceHistoryTable,
  SubstanceDefinitionTable,
  SubstanceDefinitionHistoryTable,
  SupplyDeliveryTable,
  SupplyDeliveryHistoryTable,
  SupplyRequestTable,
  SupplyRequestHistoryTable,
  TaskTable,
  TaskHistoryTable,
  TerminologyCapabilitiesTable,
  TerminologyCapabilitiesHistoryTable,
  TestReportTable,
  TestReportHistoryTable,
  TestScriptTable,
  TestScriptHistoryTable,
  ValueSetTable,
  ValueSetHistoryTable,
  VerificationResultTable,
  VerificationResultHistoryTable,
  VisionPrescriptionTable,
  VisionPrescriptionHistoryTable,
];

/// Iterable list of all FHIR tables
TableInfo<Table, dynamic> getTableByType(R4ResourceType type, AppDatabase db) {
  switch (type) {
    case R4ResourceType.Account:
      return db.accountTable;

    case R4ResourceType.ActivityDefinition:
      return db.activityDefinitionTable;

    case R4ResourceType.AdministrableProductDefinition:
      return db.administrableProductDefinitionTable;

    case R4ResourceType.AdverseEvent:
      return db.adverseEventTable;

    case R4ResourceType.AllergyIntolerance:
      return db.allergyIntoleranceTable;

    case R4ResourceType.Appointment:
      return db.appointmentTable;

    case R4ResourceType.AppointmentResponse:
      return db.appointmentResponseTable;

    case R4ResourceType.AuditEvent:
      return db.auditEventTable;

    case R4ResourceType.Basic:
      return db.basicTable;

    case R4ResourceType.Binary:
      return db.binaryTable;

    case R4ResourceType.BiologicallyDerivedProduct:
      return db.biologicallyDerivedProductTable;

    case R4ResourceType.BodyStructure:
      return db.bodyStructureTable;

    case R4ResourceType.Bundle:
      return db.bundleTable;

    case R4ResourceType.CapabilityStatement:
      return db.capabilityStatementTable;

    case R4ResourceType.CarePlan:
      return db.carePlanTable;

    case R4ResourceType.CareTeam:
      return db.careTeamTable;

    case R4ResourceType.CatalogEntry:
      return db.catalogEntryTable;

    case R4ResourceType.ChargeItem:
      return db.chargeItemTable;

    case R4ResourceType.ChargeItemDefinition:
      return db.chargeItemDefinitionTable;

    case R4ResourceType.Citation:
      return db.citationTable;

    case R4ResourceType.Claim:
      return db.claimTable;

    case R4ResourceType.ClaimResponse:
      return db.claimResponseTable;

    case R4ResourceType.ClinicalImpression:
      return db.clinicalImpressionTable;

    case R4ResourceType.ClinicalUseDefinition:
      return db.clinicalUseDefinitionTable;

    case R4ResourceType.CodeSystem:
      return db.codeSystemTable;

    case R4ResourceType.Communication:
      return db.communicationTable;

    case R4ResourceType.CommunicationRequest:
      return db.communicationRequestTable;

    case R4ResourceType.CompartmentDefinition:
      return db.compartmentDefinitionTable;

    case R4ResourceType.Composition:
      return db.compositionTable;

    case R4ResourceType.ConceptMap:
      return db.conceptMapTable;

    case R4ResourceType.Condition:
      return db.conditionTable;

    case R4ResourceType.Consent:
      return db.consentTable;

    case R4ResourceType.Contract:
      return db.contractTable;

    case R4ResourceType.Coverage:
      return db.coverageTable;

    case R4ResourceType.CoverageEligibilityRequest:
      return db.coverageEligibilityRequestTable;

    case R4ResourceType.CoverageEligibilityResponse:
      return db.coverageEligibilityResponseTable;

    case R4ResourceType.DetectedIssue:
      return db.detectedIssueTable;

    case R4ResourceType.Device:
      return db.deviceTable;

    case R4ResourceType.DeviceDefinition:
      return db.deviceDefinitionTable;

    case R4ResourceType.DeviceMetric:
      return db.deviceMetricTable;

    case R4ResourceType.DeviceRequest:
      return db.deviceRequestTable;

    case R4ResourceType.DeviceUseStatement:
      return db.deviceUseStatementTable;

    case R4ResourceType.DiagnosticReport:
      return db.diagnosticReportTable;

    case R4ResourceType.DocumentManifest:
      return db.documentManifestTable;

    case R4ResourceType.DocumentReference:
      return db.documentReferenceTable;

    case R4ResourceType.Encounter:
      return db.encounterTable;

    case R4ResourceType.EnrollmentRequest:
      return db.enrollmentRequestTable;

    case R4ResourceType.EnrollmentResponse:
      return db.enrollmentResponseTable;

    case R4ResourceType.EpisodeOfCare:
      return db.episodeOfCareTable;

    case R4ResourceType.EventDefinition:
      return db.eventDefinitionTable;

    case R4ResourceType.Evidence:
      return db.evidenceTable;

    case R4ResourceType.EvidenceReport:
      return db.evidenceReportTable;

    case R4ResourceType.EvidenceVariable:
      return db.evidenceVariableTable;

    case R4ResourceType.ExampleScenario:
      return db.exampleScenarioTable;

    case R4ResourceType.ExplanationOfBenefit:
      return db.explanationOfBenefitTable;

    case R4ResourceType.FhirEndpoint:
      return db.fhirEndpointTable;

    case R4ResourceType.FhirGroup:
      return db.fhirGroupTable;

    case R4ResourceType.FhirList:
      return db.fhirListTable;

    case R4ResourceType.Flag:
      return db.flagTable;

    case R4ResourceType.Goal:
      return db.goalTable;

    case R4ResourceType.GraphDefinition:
      return db.graphDefinitionTable;

    case R4ResourceType.GuidanceResponse:
      return db.guidanceResponseTable;

    case R4ResourceType.HealthcareService:
      return db.healthcareServiceTable;

    case R4ResourceType.ImagingStudy:
      return db.imagingStudyTable;

    case R4ResourceType.Immunization:
      return db.immunizationTable;

    case R4ResourceType.ImmunizationEvaluation:
      return db.immunizationEvaluationTable;

    case R4ResourceType.ImmunizationRecommendation:
      return db.immunizationRecommendationTable;

    case R4ResourceType.ImplementationGuide:
      return db.implementationGuideTable;

    case R4ResourceType.Ingredient:
      return db.ingredientTable;

    case R4ResourceType.InsurancePlan:
      return db.insurancePlanTable;

    case R4ResourceType.Invoice:
      return db.invoiceTable;

    case R4ResourceType.Library:
      return db.libraryTable;

    case R4ResourceType.Linkage:
      return db.linkageTable;

    case R4ResourceType.Location:
      return db.locationTable;

    case R4ResourceType.ManufacturedItemDefinition:
      return db.manufacturedItemDefinitionTable;

    case R4ResourceType.Measure:
      return db.measureTable;

    case R4ResourceType.MeasureReport:
      return db.measureReportTable;

    case R4ResourceType.Media:
      return db.mediaTable;

    case R4ResourceType.Medication:
      return db.medicationTable;

    case R4ResourceType.MedicationAdministration:
      return db.medicationAdministrationTable;

    case R4ResourceType.MedicationDispense:
      return db.medicationDispenseTable;

    case R4ResourceType.MedicationKnowledge:
      return db.medicationKnowledgeTable;

    case R4ResourceType.MedicationRequest:
      return db.medicationRequestTable;

    case R4ResourceType.MedicationStatement:
      return db.medicationStatementTable;

    case R4ResourceType.MedicinalProductDefinition:
      return db.medicinalProductDefinitionTable;

    case R4ResourceType.MessageDefinition:
      return db.messageDefinitionTable;

    case R4ResourceType.MessageHeader:
      return db.messageHeaderTable;

    case R4ResourceType.MolecularSequence:
      return db.molecularSequenceTable;

    case R4ResourceType.NamingSystem:
      return db.namingSystemTable;

    case R4ResourceType.NutritionOrder:
      return db.nutritionOrderTable;

    case R4ResourceType.NutritionProduct:
      return db.nutritionProductTable;

    case R4ResourceType.Observation:
      return db.observationTable;

    case R4ResourceType.ObservationDefinition:
      return db.observationDefinitionTable;

    case R4ResourceType.OperationDefinition:
      return db.operationDefinitionTable;

    case R4ResourceType.OperationOutcome:
      return db.operationOutcomeTable;

    case R4ResourceType.Organization:
      return db.organizationTable;

    case R4ResourceType.OrganizationAffiliation:
      return db.organizationAffiliationTable;

    case R4ResourceType.PackagedProductDefinition:
      return db.packagedProductDefinitionTable;

    case R4ResourceType.Parameters:
      return db.parametersTable;

    case R4ResourceType.Patient:
      return db.patientTable;

    case R4ResourceType.PaymentNotice:
      return db.paymentNoticeTable;

    case R4ResourceType.PaymentReconciliation:
      return db.paymentReconciliationTable;

    case R4ResourceType.Person:
      return db.personTable;

    case R4ResourceType.PlanDefinition:
      return db.planDefinitionTable;

    case R4ResourceType.Practitioner:
      return db.practitionerTable;

    case R4ResourceType.PractitionerRole:
      return db.practitionerRoleTable;

    case R4ResourceType.Procedure:
      return db.procedureTable;

    case R4ResourceType.Provenance:
      return db.provenanceTable;

    case R4ResourceType.Questionnaire:
      return db.questionnaireTable;

    case R4ResourceType.QuestionnaireResponse:
      return db.questionnaireResponseTable;

    case R4ResourceType.RegulatedAuthorization:
      return db.regulatedAuthorizationTable;

    case R4ResourceType.RelatedPerson:
      return db.relatedPersonTable;

    case R4ResourceType.RequestGroup:
      return db.requestGroupTable;

    case R4ResourceType.ResearchDefinition:
      return db.researchDefinitionTable;

    case R4ResourceType.ResearchElementDefinition:
      return db.researchElementDefinitionTable;

    case R4ResourceType.ResearchStudy:
      return db.researchStudyTable;

    case R4ResourceType.ResearchSubject:
      return db.researchSubjectTable;

    case R4ResourceType.RiskAssessment:
      return db.riskAssessmentTable;

    case R4ResourceType.Schedule:
      return db.scheduleTable;

    case R4ResourceType.SearchParameter:
      return db.searchParameterTable;

    case R4ResourceType.ServiceRequest:
      return db.serviceRequestTable;

    case R4ResourceType.Slot:
      return db.slotTable;

    case R4ResourceType.Specimen:
      return db.specimenTable;

    case R4ResourceType.SpecimenDefinition:
      return db.specimenDefinitionTable;

    case R4ResourceType.StructureDefinition:
      return db.structureDefinitionTable;

    case R4ResourceType.StructureMap:
      return db.structureMapTable;

    case R4ResourceType.Subscription:
      return db.subscriptionTable;

    case R4ResourceType.SubscriptionStatus:
      return db.subscriptionStatusTable;

    case R4ResourceType.SubscriptionTopic:
      return db.subscriptionTopicTable;

    case R4ResourceType.Substance:
      return db.substanceTable;

    case R4ResourceType.SubstanceDefinition:
      return db.substanceDefinitionTable;

    case R4ResourceType.SupplyDelivery:
      return db.supplyDeliveryTable;

    case R4ResourceType.SupplyRequest:
      return db.supplyRequestTable;

    case R4ResourceType.Task:
      return db.taskTable;

    case R4ResourceType.TerminologyCapabilities:
      return db.terminologyCapabilitiesTable;

    case R4ResourceType.TestReport:
      return db.testReportTable;

    case R4ResourceType.TestScript:
      return db.testScriptTable;

    case R4ResourceType.ValueSet:
      return db.valueSetTable;

    case R4ResourceType.VerificationResult:
      return db.verificationResultTable;

    case R4ResourceType.VisionPrescription:
      return db.visionPrescriptionTable;

    case R4ResourceType.FamilyMemberHistory:
      return db.familyMemberHistoryTable;
  }
}
