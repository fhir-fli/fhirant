import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/sqflite/db.dart';
import 'package:sqflite/sqflite.dart';

Future<bool> Function(Transaction, Resource) saveFunction(
  R4ResourceType resourceType,
) {
  switch (resourceType) {
    case R4ResourceType.Account:
      return (txn, resource) async => saveAccount(txn, resource as Account);
    case R4ResourceType.ActivityDefinition:
      return (txn, resource) async =>
          saveActivityDefinition(txn, resource as ActivityDefinition);
    case R4ResourceType.AdministrableProductDefinition:
      return (txn, resource) async => saveAdministrableProductDefinition(
            txn,
            resource as AdministrableProductDefinition,
          );
    case R4ResourceType.AdverseEvent:
      return (txn, resource) async =>
          saveAdverseEvent(txn, resource as AdverseEvent);
    case R4ResourceType.AllergyIntolerance:
      return (txn, resource) async =>
          saveAllergyIntolerance(txn, resource as AllergyIntolerance);
    case R4ResourceType.Appointment:
      return (txn, resource) async =>
          saveAppointment(txn, resource as Appointment);
    case R4ResourceType.AppointmentResponse:
      return (txn, resource) async =>
          saveAppointmentResponse(txn, resource as AppointmentResponse);
    case R4ResourceType.AuditEvent:
      return (txn, resource) async =>
          saveAuditEvent(txn, resource as AuditEvent);
    case R4ResourceType.Basic:
      return (txn, resource) async => saveBasic(txn, resource as Basic);
    case R4ResourceType.Binary:
      return (txn, resource) async => saveBinary(txn, resource as Binary);
    case R4ResourceType.BiologicallyDerivedProduct:
      return (txn, resource) async => saveBiologicallyDerivedProduct(
            txn,
            resource as BiologicallyDerivedProduct,
          );
    case R4ResourceType.BodyStructure:
      return (txn, resource) async =>
          saveBodyStructure(txn, resource as BodyStructure);
    case R4ResourceType.Bundle:
      return (txn, resource) async => saveBundle(txn, resource as Bundle);
    case R4ResourceType.CapabilityStatement:
      return (txn, resource) async =>
          saveCapabilityStatement(txn, resource as CapabilityStatement);
    case R4ResourceType.CarePlan:
      return (txn, resource) async => saveCarePlan(txn, resource as CarePlan);
    case R4ResourceType.CareTeam:
      return (txn, resource) async => saveCareTeam(txn, resource as CareTeam);
    case R4ResourceType.CatalogEntry:
      return (txn, resource) async =>
          saveCatalogEntry(txn, resource as CatalogEntry);
    case R4ResourceType.ChargeItem:
      return (txn, resource) async =>
          saveChargeItem(txn, resource as ChargeItem);
    case R4ResourceType.ChargeItemDefinition:
      return (txn, resource) async =>
          saveChargeItemDefinition(txn, resource as ChargeItemDefinition);
    case R4ResourceType.Citation:
      return (txn, resource) async => saveCitation(txn, resource as Citation);
    case R4ResourceType.Claim:
      return (txn, resource) async => saveClaim(txn, resource as Claim);
    case R4ResourceType.ClaimResponse:
      return (txn, resource) async =>
          saveClaimResponse(txn, resource as ClaimResponse);
    case R4ResourceType.ClinicalImpression:
      return (txn, resource) async =>
          saveClinicalImpression(txn, resource as ClinicalImpression);
    case R4ResourceType.ClinicalUseDefinition:
      return (txn, resource) async =>
          saveClinicalUseDefinition(txn, resource as ClinicalUseDefinition);
    case R4ResourceType.CodeSystem:
      return (txn, resource) async =>
          saveCodeSystem(txn, resource as CodeSystem);
    case R4ResourceType.Communication:
      return (txn, resource) async =>
          saveCommunication(txn, resource as Communication);
    case R4ResourceType.CommunicationRequest:
      return (txn, resource) async =>
          saveCommunicationRequest(txn, resource as CommunicationRequest);
    case R4ResourceType.CompartmentDefinition:
      return (txn, resource) async =>
          saveCompartmentDefinition(txn, resource as CompartmentDefinition);
    case R4ResourceType.Composition:
      return (txn, resource) async =>
          saveComposition(txn, resource as Composition);
    case R4ResourceType.ConceptMap:
      return (txn, resource) async =>
          saveConceptMap(txn, resource as ConceptMap);
    case R4ResourceType.Condition:
      return (txn, resource) async => saveCondition(txn, resource as Condition);
    case R4ResourceType.Consent:
      return (txn, resource) async => saveConsent(txn, resource as Consent);
    case R4ResourceType.Contract:
      return (txn, resource) async => saveContract(txn, resource as Contract);
    case R4ResourceType.Coverage:
      return (txn, resource) async => saveCoverage(txn, resource as Coverage);
    case R4ResourceType.CoverageEligibilityRequest:
      return (txn, resource) async => saveCoverageEligibilityRequest(
            txn,
            resource as CoverageEligibilityRequest,
          );
    case R4ResourceType.CoverageEligibilityResponse:
      return (txn, resource) async => saveCoverageEligibilityResponse(
            txn,
            resource as CoverageEligibilityResponse,
          );
    case R4ResourceType.DetectedIssue:
      return (txn, resource) async =>
          saveDetectedIssue(txn, resource as DetectedIssue);
    case R4ResourceType.Device:
      return (txn, resource) async => saveDevice(txn, resource as Device);
    case R4ResourceType.DeviceDefinition:
      return (txn, resource) async =>
          saveDeviceDefinition(txn, resource as DeviceDefinition);
    case R4ResourceType.DeviceMetric:
      return (txn, resource) async =>
          saveDeviceMetric(txn, resource as DeviceMetric);
    case R4ResourceType.DeviceRequest:
      return (txn, resource) async =>
          saveDeviceRequest(txn, resource as DeviceRequest);
    case R4ResourceType.DeviceUseStatement:
      return (txn, resource) async =>
          saveDeviceUseStatement(txn, resource as DeviceUseStatement);
    case R4ResourceType.DiagnosticReport:
      return (txn, resource) async =>
          saveDiagnosticReport(txn, resource as DiagnosticReport);
    case R4ResourceType.DocumentManifest:
      return (txn, resource) async =>
          saveDocumentManifest(txn, resource as DocumentManifest);
    case R4ResourceType.DocumentReference:
      return (txn, resource) async =>
          saveDocumentReference(txn, resource as DocumentReference);
    case R4ResourceType.Encounter:
      return (txn, resource) async => saveEncounter(txn, resource as Encounter);
    case R4ResourceType.FhirEndpoint:
      return (txn, resource) async =>
          saveFhirEndpoint(txn, resource as FhirEndpoint);
    case R4ResourceType.EnrollmentRequest:
      return (txn, resource) async =>
          saveEnrollmentRequest(txn, resource as EnrollmentRequest);
    case R4ResourceType.EnrollmentResponse:
      return (txn, resource) async =>
          saveEnrollmentResponse(txn, resource as EnrollmentResponse);
    case R4ResourceType.EpisodeOfCare:
      return (txn, resource) async =>
          saveEpisodeOfCare(txn, resource as EpisodeOfCare);
    case R4ResourceType.EventDefinition:
      return (txn, resource) async =>
          saveEventDefinition(txn, resource as EventDefinition);
    case R4ResourceType.Evidence:
      return (txn, resource) async => saveEvidence(txn, resource as Evidence);
    case R4ResourceType.EvidenceReport:
      return (txn, resource) async =>
          saveEvidenceReport(txn, resource as EvidenceReport);
    case R4ResourceType.EvidenceVariable:
      return (txn, resource) async =>
          saveEvidenceVariable(txn, resource as EvidenceVariable);
    case R4ResourceType.ExampleScenario:
      return (txn, resource) async =>
          saveExampleScenario(txn, resource as ExampleScenario);
    case R4ResourceType.ExplanationOfBenefit:
      return (txn, resource) async =>
          saveExplanationOfBenefit(txn, resource as ExplanationOfBenefit);
    case R4ResourceType.FamilyMemberHistory:
      return (txn, resource) async =>
          saveFamilyMemberHistory(txn, resource as FamilyMemberHistory);
    case R4ResourceType.Flag:
      return (txn, resource) async => saveFlag(txn, resource as Flag);
    case R4ResourceType.Goal:
      return (txn, resource) async => saveGoal(txn, resource as Goal);
    case R4ResourceType.GraphDefinition:
      return (txn, resource) async =>
          saveGraphDefinition(txn, resource as GraphDefinition);
    case R4ResourceType.FhirGroup:
      return (txn, resource) async => saveFhirGroup(txn, resource as FhirGroup);
    case R4ResourceType.GuidanceResponse:
      return (txn, resource) async =>
          saveGuidanceResponse(txn, resource as GuidanceResponse);
    case R4ResourceType.HealthcareService:
      return (txn, resource) async =>
          saveHealthcareService(txn, resource as HealthcareService);
    case R4ResourceType.ImagingStudy:
      return (txn, resource) async =>
          saveImagingStudy(txn, resource as ImagingStudy);
    case R4ResourceType.Immunization:
      return (txn, resource) async =>
          saveImmunization(txn, resource as Immunization);
    case R4ResourceType.ImmunizationEvaluation:
      return (txn, resource) async =>
          saveImmunizationEvaluation(txn, resource as ImmunizationEvaluation);
    case R4ResourceType.ImmunizationRecommendation:
      return (txn, resource) async => saveImmunizationRecommendation(
            txn,
            resource as ImmunizationRecommendation,
          );
    case R4ResourceType.ImplementationGuide:
      return (txn, resource) async =>
          saveImplementationGuide(txn, resource as ImplementationGuide);
    case R4ResourceType.Ingredient:
      return (txn, resource) async =>
          saveIngredient(txn, resource as Ingredient);
    case R4ResourceType.InsurancePlan:
      return (txn, resource) async =>
          saveInsurancePlan(txn, resource as InsurancePlan);
    case R4ResourceType.Invoice:
      return (txn, resource) async => saveInvoice(txn, resource as Invoice);
    case R4ResourceType.Library:
      return (txn, resource) async => saveLibrary(txn, resource as Library);
    case R4ResourceType.Linkage:
      return (txn, resource) async => saveLinkage(txn, resource as Linkage);
    case R4ResourceType.FhirList:
      return (txn, resource) async => saveFhirList(txn, resource as FhirList);
    case R4ResourceType.Location:
      return (txn, resource) async => saveLocation(txn, resource as Location);
    case R4ResourceType.ManufacturedItemDefinition:
      return (txn, resource) async => saveManufacturedItemDefinition(
            txn,
            resource as ManufacturedItemDefinition,
          );
    case R4ResourceType.Measure:
      return (txn, resource) async => saveMeasure(txn, resource as Measure);
    case R4ResourceType.MeasureReport:
      return (txn, resource) async =>
          saveMeasureReport(txn, resource as MeasureReport);
    case R4ResourceType.Media:
      return (txn, resource) async => saveMedia(txn, resource as Media);
    case R4ResourceType.Medication:
      return (txn, resource) async =>
          saveMedication(txn, resource as Medication);
    case R4ResourceType.MedicationAdministration:
      return (txn, resource) async => saveMedicationAdministration(
            txn,
            resource as MedicationAdministration,
          );
    case R4ResourceType.MedicationDispense:
      return (txn, resource) async =>
          saveMedicationDispense(txn, resource as MedicationDispense);
    case R4ResourceType.MedicationKnowledge:
      return (txn, resource) async =>
          saveMedicationKnowledge(txn, resource as MedicationKnowledge);
    case R4ResourceType.MedicationRequest:
      return (txn, resource) async =>
          saveMedicationRequest(txn, resource as MedicationRequest);
    case R4ResourceType.MedicationStatement:
      return (txn, resource) async =>
          saveMedicationStatement(txn, resource as MedicationStatement);
    case R4ResourceType.MedicinalProductDefinition:
      return (txn, resource) async => saveMedicinalProductDefinition(
            txn,
            resource as MedicinalProductDefinition,
          );
    case R4ResourceType.MessageDefinition:
      return (txn, resource) async =>
          saveMessageDefinition(txn, resource as MessageDefinition);
    case R4ResourceType.MessageHeader:
      return (txn, resource) async =>
          saveMessageHeader(txn, resource as MessageHeader);
    case R4ResourceType.MolecularSequence:
      return (txn, resource) async =>
          saveMolecularSequence(txn, resource as MolecularSequence);
    case R4ResourceType.NamingSystem:
      return (txn, resource) async =>
          saveNamingSystem(txn, resource as NamingSystem);
    case R4ResourceType.NutritionOrder:
      return (txn, resource) async =>
          saveNutritionOrder(txn, resource as NutritionOrder);
    case R4ResourceType.NutritionProduct:
      return (txn, resource) async =>
          saveNutritionProduct(txn, resource as NutritionProduct);
    case R4ResourceType.Observation:
      return (txn, resource) async =>
          saveObservation(txn, resource as Observation);
    case R4ResourceType.ObservationDefinition:
      return (txn, resource) async =>
          saveObservationDefinition(txn, resource as ObservationDefinition);
    case R4ResourceType.OperationDefinition:
      return (txn, resource) async =>
          saveOperationDefinition(txn, resource as OperationDefinition);
    case R4ResourceType.OperationOutcome:
      return (txn, resource) async =>
          saveOperationOutcome(txn, resource as OperationOutcome);
    case R4ResourceType.Organization:
      return (txn, resource) async =>
          saveOrganization(txn, resource as Organization);
    case R4ResourceType.OrganizationAffiliation:
      return (txn, resource) async => saveOrganizationAffiliation(
            txn,
            resource as OrganizationAffiliation,
          );
    case R4ResourceType.PackagedProductDefinition:
      return (txn, resource) async => savePackagedProductDefinition(
            txn,
            resource as PackagedProductDefinition,
          );
    case R4ResourceType.Parameters:
      return (txn, resource) async =>
          saveParameters(txn, resource as Parameters);
    case R4ResourceType.Patient:
      return (txn, resource) async => savePatient(txn, resource as Patient);
    case R4ResourceType.PaymentNotice:
      return (txn, resource) async =>
          savePaymentNotice(txn, resource as PaymentNotice);
    case R4ResourceType.PaymentReconciliation:
      return (txn, resource) async =>
          savePaymentReconciliation(txn, resource as PaymentReconciliation);
    case R4ResourceType.Person:
      return (txn, resource) async => savePerson(txn, resource as Person);
    case R4ResourceType.PlanDefinition:
      return (txn, resource) async =>
          savePlanDefinition(txn, resource as PlanDefinition);
    case R4ResourceType.Practitioner:
      return (txn, resource) async =>
          savePractitioner(txn, resource as Practitioner);
    case R4ResourceType.PractitionerRole:
      return (txn, resource) async =>
          savePractitionerRole(txn, resource as PractitionerRole);
    case R4ResourceType.Procedure:
      return (txn, resource) async => saveProcedure(txn, resource as Procedure);
    case R4ResourceType.Provenance:
      return (txn, resource) async =>
          saveProvenance(txn, resource as Provenance);
    case R4ResourceType.Questionnaire:
      return (txn, resource) async =>
          saveQuestionnaire(txn, resource as Questionnaire);
    case R4ResourceType.QuestionnaireResponse:
      return (txn, resource) async =>
          saveQuestionnaireResponse(txn, resource as QuestionnaireResponse);
    case R4ResourceType.RegulatedAuthorization:
      return (txn, resource) async =>
          saveRegulatedAuthorization(txn, resource as RegulatedAuthorization);
    case R4ResourceType.RelatedPerson:
      return (txn, resource) async =>
          saveRelatedPerson(txn, resource as RelatedPerson);
    case R4ResourceType.RequestGroup:
      return (txn, resource) async =>
          saveRequestGroup(txn, resource as RequestGroup);
    case R4ResourceType.ResearchDefinition:
      return (txn, resource) async =>
          saveResearchDefinition(txn, resource as ResearchDefinition);
    case R4ResourceType.ResearchElementDefinition:
      return (txn, resource) async => saveResearchElementDefinition(
            txn,
            resource as ResearchElementDefinition,
          );
    case R4ResourceType.ResearchStudy:
      return (txn, resource) async =>
          saveResearchStudy(txn, resource as ResearchStudy);
    case R4ResourceType.ResearchSubject:
      return (txn, resource) async =>
          saveResearchSubject(txn, resource as ResearchSubject);
    case R4ResourceType.RiskAssessment:
      return (txn, resource) async =>
          saveRiskAssessment(txn, resource as RiskAssessment);
    case R4ResourceType.Schedule:
      return (txn, resource) async => saveSchedule(txn, resource as Schedule);
    case R4ResourceType.SearchParameter:
      return (txn, resource) async =>
          saveSearchParameter(txn, resource as SearchParameter);
    case R4ResourceType.ServiceRequest:
      return (txn, resource) async =>
          saveServiceRequest(txn, resource as ServiceRequest);
    case R4ResourceType.Slot:
      return (txn, resource) async => saveSlot(txn, resource as Slot);
    case R4ResourceType.Specimen:
      return (txn, resource) async => saveSpecimen(txn, resource as Specimen);
    case R4ResourceType.SpecimenDefinition:
      return (txn, resource) async =>
          saveSpecimenDefinition(txn, resource as SpecimenDefinition);
    case R4ResourceType.StructureDefinition:
      return (txn, resource) async =>
          saveStructureDefinition(txn, resource as StructureDefinition);
    case R4ResourceType.StructureMap:
      return (txn, resource) async =>
          saveStructureMap(txn, resource as StructureMap);
    case R4ResourceType.Subscription:
      return (txn, resource) async =>
          saveSubscription(txn, resource as Subscription);
    case R4ResourceType.SubscriptionStatus:
      return (txn, resource) async =>
          saveSubscriptionStatus(txn, resource as SubscriptionStatus);
    case R4ResourceType.SubscriptionTopic:
      return (txn, resource) async =>
          saveSubscriptionTopic(txn, resource as SubscriptionTopic);
    case R4ResourceType.Substance:
      return (txn, resource) async => saveSubstance(txn, resource as Substance);
    case R4ResourceType.SubstanceDefinition:
      return (txn, resource) async =>
          saveSubstanceDefinition(txn, resource as SubstanceDefinition);
    case R4ResourceType.SupplyDelivery:
      return (txn, resource) async =>
          saveSupplyDelivery(txn, resource as SupplyDelivery);
    case R4ResourceType.SupplyRequest:
      return (txn, resource) async =>
          saveSupplyRequest(txn, resource as SupplyRequest);
    case R4ResourceType.Task:
      return (txn, resource) async => saveTask(txn, resource as Task);
    case R4ResourceType.TerminologyCapabilities:
      return (txn, resource) async => saveTerminologyCapabilities(
            txn,
            resource as TerminologyCapabilities,
          );
    case R4ResourceType.TestReport:
      return (txn, resource) async =>
          saveTestReport(txn, resource as TestReport);
    case R4ResourceType.TestScript:
      return (txn, resource) async =>
          saveTestScript(txn, resource as TestScript);
    case R4ResourceType.ValueSet:
      return (txn, resource) async => saveValueSet(txn, resource as ValueSet);
    case R4ResourceType.VerificationResult:
      return (txn, resource) async =>
          saveVerificationResult(txn, resource as VerificationResult);
    case R4ResourceType.VisionPrescription:
      return (txn, resource) async =>
          saveVisionPrescription(txn, resource as VisionPrescription);
  }
}
