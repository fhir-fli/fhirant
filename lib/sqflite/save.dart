import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/sqflite/db.dart';
import 'package:sqflite/sqflite.dart';

Future<bool> Function(Database, Resource) saveFunction(
  R4ResourceType resourceType,
) {
  switch (resourceType) {
    case R4ResourceType.Account:
      return (db, resource) async => saveAccount(db, resource as Account);
    case R4ResourceType.ActivityDefinition:
      return (db, resource) async =>
          saveActivityDefinition(db, resource as ActivityDefinition);
    case R4ResourceType.AdministrableProductDefinition:
      return (db, resource) async => saveAdministrableProductDefinition(
            db,
            resource as AdministrableProductDefinition,
          );
    case R4ResourceType.AdverseEvent:
      return (db, resource) async =>
          saveAdverseEvent(db, resource as AdverseEvent);
    case R4ResourceType.AllergyIntolerance:
      return (db, resource) async =>
          saveAllergyIntolerance(db, resource as AllergyIntolerance);
    case R4ResourceType.Appointment:
      return (db, resource) async =>
          saveAppointment(db, resource as Appointment);
    case R4ResourceType.AppointmentResponse:
      return (db, resource) async =>
          saveAppointmentResponse(db, resource as AppointmentResponse);
    case R4ResourceType.AuditEvent:
      return (db, resource) async => saveAuditEvent(db, resource as AuditEvent);
    case R4ResourceType.Basic:
      return (db, resource) async => saveBasic(db, resource as Basic);
    case R4ResourceType.Binary:
      return (db, resource) async => saveBinary(db, resource as Binary);
    case R4ResourceType.BiologicallyDerivedProduct:
      return (db, resource) async => saveBiologicallyDerivedProduct(
            db,
            resource as BiologicallyDerivedProduct,
          );
    case R4ResourceType.BodyStructure:
      return (db, resource) async =>
          saveBodyStructure(db, resource as BodyStructure);
    case R4ResourceType.Bundle:
      return (db, resource) async => saveBundle(db, resource as Bundle);
    case R4ResourceType.CapabilityStatement:
      return (db, resource) async =>
          saveCapabilityStatement(db, resource as CapabilityStatement);
    case R4ResourceType.CarePlan:
      return (db, resource) async => saveCarePlan(db, resource as CarePlan);
    case R4ResourceType.CareTeam:
      return (db, resource) async => saveCareTeam(db, resource as CareTeam);
    case R4ResourceType.CatalogEntry:
      return (db, resource) async =>
          saveCatalogEntry(db, resource as CatalogEntry);
    case R4ResourceType.ChargeItem:
      return (db, resource) async => saveChargeItem(db, resource as ChargeItem);
    case R4ResourceType.ChargeItemDefinition:
      return (db, resource) async =>
          saveChargeItemDefinition(db, resource as ChargeItemDefinition);
    case R4ResourceType.Citation:
      return (db, resource) async => saveCitation(db, resource as Citation);
    case R4ResourceType.Claim:
      return (db, resource) async => saveClaim(db, resource as Claim);
    case R4ResourceType.ClaimResponse:
      return (db, resource) async =>
          saveClaimResponse(db, resource as ClaimResponse);
    case R4ResourceType.ClinicalImpression:
      return (db, resource) async =>
          saveClinicalImpression(db, resource as ClinicalImpression);
    case R4ResourceType.ClinicalUseDefinition:
      return (db, resource) async =>
          saveClinicalUseDefinition(db, resource as ClinicalUseDefinition);
    case R4ResourceType.CodeSystem:
      return (db, resource) async => saveCodeSystem(db, resource as CodeSystem);
    case R4ResourceType.Communication:
      return (db, resource) async =>
          saveCommunication(db, resource as Communication);
    case R4ResourceType.CommunicationRequest:
      return (db, resource) async =>
          saveCommunicationRequest(db, resource as CommunicationRequest);
    case R4ResourceType.CompartmentDefinition:
      return (db, resource) async =>
          saveCompartmentDefinition(db, resource as CompartmentDefinition);
    case R4ResourceType.Composition:
      return (db, resource) async =>
          saveComposition(db, resource as Composition);
    case R4ResourceType.ConceptMap:
      return (db, resource) async => saveConceptMap(db, resource as ConceptMap);
    case R4ResourceType.Condition:
      return (db, resource) async => saveCondition(db, resource as Condition);
    case R4ResourceType.Consent:
      return (db, resource) async => saveConsent(db, resource as Consent);
    case R4ResourceType.Contract:
      return (db, resource) async => saveContract(db, resource as Contract);
    case R4ResourceType.Coverage:
      return (db, resource) async => saveCoverage(db, resource as Coverage);
    case R4ResourceType.CoverageEligibilityRequest:
      return (db, resource) async => saveCoverageEligibilityRequest(
            db,
            resource as CoverageEligibilityRequest,
          );
    case R4ResourceType.CoverageEligibilityResponse:
      return (db, resource) async => saveCoverageEligibilityResponse(
            db,
            resource as CoverageEligibilityResponse,
          );
    case R4ResourceType.DetectedIssue:
      return (db, resource) async =>
          saveDetectedIssue(db, resource as DetectedIssue);
    case R4ResourceType.Device:
      return (db, resource) async => saveDevice(db, resource as Device);
    case R4ResourceType.DeviceDefinition:
      return (db, resource) async =>
          saveDeviceDefinition(db, resource as DeviceDefinition);
    case R4ResourceType.DeviceMetric:
      return (db, resource) async =>
          saveDeviceMetric(db, resource as DeviceMetric);
    case R4ResourceType.DeviceRequest:
      return (db, resource) async =>
          saveDeviceRequest(db, resource as DeviceRequest);
    case R4ResourceType.DeviceUseStatement:
      return (db, resource) async =>
          saveDeviceUseStatement(db, resource as DeviceUseStatement);
    case R4ResourceType.DiagnosticReport:
      return (db, resource) async =>
          saveDiagnosticReport(db, resource as DiagnosticReport);
    case R4ResourceType.DocumentManifest:
      return (db, resource) async =>
          saveDocumentManifest(db, resource as DocumentManifest);
    case R4ResourceType.DocumentReference:
      return (db, resource) async =>
          saveDocumentReference(db, resource as DocumentReference);
    case R4ResourceType.Encounter:
      return (db, resource) async => saveEncounter(db, resource as Encounter);
    case R4ResourceType.FhirEndpoint:
      return (db, resource) async =>
          saveFhirEndpoint(db, resource as FhirEndpoint);
    case R4ResourceType.EnrollmentRequest:
      return (db, resource) async =>
          saveEnrollmentRequest(db, resource as EnrollmentRequest);
    case R4ResourceType.EnrollmentResponse:
      return (db, resource) async =>
          saveEnrollmentResponse(db, resource as EnrollmentResponse);
    case R4ResourceType.EpisodeOfCare:
      return (db, resource) async =>
          saveEpisodeOfCare(db, resource as EpisodeOfCare);
    case R4ResourceType.EventDefinition:
      return (db, resource) async =>
          saveEventDefinition(db, resource as EventDefinition);
    case R4ResourceType.Evidence:
      return (db, resource) async => saveEvidence(db, resource as Evidence);
    case R4ResourceType.EvidenceReport:
      return (db, resource) async =>
          saveEvidenceReport(db, resource as EvidenceReport);
    case R4ResourceType.EvidenceVariable:
      return (db, resource) async =>
          saveEvidenceVariable(db, resource as EvidenceVariable);
    case R4ResourceType.ExampleScenario:
      return (db, resource) async =>
          saveExampleScenario(db, resource as ExampleScenario);
    case R4ResourceType.ExplanationOfBenefit:
      return (db, resource) async =>
          saveExplanationOfBenefit(db, resource as ExplanationOfBenefit);
    case R4ResourceType.FamilyMemberHistory:
      return (db, resource) async =>
          saveFamilyMemberHistory(db, resource as FamilyMemberHistory);
    case R4ResourceType.Flag:
      return (db, resource) async => saveFlag(db, resource as Flag);
    case R4ResourceType.Goal:
      return (db, resource) async => saveGoal(db, resource as Goal);
    case R4ResourceType.GraphDefinition:
      return (db, resource) async =>
          saveGraphDefinition(db, resource as GraphDefinition);
    case R4ResourceType.FhirGroup:
      return (db, resource) async => saveFhirGroup(db, resource as FhirGroup);
    case R4ResourceType.GuidanceResponse:
      return (db, resource) async =>
          saveGuidanceResponse(db, resource as GuidanceResponse);
    case R4ResourceType.HealthcareService:
      return (db, resource) async =>
          saveHealthcareService(db, resource as HealthcareService);
    case R4ResourceType.ImagingStudy:
      return (db, resource) async =>
          saveImagingStudy(db, resource as ImagingStudy);
    case R4ResourceType.Immunization:
      return (db, resource) async =>
          saveImmunization(db, resource as Immunization);
    case R4ResourceType.ImmunizationEvaluation:
      return (db, resource) async =>
          saveImmunizationEvaluation(db, resource as ImmunizationEvaluation);
    case R4ResourceType.ImmunizationRecommendation:
      return (db, resource) async => saveImmunizationRecommendation(
            db,
            resource as ImmunizationRecommendation,
          );
    case R4ResourceType.ImplementationGuide:
      return (db, resource) async =>
          saveImplementationGuide(db, resource as ImplementationGuide);
    case R4ResourceType.Ingredient:
      return (db, resource) async => saveIngredient(db, resource as Ingredient);
    case R4ResourceType.InsurancePlan:
      return (db, resource) async =>
          saveInsurancePlan(db, resource as InsurancePlan);
    case R4ResourceType.Invoice:
      return (db, resource) async => saveInvoice(db, resource as Invoice);
    case R4ResourceType.Library:
      return (db, resource) async => saveLibrary(db, resource as Library);
    case R4ResourceType.Linkage:
      return (db, resource) async => saveLinkage(db, resource as Linkage);
    case R4ResourceType.FhirList:
      return (db, resource) async => saveFhirList(db, resource as FhirList);
    case R4ResourceType.Location:
      return (db, resource) async => saveLocation(db, resource as Location);
    case R4ResourceType.ManufacturedItemDefinition:
      return (db, resource) async => saveManufacturedItemDefinition(
            db,
            resource as ManufacturedItemDefinition,
          );
    case R4ResourceType.Measure:
      return (db, resource) async => saveMeasure(db, resource as Measure);
    case R4ResourceType.MeasureReport:
      return (db, resource) async =>
          saveMeasureReport(db, resource as MeasureReport);
    case R4ResourceType.Media:
      return (db, resource) async => saveMedia(db, resource as Media);
    case R4ResourceType.Medication:
      return (db, resource) async => saveMedication(db, resource as Medication);
    case R4ResourceType.MedicationAdministration:
      return (db, resource) async => saveMedicationAdministration(
            db,
            resource as MedicationAdministration,
          );
    case R4ResourceType.MedicationDispense:
      return (db, resource) async =>
          saveMedicationDispense(db, resource as MedicationDispense);
    case R4ResourceType.MedicationKnowledge:
      return (db, resource) async =>
          saveMedicationKnowledge(db, resource as MedicationKnowledge);
    case R4ResourceType.MedicationRequest:
      return (db, resource) async =>
          saveMedicationRequest(db, resource as MedicationRequest);
    case R4ResourceType.MedicationStatement:
      return (db, resource) async =>
          saveMedicationStatement(db, resource as MedicationStatement);
    case R4ResourceType.MedicinalProductDefinition:
      return (db, resource) async => saveMedicinalProductDefinition(
            db,
            resource as MedicinalProductDefinition,
          );
    case R4ResourceType.MessageDefinition:
      return (db, resource) async =>
          saveMessageDefinition(db, resource as MessageDefinition);
    case R4ResourceType.MessageHeader:
      return (db, resource) async =>
          saveMessageHeader(db, resource as MessageHeader);
    case R4ResourceType.MolecularSequence:
      return (db, resource) async =>
          saveMolecularSequence(db, resource as MolecularSequence);
    case R4ResourceType.NamingSystem:
      return (db, resource) async =>
          saveNamingSystem(db, resource as NamingSystem);
    case R4ResourceType.NutritionOrder:
      return (db, resource) async =>
          saveNutritionOrder(db, resource as NutritionOrder);
    case R4ResourceType.NutritionProduct:
      return (db, resource) async =>
          saveNutritionProduct(db, resource as NutritionProduct);
    case R4ResourceType.Observation:
      return (db, resource) async =>
          saveObservation(db, resource as Observation);
    case R4ResourceType.ObservationDefinition:
      return (db, resource) async =>
          saveObservationDefinition(db, resource as ObservationDefinition);
    case R4ResourceType.OperationDefinition:
      return (db, resource) async =>
          saveOperationDefinition(db, resource as OperationDefinition);
    case R4ResourceType.OperationOutcome:
      return (db, resource) async =>
          saveOperationOutcome(db, resource as OperationOutcome);
    case R4ResourceType.Organization:
      return (db, resource) async =>
          saveOrganization(db, resource as Organization);
    case R4ResourceType.OrganizationAffiliation:
      return (db, resource) async => saveOrganizationAffiliation(
            db,
            resource as OrganizationAffiliation,
          );
    case R4ResourceType.PackagedProductDefinition:
      return (db, resource) async => savePackagedProductDefinition(
            db,
            resource as PackagedProductDefinition,
          );
    case R4ResourceType.Parameters:
      return (db, resource) async => saveParameters(db, resource as Parameters);
    case R4ResourceType.Patient:
      return (db, resource) async => savePatient(db, resource as Patient);
    case R4ResourceType.PaymentNotice:
      return (db, resource) async =>
          savePaymentNotice(db, resource as PaymentNotice);
    case R4ResourceType.PaymentReconciliation:
      return (db, resource) async =>
          savePaymentReconciliation(db, resource as PaymentReconciliation);
    case R4ResourceType.Person:
      return (db, resource) async => savePerson(db, resource as Person);
    case R4ResourceType.PlanDefinition:
      return (db, resource) async =>
          savePlanDefinition(db, resource as PlanDefinition);
    case R4ResourceType.Practitioner:
      return (db, resource) async =>
          savePractitioner(db, resource as Practitioner);
    case R4ResourceType.PractitionerRole:
      return (db, resource) async =>
          savePractitionerRole(db, resource as PractitionerRole);
    case R4ResourceType.Procedure:
      return (db, resource) async => saveProcedure(db, resource as Procedure);
    case R4ResourceType.Provenance:
      return (db, resource) async => saveProvenance(db, resource as Provenance);
    case R4ResourceType.Questionnaire:
      return (db, resource) async =>
          saveQuestionnaire(db, resource as Questionnaire);
    case R4ResourceType.QuestionnaireResponse:
      return (db, resource) async =>
          saveQuestionnaireResponse(db, resource as QuestionnaireResponse);
    case R4ResourceType.RegulatedAuthorization:
      return (db, resource) async =>
          saveRegulatedAuthorization(db, resource as RegulatedAuthorization);
    case R4ResourceType.RelatedPerson:
      return (db, resource) async =>
          saveRelatedPerson(db, resource as RelatedPerson);
    case R4ResourceType.RequestGroup:
      return (db, resource) async =>
          saveRequestGroup(db, resource as RequestGroup);
    case R4ResourceType.ResearchDefinition:
      return (db, resource) async =>
          saveResearchDefinition(db, resource as ResearchDefinition);
    case R4ResourceType.ResearchElementDefinition:
      return (db, resource) async => saveResearchElementDefinition(
            db,
            resource as ResearchElementDefinition,
          );
    case R4ResourceType.ResearchStudy:
      return (db, resource) async =>
          saveResearchStudy(db, resource as ResearchStudy);
    case R4ResourceType.ResearchSubject:
      return (db, resource) async =>
          saveResearchSubject(db, resource as ResearchSubject);
    case R4ResourceType.RiskAssessment:
      return (db, resource) async =>
          saveRiskAssessment(db, resource as RiskAssessment);
    case R4ResourceType.Schedule:
      return (db, resource) async => saveSchedule(db, resource as Schedule);
    case R4ResourceType.SearchParameter:
      return (db, resource) async =>
          saveSearchParameter(db, resource as SearchParameter);
    case R4ResourceType.ServiceRequest:
      return (db, resource) async =>
          saveServiceRequest(db, resource as ServiceRequest);
    case R4ResourceType.Slot:
      return (db, resource) async => saveSlot(db, resource as Slot);
    case R4ResourceType.Specimen:
      return (db, resource) async => saveSpecimen(db, resource as Specimen);
    case R4ResourceType.SpecimenDefinition:
      return (db, resource) async =>
          saveSpecimenDefinition(db, resource as SpecimenDefinition);
    case R4ResourceType.StructureDefinition:
      return (db, resource) async =>
          saveStructureDefinition(db, resource as StructureDefinition);
    case R4ResourceType.StructureMap:
      return (db, resource) async =>
          saveStructureMap(db, resource as StructureMap);
    case R4ResourceType.Subscription:
      return (db, resource) async =>
          saveSubscription(db, resource as Subscription);
    case R4ResourceType.SubscriptionStatus:
      return (db, resource) async =>
          saveSubscriptionStatus(db, resource as SubscriptionStatus);
    case R4ResourceType.SubscriptionTopic:
      return (db, resource) async =>
          saveSubscriptionTopic(db, resource as SubscriptionTopic);
    case R4ResourceType.Substance:
      return (db, resource) async => saveSubstance(db, resource as Substance);
    case R4ResourceType.SubstanceDefinition:
      return (db, resource) async =>
          saveSubstanceDefinition(db, resource as SubstanceDefinition);
    case R4ResourceType.SupplyDelivery:
      return (db, resource) async =>
          saveSupplyDelivery(db, resource as SupplyDelivery);
    case R4ResourceType.SupplyRequest:
      return (db, resource) async =>
          saveSupplyRequest(db, resource as SupplyRequest);
    case R4ResourceType.Task:
      return (db, resource) async => saveTask(db, resource as Task);
    case R4ResourceType.TerminologyCapabilities:
      return (db, resource) async => saveTerminologyCapabilities(
            db,
            resource as TerminologyCapabilities,
          );
    case R4ResourceType.TestReport:
      return (db, resource) async => saveTestReport(db, resource as TestReport);
    case R4ResourceType.TestScript:
      return (db, resource) async => saveTestScript(db, resource as TestScript);
    case R4ResourceType.ValueSet:
      return (db, resource) async => saveValueSet(db, resource as ValueSet);
    case R4ResourceType.VerificationResult:
      return (db, resource) async =>
          saveVerificationResult(db, resource as VerificationResult);
    case R4ResourceType.VisionPrescription:
      return (db, resource) async =>
          saveVisionPrescription(db, resource as VisionPrescription);
  }
}
