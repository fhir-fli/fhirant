import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db.dart';
import 'package:sqflite/sqflite.dart';

bool Function(Database, Resource) saveFunction(R4ResourceType resourceType) {
  switch (resourceType) {
    case R4ResourceType.Account:
      return (db, resource) => saveAccount(db, resource as Account);
    case R4ResourceType.ActivityDefinition:
      return (db, resource) =>
          saveActivityDefinition(db, resource as ActivityDefinition);
    case R4ResourceType.AdministrableProductDefinition:
      return (db, resource) => saveAdministrableProductDefinition(
            db,
            resource as AdministrableProductDefinition,
          );
    case R4ResourceType.AdverseEvent:
      return (db, resource) => saveAdverseEvent(db, resource as AdverseEvent);
    case R4ResourceType.AllergyIntolerance:
      return (db, resource) =>
          saveAllergyIntolerance(db, resource as AllergyIntolerance);
    case R4ResourceType.Appointment:
      return (db, resource) => saveAppointment(db, resource as Appointment);
    case R4ResourceType.AppointmentResponse:
      return (db, resource) =>
          saveAppointmentResponse(db, resource as AppointmentResponse);
    case R4ResourceType.AuditEvent:
      return (db, resource) => saveAuditEvent(db, resource as AuditEvent);
    case R4ResourceType.Basic:
      return (db, resource) => saveBasic(db, resource as Basic);
    case R4ResourceType.Binary:
      return (db, resource) => saveBinary(db, resource as Binary);
    case R4ResourceType.BiologicallyDerivedProduct:
      return (db, resource) => saveBiologicallyDerivedProduct(
            db,
            resource as BiologicallyDerivedProduct,
          );
    case R4ResourceType.BodyStructure:
      return (db, resource) => saveBodyStructure(db, resource as BodyStructure);
    case R4ResourceType.Bundle:
      return (db, resource) => saveBundle(db, resource as Bundle);
    case R4ResourceType.CapabilityStatement:
      return (db, resource) =>
          saveCapabilityStatement(db, resource as CapabilityStatement);
    case R4ResourceType.CarePlan:
      return (db, resource) => saveCarePlan(db, resource as CarePlan);
    case R4ResourceType.CareTeam:
      return (db, resource) => saveCareTeam(db, resource as CareTeam);
    case R4ResourceType.CatalogEntry:
      return (db, resource) => saveCatalogEntry(db, resource as CatalogEntry);
    case R4ResourceType.ChargeItem:
      return (db, resource) => saveChargeItem(db, resource as ChargeItem);
    case R4ResourceType.ChargeItemDefinition:
      return (db, resource) =>
          saveChargeItemDefinition(db, resource as ChargeItemDefinition);
    case R4ResourceType.Citation:
      return (db, resource) => saveCitation(db, resource as Citation);
    case R4ResourceType.Claim:
      return (db, resource) => saveClaim(db, resource as Claim);
    case R4ResourceType.ClaimResponse:
      return (db, resource) => saveClaimResponse(db, resource as ClaimResponse);
    case R4ResourceType.ClinicalImpression:
      return (db, resource) =>
          saveClinicalImpression(db, resource as ClinicalImpression);
    case R4ResourceType.ClinicalUseDefinition:
      return (db, resource) =>
          saveClinicalUseDefinition(db, resource as ClinicalUseDefinition);
    case R4ResourceType.CodeSystem:
      return (db, resource) => saveCodeSystem(db, resource as CodeSystem);
    case R4ResourceType.Communication:
      return (db, resource) => saveCommunication(db, resource as Communication);
    case R4ResourceType.CommunicationRequest:
      return (db, resource) =>
          saveCommunicationRequest(db, resource as CommunicationRequest);
    case R4ResourceType.CompartmentDefinition:
      return (db, resource) =>
          saveCompartmentDefinition(db, resource as CompartmentDefinition);
    case R4ResourceType.Composition:
      return (db, resource) => saveComposition(db, resource as Composition);
    case R4ResourceType.ConceptMap:
      return (db, resource) => saveConceptMap(db, resource as ConceptMap);
    case R4ResourceType.Condition:
      return (db, resource) => saveCondition(db, resource as Condition);
    case R4ResourceType.Consent:
      return (db, resource) => saveConsent(db, resource as Consent);
    case R4ResourceType.Contract:
      return (db, resource) => saveContract(db, resource as Contract);
    case R4ResourceType.Coverage:
      return (db, resource) => saveCoverage(db, resource as Coverage);
    case R4ResourceType.CoverageEligibilityRequest:
      return (db, resource) => saveCoverageEligibilityRequest(
            db,
            resource as CoverageEligibilityRequest,
          );
    case R4ResourceType.CoverageEligibilityResponse:
      return (db, resource) => saveCoverageEligibilityResponse(
            db,
            resource as CoverageEligibilityResponse,
          );
    case R4ResourceType.DetectedIssue:
      return (db, resource) => saveDetectedIssue(db, resource as DetectedIssue);
    case R4ResourceType.Device:
      return (db, resource) => saveDevice(db, resource as Device);
    case R4ResourceType.DeviceDefinition:
      return (db, resource) =>
          saveDeviceDefinition(db, resource as DeviceDefinition);
    case R4ResourceType.DeviceMetric:
      return (db, resource) => saveDeviceMetric(db, resource as DeviceMetric);
    case R4ResourceType.DeviceRequest:
      return (db, resource) => saveDeviceRequest(db, resource as DeviceRequest);
    case R4ResourceType.DeviceUseStatement:
      return (db, resource) =>
          saveDeviceUseStatement(db, resource as DeviceUseStatement);
    case R4ResourceType.DiagnosticReport:
      return (db, resource) =>
          saveDiagnosticReport(db, resource as DiagnosticReport);
    case R4ResourceType.DocumentManifest:
      return (db, resource) =>
          saveDocumentManifest(db, resource as DocumentManifest);
    case R4ResourceType.DocumentReference:
      return (db, resource) =>
          saveDocumentReference(db, resource as DocumentReference);
    case R4ResourceType.Encounter:
      return (db, resource) => saveEncounter(db, resource as Encounter);
    case R4ResourceType.FhirEndpoint:
      return (db, resource) => saveFhirEndpoint(db, resource as FhirEndpoint);
    case R4ResourceType.EnrollmentRequest:
      return (db, resource) =>
          saveEnrollmentRequest(db, resource as EnrollmentRequest);
    case R4ResourceType.EnrollmentResponse:
      return (db, resource) =>
          saveEnrollmentResponse(db, resource as EnrollmentResponse);
    case R4ResourceType.EpisodeOfCare:
      return (db, resource) => saveEpisodeOfCare(db, resource as EpisodeOfCare);
    case R4ResourceType.EventDefinition:
      return (db, resource) =>
          saveEventDefinition(db, resource as EventDefinition);
    case R4ResourceType.Evidence:
      return (db, resource) => saveEvidence(db, resource as Evidence);
    case R4ResourceType.EvidenceReport:
      return (db, resource) =>
          saveEvidenceReport(db, resource as EvidenceReport);
    case R4ResourceType.EvidenceVariable:
      return (db, resource) =>
          saveEvidenceVariable(db, resource as EvidenceVariable);
    case R4ResourceType.ExampleScenario:
      return (db, resource) =>
          saveExampleScenario(db, resource as ExampleScenario);
    case R4ResourceType.ExplanationOfBenefit:
      return (db, resource) =>
          saveExplanationOfBenefit(db, resource as ExplanationOfBenefit);
    case R4ResourceType.FamilyMemberHistory:
      return (db, resource) =>
          saveFamilyMemberHistory(db, resource as FamilyMemberHistory);
    case R4ResourceType.Flag:
      return (db, resource) => saveFlag(db, resource as Flag);
    case R4ResourceType.Goal:
      return (db, resource) => saveGoal(db, resource as Goal);
    case R4ResourceType.GraphDefinition:
      return (db, resource) =>
          saveGraphDefinition(db, resource as GraphDefinition);
    case R4ResourceType.FhirGroup:
      return (db, resource) => saveFhirGroup(db, resource as FhirGroup);
    case R4ResourceType.GuidanceResponse:
      return (db, resource) =>
          saveGuidanceResponse(db, resource as GuidanceResponse);
    case R4ResourceType.HealthcareService:
      return (db, resource) =>
          saveHealthcareService(db, resource as HealthcareService);
    case R4ResourceType.ImagingStudy:
      return (db, resource) => saveImagingStudy(db, resource as ImagingStudy);
    case R4ResourceType.Immunization:
      return (db, resource) => saveImmunization(db, resource as Immunization);
    case R4ResourceType.ImmunizationEvaluation:
      return (db, resource) =>
          saveImmunizationEvaluation(db, resource as ImmunizationEvaluation);
    case R4ResourceType.ImmunizationRecommendation:
      return (db, resource) => saveImmunizationRecommendation(
            db,
            resource as ImmunizationRecommendation,
          );
    case R4ResourceType.ImplementationGuide:
      return (db, resource) =>
          saveImplementationGuide(db, resource as ImplementationGuide);
    case R4ResourceType.Ingredient:
      return (db, resource) => saveIngredient(db, resource as Ingredient);
    case R4ResourceType.InsurancePlan:
      return (db, resource) => saveInsurancePlan(db, resource as InsurancePlan);
    case R4ResourceType.Invoice:
      return (db, resource) => saveInvoice(db, resource as Invoice);
    case R4ResourceType.Library:
      return (db, resource) => saveLibrary(db, resource as Library);
    case R4ResourceType.Linkage:
      return (db, resource) => saveLinkage(db, resource as Linkage);
    case R4ResourceType.FhirList:
      return (db, resource) => saveFhirList(db, resource as FhirList);
    case R4ResourceType.Location:
      return (db, resource) => saveLocation(db, resource as Location);
    case R4ResourceType.ManufacturedItemDefinition:
      return (db, resource) => saveManufacturedItemDefinition(
            db,
            resource as ManufacturedItemDefinition,
          );
    case R4ResourceType.Measure:
      return (db, resource) => saveMeasure(db, resource as Measure);
    case R4ResourceType.MeasureReport:
      return (db, resource) => saveMeasureReport(db, resource as MeasureReport);
    case R4ResourceType.Media:
      return (db, resource) => saveMedia(db, resource as Media);
    case R4ResourceType.Medication:
      return (db, resource) => saveMedication(db, resource as Medication);
    case R4ResourceType.MedicationAdministration:
      return (db, resource) => saveMedicationAdministration(
            db,
            resource as MedicationAdministration,
          );
    case R4ResourceType.MedicationDispense:
      return (db, resource) =>
          saveMedicationDispense(db, resource as MedicationDispense);
    case R4ResourceType.MedicationKnowledge:
      return (db, resource) =>
          saveMedicationKnowledge(db, resource as MedicationKnowledge);
    case R4ResourceType.MedicationRequest:
      return (db, resource) =>
          saveMedicationRequest(db, resource as MedicationRequest);
    case R4ResourceType.MedicationStatement:
      return (db, resource) =>
          saveMedicationStatement(db, resource as MedicationStatement);
    case R4ResourceType.MedicinalProductDefinition:
      return (db, resource) => saveMedicinalProductDefinition(
            db,
            resource as MedicinalProductDefinition,
          );
    case R4ResourceType.MessageDefinition:
      return (db, resource) =>
          saveMessageDefinition(db, resource as MessageDefinition);
    case R4ResourceType.MessageHeader:
      return (db, resource) => saveMessageHeader(db, resource as MessageHeader);
    case R4ResourceType.MolecularSequence:
      return (db, resource) =>
          saveMolecularSequence(db, resource as MolecularSequence);
    case R4ResourceType.NamingSystem:
      return (db, resource) => saveNamingSystem(db, resource as NamingSystem);
    case R4ResourceType.NutritionOrder:
      return (db, resource) =>
          saveNutritionOrder(db, resource as NutritionOrder);
    case R4ResourceType.NutritionProduct:
      return (db, resource) =>
          saveNutritionProduct(db, resource as NutritionProduct);
    case R4ResourceType.Observation:
      return (db, resource) => saveObservation(db, resource as Observation);
    case R4ResourceType.ObservationDefinition:
      return (db, resource) =>
          saveObservationDefinition(db, resource as ObservationDefinition);
    case R4ResourceType.OperationDefinition:
      return (db, resource) =>
          saveOperationDefinition(db, resource as OperationDefinition);
    case R4ResourceType.OperationOutcome:
      return (db, resource) =>
          saveOperationOutcome(db, resource as OperationOutcome);
    case R4ResourceType.Organization:
      return (db, resource) => saveOrganization(db, resource as Organization);
    case R4ResourceType.OrganizationAffiliation:
      return (db, resource) => saveOrganizationAffiliation(
            db,
            resource as OrganizationAffiliation,
          );
    case R4ResourceType.PackagedProductDefinition:
      return (db, resource) => savePackagedProductDefinition(
            db,
            resource as PackagedProductDefinition,
          );
    case R4ResourceType.Parameters:
      return (db, resource) => saveParameters(db, resource as Parameters);
    case R4ResourceType.Patient:
      return (db, resource) => savePatient(db, resource as Patient);
    case R4ResourceType.PaymentNotice:
      return (db, resource) => savePaymentNotice(db, resource as PaymentNotice);
    case R4ResourceType.PaymentReconciliation:
      return (db, resource) =>
          savePaymentReconciliation(db, resource as PaymentReconciliation);
    case R4ResourceType.Person:
      return (db, resource) => savePerson(db, resource as Person);
    case R4ResourceType.PlanDefinition:
      return (db, resource) =>
          savePlanDefinition(db, resource as PlanDefinition);
    case R4ResourceType.Practitioner:
      return (db, resource) => savePractitioner(db, resource as Practitioner);
    case R4ResourceType.PractitionerRole:
      return (db, resource) =>
          savePractitionerRole(db, resource as PractitionerRole);
    case R4ResourceType.Procedure:
      return (db, resource) => saveProcedure(db, resource as Procedure);
    case R4ResourceType.Provenance:
      return (db, resource) => saveProvenance(db, resource as Provenance);
    case R4ResourceType.Questionnaire:
      return (db, resource) => saveQuestionnaire(db, resource as Questionnaire);
    case R4ResourceType.QuestionnaireResponse:
      return (db, resource) =>
          saveQuestionnaireResponse(db, resource as QuestionnaireResponse);
    case R4ResourceType.RegulatedAuthorization:
      return (db, resource) =>
          saveRegulatedAuthorization(db, resource as RegulatedAuthorization);
    case R4ResourceType.RelatedPerson:
      return (db, resource) => saveRelatedPerson(db, resource as RelatedPerson);
    case R4ResourceType.RequestGroup:
      return (db, resource) => saveRequestGroup(db, resource as RequestGroup);
    case R4ResourceType.ResearchDefinition:
      return (db, resource) =>
          saveResearchDefinition(db, resource as ResearchDefinition);
    case R4ResourceType.ResearchElementDefinition:
      return (db, resource) => saveResearchElementDefinition(
            db,
            resource as ResearchElementDefinition,
          );
    case R4ResourceType.ResearchStudy:
      return (db, resource) => saveResearchStudy(db, resource as ResearchStudy);
    case R4ResourceType.ResearchSubject:
      return (db, resource) =>
          saveResearchSubject(db, resource as ResearchSubject);
    case R4ResourceType.RiskAssessment:
      return (db, resource) =>
          saveRiskAssessment(db, resource as RiskAssessment);
    case R4ResourceType.Schedule:
      return (db, resource) => saveSchedule(db, resource as Schedule);
    case R4ResourceType.SearchParameter:
      return (db, resource) =>
          saveSearchParameter(db, resource as SearchParameter);
    case R4ResourceType.ServiceRequest:
      return (db, resource) =>
          saveServiceRequest(db, resource as ServiceRequest);
    case R4ResourceType.Slot:
      return (db, resource) => saveSlot(db, resource as Slot);
    case R4ResourceType.Specimen:
      return (db, resource) => saveSpecimen(db, resource as Specimen);
    case R4ResourceType.SpecimenDefinition:
      return (db, resource) =>
          saveSpecimenDefinition(db, resource as SpecimenDefinition);
    case R4ResourceType.StructureDefinition:
      return (db, resource) =>
          saveStructureDefinition(db, resource as StructureDefinition);
    case R4ResourceType.StructureMap:
      return (db, resource) => saveStructureMap(db, resource as StructureMap);
    case R4ResourceType.Subscription:
      return (db, resource) => saveSubscription(db, resource as Subscription);
    case R4ResourceType.SubscriptionStatus:
      return (db, resource) =>
          saveSubscriptionStatus(db, resource as SubscriptionStatus);
    case R4ResourceType.SubscriptionTopic:
      return (db, resource) =>
          saveSubscriptionTopic(db, resource as SubscriptionTopic);
    case R4ResourceType.Substance:
      return (db, resource) => saveSubstance(db, resource as Substance);
    case R4ResourceType.SubstanceDefinition:
      return (db, resource) =>
          saveSubstanceDefinition(db, resource as SubstanceDefinition);
    case R4ResourceType.SupplyDelivery:
      return (db, resource) =>
          saveSupplyDelivery(db, resource as SupplyDelivery);
    case R4ResourceType.SupplyRequest:
      return (db, resource) => saveSupplyRequest(db, resource as SupplyRequest);
    case R4ResourceType.Task:
      return (db, resource) => saveTask(db, resource as Task);
    case R4ResourceType.TerminologyCapabilities:
      return (db, resource) => saveTerminologyCapabilities(
            db,
            resource as TerminologyCapabilities,
          );
    case R4ResourceType.TestReport:
      return (db, resource) => saveTestReport(db, resource as TestReport);
    case R4ResourceType.TestScript:
      return (db, resource) => saveTestScript(db, resource as TestScript);
    case R4ResourceType.ValueSet:
      return (db, resource) => saveValueSet(db, resource as ValueSet);
    case R4ResourceType.VerificationResult:
      return (db, resource) =>
          saveVerificationResult(db, resource as VerificationResult);
    case R4ResourceType.VisionPrescription:
      return (db, resource) =>
          saveVisionPrescription(db, resource as VisionPrescription);
  }
}
