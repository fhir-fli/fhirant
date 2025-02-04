// ignore_for_file: lines_longer_than_80_chars, avoid_print
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant/fhirant.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

part 'app_database.g.dart';

@DriftDatabase(tables: tablesList)

/// Database for the application
class AppDatabase extends _$AppDatabase {
  /// Creates an instance of the database
  AppDatabase() : super(_openConnection());

  /// Named constructor for testing.
  AppDatabase.forTesting(super.e);

  /// Default database version for migrations
  @override
  int get schemaVersion => 1;

  /// Secure Storage Service instance
  static final SecureStorageService _secureStorageService =
      SecureStorageService();

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      // 1. Get the correct directory for storing databases on Android (or iOS).
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(dir.path, 'fhirant.db');

      // 2. Ensure SQLCipher is set up
      await setupSqlCipher();

      // 3. Retrieve the encryption key
      final encryptionKey = await _secureStorageService.getEncryptionKey();
      if (encryptionKey == null) {
        throw Exception('Failed to retrieve encryption key.');
      }

      // 4. Initialize the encrypted database
      return NativeDatabase(
        File(dbPath),
        setup: (rawDb) {
          rawDb.execute('PRAGMA key = "$encryptionKey";');

          // Recommended SQLCipher setting
          rawDb.config.doubleQuotedStringLiterals = false;

          // Debug check to ensure SQLCipher is working
          assert(
            _debugCheckHasCipher(rawDb),
            'SQLCipher encryption is not enabled. Verify the setup.',
          );
        },
      );
    });
  }

  /// Debug check to ensure SQLCipher is available
  static bool _debugCheckHasCipher(sqlite3.Database database) {
    try {
      return database.select('PRAGMA cipher_version;').isNotEmpty;
    } catch (e) {
      print('SQLCipher not available: $e');
      return false;
    }
  }

  /// Save multiple FHIR resources into the database with history management.
  Future<bool> saveResources(List<fhir.Resource> resources) async {
    if (resources.isEmpty) {
      print('No resources to save.');
      return true;
    }

    // Group resources by their type
    final groupedResources = <fhir.R4ResourceType, List<fhir.Resource>>{};
    for (final resource in resources) {
      final type = resource.resourceType;
      groupedResources.putIfAbsent(type, () => []).add(resource);
    }

    var totalErrors = 0;

    try {
      await batch((batch) async {
        // Save each resource group into its respective table
        for (final entry in groupedResources.entries) {
          final type = entry.key;
          final resourceList = entry.value;

          for (final resource in resourceList) {
            try {
              _saveResourceWithHistory(
                batch,
                type,
                resource.newIdIfNoId().updateVersion(versionIdAsTime: true),
              );
            } catch (e, s) {
              totalErrors++;
              // Log the specific resource that failed to save
              print(
                'Error saving resource of type $type with ID: ${resource.id?.value}: $e',
              );
              print('\n\n');
              print('Stack trace: $s');
              rethrow;
            }
          }
        }
      });

      print('Successfully saved ${resources.length} resource(s).');
      print('Total errors: $totalErrors');
      return true;
    } catch (e) {
      print('Batch execution failed: $e');
      print('Total errors: $totalErrors');
      return false;
    }
  }

  /// Save a resource with history management
  void _saveResourceWithHistory(
    Batch batch,
    fhir.R4ResourceType resourceType,
    fhir.Resource resource,
  ) {
    switch (resourceType) {
      case fhir.R4ResourceType.Account:
        final companion = (resource as fhir.Account).companion;
        batch
          ..insert(accountHistoryTable, companion.companion)
          ..insert(accountTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.ActivityDefinition:
        final companion = (resource as fhir.ActivityDefinition).companion;
        batch
          ..insert(activityDefinitionHistoryTable, companion.companion)
          ..insert(
            activityDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.AdministrableProductDefinition:
        final companion =
            (resource as fhir.AdministrableProductDefinition).companion;
        batch
          ..insert(
            administrableProductDefinitionHistoryTable,
            companion.companion,
          )
          ..insert(
            administrableProductDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.AdverseEvent:
        final companion = (resource as fhir.AdverseEvent).companion;
        batch
          ..insert(adverseEventHistoryTable, companion.companion)
          ..insert(
            adverseEventTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.AllergyIntolerance:
        final companion = (resource as fhir.AllergyIntolerance).companion;
        batch
          ..insert(allergyIntoleranceHistoryTable, companion.companion)
          ..insert(
            allergyIntoleranceTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Appointment:
        final companion = (resource as fhir.Appointment).companion;
        batch
          ..insert(appointmentHistoryTable, companion.companion)
          ..insert(
            appointmentTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.AppointmentResponse:
        final companion = (resource as fhir.AppointmentResponse).companion;
        batch
          ..insert(appointmentResponseHistoryTable, companion.companion)
          ..insert(
            appointmentResponseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.AuditEvent:
        final companion = (resource as fhir.AuditEvent).companion;
        batch
          ..insert(auditEventHistoryTable, companion.companion)
          ..insert(
            auditEventTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Basic:
        final companion = (resource as fhir.Basic).companion;
        batch
          ..insert(basicHistoryTable, companion.companion)
          ..insert(basicTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Binary:
        final companion = (resource as fhir.Binary).companion;
        batch
          ..insert(binaryHistoryTable, companion.companion)
          ..insert(binaryTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.BiologicallyDerivedProduct:
        final companion =
            (resource as fhir.BiologicallyDerivedProduct).companion;
        batch
          ..insert(biologicallyDerivedProductHistoryTable, companion.companion)
          ..insert(
            biologicallyDerivedProductTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.BodyStructure:
        final companion = (resource as fhir.BodyStructure).companion;
        batch
          ..insert(bodyStructureHistoryTable, companion.companion)
          ..insert(
            bodyStructureTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Bundle:
        final companion = (resource as fhir.Bundle).companion;
        batch
          ..insert(bundleHistoryTable, companion.companion)
          ..insert(bundleTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.CapabilityStatement:
        final companion = (resource as fhir.CapabilityStatement).companion;
        batch
          ..insert(capabilityStatementHistoryTable, companion.companion)
          ..insert(
            capabilityStatementTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.CarePlan:
        final companion = (resource as fhir.CarePlan).companion;
        batch
          ..insert(carePlanHistoryTable, companion.companion)
          ..insert(carePlanTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.CareTeam:
        final companion = (resource as fhir.CareTeam).companion;
        batch
          ..insert(careTeamHistoryTable, companion.companion)
          ..insert(careTeamTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.CatalogEntry:
        final companion = (resource as fhir.CatalogEntry).companion;
        batch
          ..insert(catalogEntryHistoryTable, companion.companion)
          ..insert(
            catalogEntryTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ChargeItem:
        final companion = (resource as fhir.ChargeItem).companion;
        batch
          ..insert(chargeItemHistoryTable, companion.companion)
          ..insert(
            chargeItemTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ChargeItemDefinition:
        final companion = (resource as fhir.ChargeItemDefinition).companion;
        batch
          ..insert(chargeItemDefinitionHistoryTable, companion.companion)
          ..insert(
            chargeItemDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Citation:
        final companion = (resource as fhir.Citation).companion;
        batch
          ..insert(citationHistoryTable, companion.companion)
          ..insert(citationTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Claim:
        final companion = (resource as fhir.Claim).companion;
        batch
          ..insert(claimHistoryTable, companion.companion)
          ..insert(claimTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.ClaimResponse:
        final companion = (resource as fhir.ClaimResponse).companion;
        batch
          ..insert(claimResponseHistoryTable, companion.companion)
          ..insert(
            claimResponseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ClinicalImpression:
        final companion = (resource as fhir.ClinicalImpression).companion;
        batch
          ..insert(clinicalImpressionHistoryTable, companion.companion)
          ..insert(
            clinicalImpressionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ClinicalUseDefinition:
        final companion = (resource as fhir.ClinicalUseDefinition).companion;
        batch
          ..insert(clinicalUseDefinitionHistoryTable, companion.companion)
          ..insert(
            clinicalUseDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.CodeSystem:
        final companion = (resource as fhir.CodeSystem).companion;
        batch
          ..insert(codeSystemHistoryTable, companion.companion)
          ..insert(
            codeSystemTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Communication:
        final companion = (resource as fhir.Communication).companion;
        batch
          ..insert(communicationHistoryTable, companion.companion)
          ..insert(
            communicationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.CommunicationRequest:
        final companion = (resource as fhir.CommunicationRequest).companion;
        batch
          ..insert(communicationRequestHistoryTable, companion.companion)
          ..insert(
            communicationRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.CompartmentDefinition:
        final companion = (resource as fhir.CompartmentDefinition).companion;
        batch
          ..insert(compartmentDefinitionHistoryTable, companion.companion)
          ..insert(
            compartmentDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Composition:
        final companion = (resource as fhir.Composition).companion;
        batch
          ..insert(compositionHistoryTable, companion.companion)
          ..insert(
            compositionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ConceptMap:
        final companion = (resource as fhir.ConceptMap).companion;
        batch
          ..insert(conceptMapHistoryTable, companion.companion)
          ..insert(
            conceptMapTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Condition:
        final companion = (resource as fhir.Condition).companion;
        batch
          ..insert(conditionHistoryTable, companion.companion)
          ..insert(conditionTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Consent:
        final companion = (resource as fhir.Consent).companion;
        batch
          ..insert(consentHistoryTable, companion.companion)
          ..insert(consentTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Contract:
        final companion = (resource as fhir.Contract).companion;
        batch
          ..insert(contractHistoryTable, companion.companion)
          ..insert(contractTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Coverage:
        final companion = (resource as fhir.Coverage).companion;
        batch
          ..insert(coverageHistoryTable, companion.companion)
          ..insert(coverageTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.CoverageEligibilityRequest:
        final companion =
            (resource as fhir.CoverageEligibilityRequest).companion;
        batch
          ..insert(coverageEligibilityRequestHistoryTable, companion.companion)
          ..insert(
            coverageEligibilityRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.CoverageEligibilityResponse:
        final companion =
            (resource as fhir.CoverageEligibilityResponse).companion;
        batch
          ..insert(coverageEligibilityResponseHistoryTable, companion.companion)
          ..insert(
            coverageEligibilityResponseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DetectedIssue:
        final companion = (resource as fhir.DetectedIssue).companion;
        batch
          ..insert(detectedIssueHistoryTable, companion.companion)
          ..insert(
            detectedIssueTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Device:
        final companion = (resource as fhir.Device).companion;
        batch
          ..insert(deviceHistoryTable, companion.companion)
          ..insert(deviceTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.DeviceDefinition:
        final companion = (resource as fhir.DeviceDefinition).companion;
        batch
          ..insert(deviceDefinitionHistoryTable, companion.companion)
          ..insert(
            deviceDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DeviceMetric:
        final companion = (resource as fhir.DeviceMetric).companion;
        batch
          ..insert(deviceMetricHistoryTable, companion.companion)
          ..insert(
            deviceMetricTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DeviceRequest:
        final companion = (resource as fhir.DeviceRequest).companion;
        batch
          ..insert(deviceRequestHistoryTable, companion.companion)
          ..insert(
            deviceRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DeviceUseStatement:
        final companion = (resource as fhir.DeviceUseStatement).companion;
        batch
          ..insert(deviceUseStatementHistoryTable, companion.companion)
          ..insert(
            deviceUseStatementTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DiagnosticReport:
        final companion = (resource as fhir.DiagnosticReport).companion;
        batch
          ..insert(diagnosticReportHistoryTable, companion.companion)
          ..insert(
            diagnosticReportTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DocumentManifest:
        final companion = (resource as fhir.DocumentManifest).companion;
        batch
          ..insert(documentManifestHistoryTable, companion.companion)
          ..insert(
            documentManifestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.DocumentReference:
        final companion = (resource as fhir.DocumentReference).companion;
        batch
          ..insert(documentReferenceHistoryTable, companion.companion)
          ..insert(
            documentReferenceTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Encounter:
        final companion = (resource as fhir.Encounter).companion;
        batch
          ..insert(encounterHistoryTable, companion.companion)
          ..insert(encounterTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.EnrollmentRequest:
        final companion = (resource as fhir.EnrollmentRequest).companion;
        batch
          ..insert(enrollmentRequestHistoryTable, companion.companion)
          ..insert(
            enrollmentRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.EnrollmentResponse:
        final companion = (resource as fhir.EnrollmentResponse).companion;
        batch
          ..insert(enrollmentResponseHistoryTable, companion.companion)
          ..insert(
            enrollmentResponseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.EpisodeOfCare:
        final companion = (resource as fhir.EpisodeOfCare).companion;
        batch
          ..insert(episodeOfCareHistoryTable, companion.companion)
          ..insert(
            episodeOfCareTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.EventDefinition:
        final companion = (resource as fhir.EventDefinition).companion;
        batch
          ..insert(eventDefinitionHistoryTable, companion.companion)
          ..insert(
            eventDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Evidence:
        final companion = (resource as fhir.Evidence).companion;
        batch
          ..insert(evidenceHistoryTable, companion.companion)
          ..insert(evidenceTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.EvidenceReport:
        final companion = (resource as fhir.EvidenceReport).companion;
        batch
          ..insert(evidenceReportHistoryTable, companion.companion)
          ..insert(
            evidenceReportTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.EvidenceVariable:
        final companion = (resource as fhir.EvidenceVariable).companion;
        batch
          ..insert(evidenceVariableHistoryTable, companion.companion)
          ..insert(
            evidenceVariableTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ExampleScenario:
        final companion = (resource as fhir.ExampleScenario).companion;
        batch
          ..insert(exampleScenarioHistoryTable, companion.companion)
          ..insert(
            exampleScenarioTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ExplanationOfBenefit:
        final companion = (resource as fhir.ExplanationOfBenefit).companion;
        batch
          ..insert(explanationOfBenefitHistoryTable, companion.companion)
          ..insert(
            explanationOfBenefitTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.FamilyMemberHistory:
        final companion = (resource as fhir.FamilyMemberHistory).companion;
        batch
          ..insert(familyMemberHistoryHistoryTable, companion.companion)
          ..insert(
            familyMemberHistoryTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.FhirEndpoint:
        final companion = (resource as fhir.FhirEndpoint).companion;
        batch
          ..insert(fhirEndpointHistoryTable, companion.companion)
          ..insert(
            fhirEndpointTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.FhirGroup:
        final companion = (resource as fhir.FhirGroup).companion;
        batch
          ..insert(fhirGroupHistoryTable, companion.companion)
          ..insert(fhirGroupTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.FhirList:
        final companion = (resource as fhir.FhirList).companion;
        batch
          ..insert(fhirListHistoryTable, companion.companion)
          ..insert(fhirListTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Flag:
        final companion = (resource as fhir.Flag).companion;
        batch
          ..insert(flagHistoryTable, companion.companion)
          ..insert(flagTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Goal:
        final companion = (resource as fhir.Goal).companion;
        batch
          ..insert(goalHistoryTable, companion.companion)
          ..insert(goalTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.GraphDefinition:
        final companion = (resource as fhir.GraphDefinition).companion;
        batch
          ..insert(graphDefinitionHistoryTable, companion.companion)
          ..insert(
            graphDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.GuidanceResponse:
        final companion = (resource as fhir.GuidanceResponse).companion;
        batch
          ..insert(guidanceResponseHistoryTable, companion.companion)
          ..insert(
            guidanceResponseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.HealthcareService:
        final companion = (resource as fhir.HealthcareService).companion;
        batch
          ..insert(healthcareServiceHistoryTable, companion.companion)
          ..insert(
            healthcareServiceTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ImagingStudy:
        final companion = (resource as fhir.ImagingStudy).companion;
        batch
          ..insert(imagingStudyHistoryTable, companion.companion)
          ..insert(
            imagingStudyTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Immunization:
        final companion = (resource as fhir.Immunization).companion;
        batch
          ..insert(immunizationHistoryTable, companion.companion)
          ..insert(
            immunizationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ImmunizationEvaluation:
        final companion = (resource as fhir.ImmunizationEvaluation).companion;
        batch
          ..insert(immunizationEvaluationHistoryTable, companion.companion)
          ..insert(
            immunizationEvaluationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ImmunizationRecommendation:
        final companion =
            (resource as fhir.ImmunizationRecommendation).companion;
        batch
          ..insert(immunizationRecommendationHistoryTable, companion.companion)
          ..insert(
            immunizationRecommendationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ImplementationGuide:
        final companion = (resource as fhir.ImplementationGuide).companion;
        batch
          ..insert(implementationGuideHistoryTable, companion.companion)
          ..insert(
            implementationGuideTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Ingredient:
        final companion = (resource as fhir.Ingredient).companion;
        batch
          ..insert(ingredientHistoryTable, companion.companion)
          ..insert(
            ingredientTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.InsurancePlan:
        final companion = (resource as fhir.InsurancePlan).companion;
        batch
          ..insert(insurancePlanHistoryTable, companion.companion)
          ..insert(
            insurancePlanTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Invoice:
        final companion = (resource as fhir.Invoice).companion;
        batch
          ..insert(invoiceHistoryTable, companion.companion)
          ..insert(invoiceTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Library:
        final companion = (resource as fhir.Library).companion;
        batch
          ..insert(libraryHistoryTable, companion.companion)
          ..insert(libraryTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Linkage:
        final companion = (resource as fhir.Linkage).companion;
        batch
          ..insert(linkageHistoryTable, companion.companion)
          ..insert(linkageTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Location:
        final companion = (resource as fhir.Location).companion;
        batch
          ..insert(locationHistoryTable, companion.companion)
          ..insert(locationTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.ManufacturedItemDefinition:
        final companion =
            (resource as fhir.ManufacturedItemDefinition).companion;
        batch
          ..insert(manufacturedItemDefinitionHistoryTable, companion.companion)
          ..insert(
            manufacturedItemDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Measure:
        final companion = (resource as fhir.Measure).companion;
        batch
          ..insert(measureHistoryTable, companion.companion)
          ..insert(measureTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.MeasureReport:
        final companion = (resource as fhir.MeasureReport).companion;
        batch
          ..insert(measureReportHistoryTable, companion.companion)
          ..insert(
            measureReportTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Media:
        final companion = (resource as fhir.Media).companion;
        batch
          ..insert(mediaHistoryTable, companion.companion)
          ..insert(mediaTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Medication:
        final companion = (resource as fhir.Medication).companion;
        batch
          ..insert(medicationHistoryTable, companion.companion)
          ..insert(
            medicationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MedicationAdministration:
        final companion = (resource as fhir.MedicationAdministration).companion;
        batch
          ..insert(medicationAdministrationHistoryTable, companion.companion)
          ..insert(
            medicationAdministrationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MedicationDispense:
        final companion = (resource as fhir.MedicationDispense).companion;
        batch
          ..insert(medicationDispenseHistoryTable, companion.companion)
          ..insert(
            medicationDispenseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MedicationKnowledge:
        final companion = (resource as fhir.MedicationKnowledge).companion;
        batch
          ..insert(medicationKnowledgeHistoryTable, companion.companion)
          ..insert(
            medicationKnowledgeTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MedicationRequest:
        final companion = (resource as fhir.MedicationRequest).companion;
        batch
          ..insert(medicationRequestHistoryTable, companion.companion)
          ..insert(
            medicationRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MedicationStatement:
        final companion = (resource as fhir.MedicationStatement).companion;
        batch
          ..insert(medicationStatementHistoryTable, companion.companion)
          ..insert(
            medicationStatementTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MedicinalProductDefinition:
        final companion =
            (resource as fhir.MedicinalProductDefinition).companion;
        batch
          ..insert(medicinalProductDefinitionHistoryTable, companion.companion)
          ..insert(
            medicinalProductDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MessageDefinition:
        final companion = (resource as fhir.MessageDefinition).companion;
        batch
          ..insert(messageDefinitionHistoryTable, companion.companion)
          ..insert(
            messageDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MessageHeader:
        final companion = (resource as fhir.MessageHeader).companion;
        batch
          ..insert(messageHeaderHistoryTable, companion.companion)
          ..insert(
            messageHeaderTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.MolecularSequence:
        final companion = (resource as fhir.MolecularSequence).companion;
        batch
          ..insert(molecularSequenceHistoryTable, companion.companion)
          ..insert(
            molecularSequenceTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.NamingSystem:
        final companion = (resource as fhir.NamingSystem).companion;
        batch
          ..insert(namingSystemHistoryTable, companion.companion)
          ..insert(
            namingSystemTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.NutritionOrder:
        final companion = (resource as fhir.NutritionOrder).companion;
        batch
          ..insert(nutritionOrderHistoryTable, companion.companion)
          ..insert(
            nutritionOrderTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.NutritionProduct:
        final companion = (resource as fhir.NutritionProduct).companion;
        batch
          ..insert(nutritionProductHistoryTable, companion.companion)
          ..insert(
            nutritionProductTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Observation:
        final companion = (resource as fhir.Observation).companion;
        batch
          ..insert(observationHistoryTable, companion.companion)
          ..insert(
            observationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ObservationDefinition:
        final companion = (resource as fhir.ObservationDefinition).companion;
        batch
          ..insert(observationDefinitionHistoryTable, companion.companion)
          ..insert(
            observationDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.OperationDefinition:
        final companion = (resource as fhir.OperationDefinition).companion;
        batch
          ..insert(operationDefinitionHistoryTable, companion.companion)
          ..insert(
            operationDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.OperationOutcome:
        final companion = (resource as fhir.OperationOutcome).companion;
        batch
          ..insert(operationOutcomeHistoryTable, companion.companion)
          ..insert(
            operationOutcomeTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Organization:
        final companion = (resource as fhir.Organization).companion;
        batch
          ..insert(organizationHistoryTable, companion.companion)
          ..insert(
            organizationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.OrganizationAffiliation:
        final companion = (resource as fhir.OrganizationAffiliation).companion;
        batch
          ..insert(organizationAffiliationHistoryTable, companion.companion)
          ..insert(
            organizationAffiliationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.PackagedProductDefinition:
        final companion =
            (resource as fhir.PackagedProductDefinition).companion;
        batch
          ..insert(packagedProductDefinitionHistoryTable, companion.companion)
          ..insert(
            packagedProductDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Parameters:
        final companion = (resource as fhir.Parameters).companion;
        batch
          ..insert(parametersHistoryTable, companion.companion)
          ..insert(
            parametersTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Patient:
        final companion = (resource as fhir.Patient).companion;
        batch
          ..insert(patientHistoryTable, companion.companion)
          ..insert(patientTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.PaymentNotice:
        final companion = (resource as fhir.PaymentNotice).companion;
        batch
          ..insert(paymentNoticeHistoryTable, companion.companion)
          ..insert(
            paymentNoticeTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.PaymentReconciliation:
        final companion = (resource as fhir.PaymentReconciliation).companion;
        batch
          ..insert(paymentReconciliationHistoryTable, companion.companion)
          ..insert(
            paymentReconciliationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Person:
        final companion = (resource as fhir.Person).companion;
        batch
          ..insert(personHistoryTable, companion.companion)
          ..insert(personTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.PlanDefinition:
        final companion = (resource as fhir.PlanDefinition).companion;
        batch
          ..insert(planDefinitionHistoryTable, companion.companion)
          ..insert(
            planDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Practitioner:
        final companion = (resource as fhir.Practitioner).companion;
        batch
          ..insert(practitionerHistoryTable, companion.companion)
          ..insert(
            practitionerTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.PractitionerRole:
        final companion = (resource as fhir.PractitionerRole).companion;
        batch
          ..insert(practitionerRoleHistoryTable, companion.companion)
          ..insert(
            practitionerRoleTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Procedure:
        final companion = (resource as fhir.Procedure).companion;
        batch
          ..insert(procedureHistoryTable, companion.companion)
          ..insert(procedureTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Provenance:
        final companion = (resource as fhir.Provenance).companion;
        batch
          ..insert(provenanceHistoryTable, companion.companion)
          ..insert(
            provenanceTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Questionnaire:
        final companion = (resource as fhir.Questionnaire).companion;
        batch
          ..insert(questionnaireHistoryTable, companion.companion)
          ..insert(
            questionnaireTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.QuestionnaireResponse:
        final companion = (resource as fhir.QuestionnaireResponse).companion;
        batch
          ..insert(questionnaireResponseHistoryTable, companion.companion)
          ..insert(
            questionnaireResponseTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.RegulatedAuthorization:
        final companion = (resource as fhir.RegulatedAuthorization).companion;
        batch
          ..insert(regulatedAuthorizationHistoryTable, companion.companion)
          ..insert(
            regulatedAuthorizationTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.RelatedPerson:
        final companion = (resource as fhir.RelatedPerson).companion;
        batch
          ..insert(relatedPersonHistoryTable, companion.companion)
          ..insert(
            relatedPersonTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.RequestGroup:
        final companion = (resource as fhir.RequestGroup).companion;
        batch
          ..insert(requestGroupHistoryTable, companion.companion)
          ..insert(
            requestGroupTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ResearchDefinition:
        final companion = (resource as fhir.ResearchDefinition).companion;
        batch
          ..insert(researchDefinitionHistoryTable, companion.companion)
          ..insert(
            researchDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ResearchElementDefinition:
        final companion =
            (resource as fhir.ResearchElementDefinition).companion;
        batch
          ..insert(researchElementDefinitionHistoryTable, companion.companion)
          ..insert(
            researchElementDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ResearchStudy:
        final companion = (resource as fhir.ResearchStudy).companion;
        batch
          ..insert(researchStudyHistoryTable, companion.companion)
          ..insert(
            researchStudyTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ResearchSubject:
        final companion = (resource as fhir.ResearchSubject).companion;
        batch
          ..insert(researchSubjectHistoryTable, companion.companion)
          ..insert(
            researchSubjectTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.RiskAssessment:
        final companion = (resource as fhir.RiskAssessment).companion;
        batch
          ..insert(riskAssessmentHistoryTable, companion.companion)
          ..insert(
            riskAssessmentTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Schedule:
        final companion = (resource as fhir.Schedule).companion;
        batch
          ..insert(scheduleHistoryTable, companion.companion)
          ..insert(scheduleTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.SearchParameter:
        final companion = (resource as fhir.SearchParameter).companion;
        batch
          ..insert(searchParameterHistoryTable, companion.companion)
          ..insert(
            searchParameterTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ServiceRequest:
        final companion = (resource as fhir.ServiceRequest).companion;
        batch
          ..insert(serviceRequestHistoryTable, companion.companion)
          ..insert(
            serviceRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Slot:
        final companion = (resource as fhir.Slot).companion;
        batch
          ..insert(slotHistoryTable, companion.companion)
          ..insert(slotTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.Specimen:
        final companion = (resource as fhir.Specimen).companion;
        batch
          ..insert(specimenHistoryTable, companion.companion)
          ..insert(specimenTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.SpecimenDefinition:
        final companion = (resource as fhir.SpecimenDefinition).companion;
        batch
          ..insert(specimenDefinitionHistoryTable, companion.companion)
          ..insert(
            specimenDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.StructureDefinition:
        final companion = (resource as fhir.StructureDefinition).companion;
        batch
          ..insert(structureDefinitionHistoryTable, companion.companion)
          ..insert(
            structureDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.StructureMap:
        final companion = (resource as fhir.StructureMap).companion;
        batch
          ..insert(structureMapHistoryTable, companion.companion)
          ..insert(
            structureMapTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Subscription:
        final companion = (resource as fhir.Subscription).companion;
        batch
          ..insert(subscriptionHistoryTable, companion.companion)
          ..insert(
            subscriptionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.SubscriptionStatus:
        final companion = (resource as fhir.SubscriptionStatus).companion;
        batch
          ..insert(subscriptionStatusHistoryTable, companion.companion)
          ..insert(
            subscriptionStatusTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.SubscriptionTopic:
        final companion = (resource as fhir.SubscriptionTopic).companion;
        batch
          ..insert(subscriptionTopicHistoryTable, companion.companion)
          ..insert(
            subscriptionTopicTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Substance:
        final companion = (resource as fhir.Substance).companion;
        batch
          ..insert(substanceHistoryTable, companion.companion)
          ..insert(substanceTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.SubstanceDefinition:
        final companion = (resource as fhir.SubstanceDefinition).companion;
        batch
          ..insert(substanceDefinitionHistoryTable, companion.companion)
          ..insert(
            substanceDefinitionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.SupplyDelivery:
        final companion = (resource as fhir.SupplyDelivery).companion;
        batch
          ..insert(supplyDeliveryHistoryTable, companion.companion)
          ..insert(
            supplyDeliveryTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.SupplyRequest:
        final companion = (resource as fhir.SupplyRequest).companion;
        batch
          ..insert(supplyRequestHistoryTable, companion.companion)
          ..insert(
            supplyRequestTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.Task:
        final companion = (resource as fhir.Task).companion;
        batch
          ..insert(taskHistoryTable, companion.companion)
          ..insert(taskTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.TerminologyCapabilities:
        final companion = (resource as fhir.TerminologyCapabilities).companion;
        batch
          ..insert(terminologyCapabilitiesHistoryTable, companion.companion)
          ..insert(
            terminologyCapabilitiesTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.TestReport:
        final companion = (resource as fhir.TestReport).companion;
        batch
          ..insert(testReportHistoryTable, companion.companion)
          ..insert(
            testReportTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.TestScript:
        final companion = (resource as fhir.TestScript).companion;
        batch
          ..insert(testScriptHistoryTable, companion.companion)
          ..insert(
            testScriptTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.ValueSet:
        final companion = (resource as fhir.ValueSet).companion;
        batch
          ..insert(valueSetHistoryTable, companion.companion)
          ..insert(valueSetTable, companion, mode: InsertMode.insertOrReplace);
      case fhir.R4ResourceType.VerificationResult:
        final companion = (resource as fhir.VerificationResult).companion;
        batch
          ..insert(verificationResultHistoryTable, companion.companion)
          ..insert(
            verificationResultTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
      case fhir.R4ResourceType.VisionPrescription:
        final companion = (resource as fhir.VisionPrescription).companion;
        batch
          ..insert(visionPrescriptionHistoryTable, companion.companion)
          ..insert(
            visionPrescriptionTable,
            companion,
            mode: InsertMode.insertOrReplace,
          );
    }
  }
}

/// Just to ensure it will allow us to call companion on all resources
extension ResourceExtension on fhir.Resource {
  /// TableCompanion
  UpdateCompanion<dynamic> get companion {
    throw UnimplementedError();
  }
}

/// DataClassExtension
extension UpdateCompantionExtension on UpdateCompanion<dynamic> {
  /// TableCompanion
  UpdateCompanion<dynamic> get companion {
    throw UnimplementedError();
  }
}

/// AccountTableExtension
extension AccountTableExtension on fhir.Account {
  /// AccountTableCompanion
  AccountTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AccountTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AccountHistoryTableExtension
extension AccountHistoryTableExtension on AccountTableCompanion {
  /// AccountHistoryTableCompanion
  AccountHistoryTableCompanion get companion {
    return AccountHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ActivityDefinitionTableExtension
extension ActivityDefinitionTableExtension on fhir.ActivityDefinition {
  /// ActivityDefinitionTableCompanion
  ActivityDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ActivityDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ActivityDefinitionHistoryTableExtension
extension ActivityDefinitionHistoryTableExtension
    on ActivityDefinitionTableCompanion {
  /// ActivityDefinitionHistoryTableCompanion
  ActivityDefinitionHistoryTableCompanion get companion {
    return ActivityDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// AdministrableProductDefinitionTableExtension
extension AdministrableProductDefinitionTableExtension
    on fhir.AdministrableProductDefinition {
  /// AdministrableProductDefinitionTableCompanion
  AdministrableProductDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AdministrableProductDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AdministrableProductDefinitionHistoryTableExtension
extension AdministrableProductDefinitionHistoryTableExtension
    on AdministrableProductDefinitionTableCompanion {
  /// AdministrableProductDefinitionHistoryTableCompanion
  AdministrableProductDefinitionHistoryTableCompanion get companion {
    return AdministrableProductDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// AdverseEventTableExtension
extension AdverseEventTableExtension on fhir.AdverseEvent {
  /// AdverseEventTableCompanion
  AdverseEventTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AdverseEventTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AdverseEventHistoryTableExtension
extension AdverseEventHistoryTableExtension on AdverseEventTableCompanion {
  /// AdverseEventHistoryTableCompanion
  AdverseEventHistoryTableCompanion get companion {
    return AdverseEventHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// AllergyIntoleranceTableExtension
extension AllergyIntoleranceTableExtension on fhir.AllergyIntolerance {
  /// AllergyIntoleranceTableCompanion
  AllergyIntoleranceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AllergyIntoleranceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AllergyIntoleranceHistoryTableExtension
extension AllergyIntoleranceHistoryTableExtension
    on AllergyIntoleranceTableCompanion {
  /// AllergyIntoleranceHistoryTableCompanion
  AllergyIntoleranceHistoryTableCompanion get companion {
    return AllergyIntoleranceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// AppointmentTableExtension
extension AppointmentTableExtension on fhir.Appointment {
  /// AppointmentTableCompanion
  AppointmentTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AppointmentTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AppointmentHistoryTableExtension
extension AppointmentHistoryTableExtension on AppointmentTableCompanion {
  /// AppointmentHistoryTableCompanion
  AppointmentHistoryTableCompanion get companion {
    return AppointmentHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// AppointmentResponseTableExtension
extension AppointmentResponseTableExtension on fhir.AppointmentResponse {
  /// AppointmentResponseTableCompanion
  AppointmentResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AppointmentResponseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AppointmentResponseHistoryTableExtension
extension AppointmentResponseHistoryTableExtension
    on AppointmentResponseTableCompanion {
  /// AppointmentResponseHistoryTableCompanion
  AppointmentResponseHistoryTableCompanion get companion {
    return AppointmentResponseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// AuditEventTableExtension
extension AuditEventTableExtension on fhir.AuditEvent {
  /// AuditEventTableCompanion
  AuditEventTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return AuditEventTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// AuditEventHistoryTableExtension
extension AuditEventHistoryTableExtension on AuditEventTableCompanion {
  /// AuditEventHistoryTableCompanion
  AuditEventHistoryTableCompanion get companion {
    return AuditEventHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// BasicTableExtension
extension BasicTableExtension on fhir.Basic {
  /// BasicTableCompanion
  BasicTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return BasicTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// BasicHistoryTableExtension
extension BasicHistoryTableExtension on BasicTableCompanion {
  /// BasicHistoryTableCompanion
  BasicHistoryTableCompanion get companion {
    return BasicHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// BinaryTableExtension
extension BinaryTableExtension on fhir.Binary {
  /// BinaryTableCompanion
  BinaryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return BinaryTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// BinaryHistoryTableExtension
extension BinaryHistoryTableExtension on BinaryTableCompanion {
  /// BinaryHistoryTableCompanion
  BinaryHistoryTableCompanion get companion {
    return BinaryHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// BiologicallyDerivedProductTableExtension
extension BiologicallyDerivedProductTableExtension
    on fhir.BiologicallyDerivedProduct {
  /// BiologicallyDerivedProductTableCompanion
  BiologicallyDerivedProductTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return BiologicallyDerivedProductTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// BiologicallyDerivedProductHistoryTableExtension
extension BiologicallyDerivedProductHistoryTableExtension
    on BiologicallyDerivedProductTableCompanion {
  /// BiologicallyDerivedProductHistoryTableCompanion
  BiologicallyDerivedProductHistoryTableCompanion get companion {
    return BiologicallyDerivedProductHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// BodyStructureTableExtension
extension BodyStructureTableExtension on fhir.BodyStructure {
  /// BodyStructureTableCompanion
  BodyStructureTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return BodyStructureTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// BodyStructureHistoryTableExtension
extension BodyStructureHistoryTableExtension on BodyStructureTableCompanion {
  /// BodyStructureHistoryTableCompanion
  BodyStructureHistoryTableCompanion get companion {
    return BodyStructureHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// BundleTableExtension
extension BundleTableExtension on fhir.Bundle {
  /// BundleTableCompanion
  BundleTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return BundleTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// BundleHistoryTableExtension
extension BundleHistoryTableExtension on BundleTableCompanion {
  /// BundleHistoryTableCompanion
  BundleHistoryTableCompanion get companion {
    return BundleHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CapabilityStatementTableExtension
extension CapabilityStatementTableExtension on fhir.CapabilityStatement {
  /// CapabilityStatementTableCompanion
  CapabilityStatementTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CapabilityStatementTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CapabilityStatementHistoryTableExtension
extension CapabilityStatementHistoryTableExtension
    on CapabilityStatementTableCompanion {
  /// CapabilityStatementHistoryTableCompanion
  CapabilityStatementHistoryTableCompanion get companion {
    return CapabilityStatementHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CarePlanTableExtension
extension CarePlanTableExtension on fhir.CarePlan {
  /// CarePlanTableCompanion
  CarePlanTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CarePlanTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CarePlanHistoryTableExtension
extension CarePlanHistoryTableExtension on CarePlanTableCompanion {
  /// CarePlanHistoryTableCompanion
  CarePlanHistoryTableCompanion get companion {
    return CarePlanHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CareTeamTableExtension
extension CareTeamTableExtension on fhir.CareTeam {
  /// CareTeamTableCompanion
  CareTeamTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CareTeamTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CareTeamHistoryTableExtension
extension CareTeamHistoryTableExtension on CareTeamTableCompanion {
  /// CareTeamHistoryTableCompanion
  CareTeamHistoryTableCompanion get companion {
    return CareTeamHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CatalogEntryTableExtension
extension CatalogEntryTableExtension on fhir.CatalogEntry {
  /// CatalogEntryTableCompanion
  CatalogEntryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CatalogEntryTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CatalogEntryHistoryTableExtension
extension CatalogEntryHistoryTableExtension on CatalogEntryTableCompanion {
  /// CatalogEntryHistoryTableCompanion
  CatalogEntryHistoryTableCompanion get companion {
    return CatalogEntryHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ChargeItemTableExtension
extension ChargeItemTableExtension on fhir.ChargeItem {
  /// ChargeItemTableCompanion
  ChargeItemTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ChargeItemTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ChargeItemHistoryTableExtension
extension ChargeItemHistoryTableExtension on ChargeItemTableCompanion {
  /// ChargeItemHistoryTableCompanion
  ChargeItemHistoryTableCompanion get companion {
    return ChargeItemHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ChargeItemDefinitionTableExtension
extension ChargeItemDefinitionTableExtension on fhir.ChargeItemDefinition {
  /// ChargeItemDefinitionTableCompanion
  ChargeItemDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ChargeItemDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ChargeItemDefinitionHistoryTableExtension
extension ChargeItemDefinitionHistoryTableExtension
    on ChargeItemDefinitionTableCompanion {
  /// ChargeItemDefinitionHistoryTableCompanion
  ChargeItemDefinitionHistoryTableCompanion get companion {
    return ChargeItemDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CitationTableExtension
extension CitationTableExtension on fhir.Citation {
  /// CitationTableCompanion
  CitationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CitationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CitationHistoryTableExtension
extension CitationHistoryTableExtension on CitationTableCompanion {
  /// CitationHistoryTableCompanion
  CitationHistoryTableCompanion get companion {
    return CitationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ClaimTableExtension
extension ClaimTableExtension on fhir.Claim {
  /// ClaimTableCompanion
  ClaimTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ClaimTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ClaimHistoryTableExtension
extension ClaimHistoryTableExtension on ClaimTableCompanion {
  /// ClaimHistoryTableCompanion
  ClaimHistoryTableCompanion get companion {
    return ClaimHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ClaimResponseTableExtension
extension ClaimResponseTableExtension on fhir.ClaimResponse {
  /// ClaimResponseTableCompanion
  ClaimResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ClaimResponseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ClaimResponseHistoryTableExtension
extension ClaimResponseHistoryTableExtension on ClaimResponseTableCompanion {
  /// ClaimResponseHistoryTableCompanion
  ClaimResponseHistoryTableCompanion get companion {
    return ClaimResponseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ClinicalImpressionTableExtension
extension ClinicalImpressionTableExtension on fhir.ClinicalImpression {
  /// ClinicalImpressionTableCompanion
  ClinicalImpressionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ClinicalImpressionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ClinicalImpressionHistoryTableExtension
extension ClinicalImpressionHistoryTableExtension
    on ClinicalImpressionTableCompanion {
  /// ClinicalImpressionHistoryTableCompanion
  ClinicalImpressionHistoryTableCompanion get companion {
    return ClinicalImpressionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ClinicalUseDefinitionTableExtension
extension ClinicalUseDefinitionTableExtension on fhir.ClinicalUseDefinition {
  /// ClinicalUseDefinitionTableCompanion
  ClinicalUseDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ClinicalUseDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ClinicalUseDefinitionHistoryTableExtension
extension ClinicalUseDefinitionHistoryTableExtension
    on ClinicalUseDefinitionTableCompanion {
  /// ClinicalUseDefinitionHistoryTableCompanion
  ClinicalUseDefinitionHistoryTableCompanion get companion {
    return ClinicalUseDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CodeSystemTableExtension
extension CodeSystemTableExtension on fhir.CodeSystem {
  /// CodeSystemTableCompanion
  CodeSystemTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CodeSystemTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CodeSystemHistoryTableExtension
extension CodeSystemHistoryTableExtension on CodeSystemTableCompanion {
  /// CodeSystemHistoryTableCompanion
  CodeSystemHistoryTableCompanion get companion {
    return CodeSystemHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CommunicationTableExtension
extension CommunicationTableExtension on fhir.Communication {
  /// CommunicationTableCompanion
  CommunicationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CommunicationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CommunicationHistoryTableExtension
extension CommunicationHistoryTableExtension on CommunicationTableCompanion {
  /// CommunicationHistoryTableCompanion
  CommunicationHistoryTableCompanion get companion {
    return CommunicationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CommunicationRequestTableExtension
extension CommunicationRequestTableExtension on fhir.CommunicationRequest {
  /// CommunicationRequestTableCompanion
  CommunicationRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CommunicationRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CommunicationRequestHistoryTableExtension
extension CommunicationRequestHistoryTableExtension
    on CommunicationRequestTableCompanion {
  /// CommunicationRequestHistoryTableCompanion
  CommunicationRequestHistoryTableCompanion get companion {
    return CommunicationRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CompartmentDefinitionTableExtension
extension CompartmentDefinitionTableExtension on fhir.CompartmentDefinition {
  /// CompartmentDefinitionTableCompanion
  CompartmentDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CompartmentDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CompartmentDefinitionHistoryTableExtension
extension CompartmentDefinitionHistoryTableExtension
    on CompartmentDefinitionTableCompanion {
  /// CompartmentDefinitionHistoryTableCompanion
  CompartmentDefinitionHistoryTableCompanion get companion {
    return CompartmentDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CompositionTableExtension
extension CompositionTableExtension on fhir.Composition {
  /// CompositionTableCompanion
  CompositionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CompositionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CompositionHistoryTableExtension
extension CompositionHistoryTableExtension on CompositionTableCompanion {
  /// CompositionHistoryTableCompanion
  CompositionHistoryTableCompanion get companion {
    return CompositionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ConceptMapTableExtension
extension ConceptMapTableExtension on fhir.ConceptMap {
  /// ConceptMapTableCompanion
  ConceptMapTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ConceptMapTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ConceptMapHistoryTableExtension
extension ConceptMapHistoryTableExtension on ConceptMapTableCompanion {
  /// ConceptMapHistoryTableCompanion
  ConceptMapHistoryTableCompanion get companion {
    return ConceptMapHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ConditionTableExtension
extension ConditionTableExtension on fhir.Condition {
  /// ConditionTableCompanion
  ConditionTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Condition;
    return ConditionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject.reference!.value!),
      clinicalStatus: Value(
        resource.clinicalStatus?.coding?.firstOrNull?.code?.value,
      ),
      verificationStatus: Value(
        resource.verificationStatus?.coding?.firstOrNull?.code?.value,
      ),
      code: Value(resource.code?.coding?.firstOrNull?.code?.value),
      onsetDateTime: Value(
        resource.onsetX
            ?.isAs<fhir.FhirDateTime>()
            ?.valueDateTime
            ?.millisecondsSinceEpoch,
      ),
    );
  }
}

/// ConditionHistoryTableExtension
extension ConditionHistoryTableExtension on ConditionTableCompanion {
  /// ConditionHistoryTableCompanion
  ConditionHistoryTableCompanion get companion {
    return ConditionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ConsentTableExtension
extension ConsentTableExtension on fhir.Consent {
  /// ConsentTableCompanion
  ConsentTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ConsentTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ConsentHistoryTableExtension
extension ConsentHistoryTableExtension on ConsentTableCompanion {
  /// ConsentHistoryTableCompanion
  ConsentHistoryTableCompanion get companion {
    return ConsentHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ContractTableExtension
extension ContractTableExtension on fhir.Contract {
  /// ContractTableCompanion
  ContractTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ContractTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ContractHistoryTableExtension
extension ContractHistoryTableExtension on ContractTableCompanion {
  /// ContractHistoryTableCompanion
  ContractHistoryTableCompanion get companion {
    return ContractHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CoverageTableExtension
extension CoverageTableExtension on fhir.Coverage {
  /// CoverageTableCompanion
  CoverageTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CoverageTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CoverageHistoryTableExtension
extension CoverageHistoryTableExtension on CoverageTableCompanion {
  /// CoverageHistoryTableCompanion
  CoverageHistoryTableCompanion get companion {
    return CoverageHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CoverageEligibilityRequestTableExtension
extension CoverageEligibilityRequestTableExtension
    on fhir.CoverageEligibilityRequest {
  /// CoverageEligibilityRequestTableCompanion
  CoverageEligibilityRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CoverageEligibilityRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CoverageEligibilityRequestHistoryTableExtension
extension CoverageEligibilityRequestHistoryTableExtension
    on CoverageEligibilityRequestTableCompanion {
  /// CoverageEligibilityRequestHistoryTableCompanion
  CoverageEligibilityRequestHistoryTableCompanion get companion {
    return CoverageEligibilityRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// CoverageEligibilityResponseTableExtension
extension CoverageEligibilityResponseTableExtension
    on fhir.CoverageEligibilityResponse {
  /// CoverageEligibilityResponseTableCompanion
  CoverageEligibilityResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return CoverageEligibilityResponseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// CoverageEligibilityResponseHistoryTableExtension
extension CoverageEligibilityResponseHistoryTableExtension
    on CoverageEligibilityResponseTableCompanion {
  /// CoverageEligibilityResponseHistoryTableCompanion
  CoverageEligibilityResponseHistoryTableCompanion get companion {
    return CoverageEligibilityResponseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DetectedIssueTableExtension
extension DetectedIssueTableExtension on fhir.DetectedIssue {
  /// DetectedIssueTableCompanion
  DetectedIssueTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DetectedIssueTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DetectedIssueHistoryTableExtension
extension DetectedIssueHistoryTableExtension on DetectedIssueTableCompanion {
  /// DetectedIssueHistoryTableCompanion
  DetectedIssueHistoryTableCompanion get companion {
    return DetectedIssueHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DeviceTableExtension
extension DeviceTableExtension on fhir.Device {
  /// DeviceTableCompanion
  DeviceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DeviceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DeviceHistoryTableExtension
extension DeviceHistoryTableExtension on DeviceTableCompanion {
  /// DeviceHistoryTableCompanion
  DeviceHistoryTableCompanion get companion {
    return DeviceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DeviceDefinitionTableExtension
extension DeviceDefinitionTableExtension on fhir.DeviceDefinition {
  /// DeviceDefinitionTableCompanion
  DeviceDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DeviceDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DeviceDefinitionHistoryTableExtension
extension DeviceDefinitionHistoryTableExtension
    on DeviceDefinitionTableCompanion {
  /// DeviceDefinitionHistoryTableCompanion
  DeviceDefinitionHistoryTableCompanion get companion {
    return DeviceDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DeviceMetricTableExtension
extension DeviceMetricTableExtension on fhir.DeviceMetric {
  /// DeviceMetricTableCompanion
  DeviceMetricTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DeviceMetricTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DeviceMetricHistoryTableExtension
extension DeviceMetricHistoryTableExtension on DeviceMetricTableCompanion {
  /// DeviceMetricHistoryTableCompanion
  DeviceMetricHistoryTableCompanion get companion {
    return DeviceMetricHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DeviceRequestTableExtension
extension DeviceRequestTableExtension on fhir.DeviceRequest {
  /// DeviceRequestTableCompanion
  DeviceRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DeviceRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DeviceRequestHistoryTableExtension
extension DeviceRequestHistoryTableExtension on DeviceRequestTableCompanion {
  /// DeviceRequestHistoryTableCompanion
  DeviceRequestHistoryTableCompanion get companion {
    return DeviceRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DeviceUseStatementTableExtension
extension DeviceUseStatementTableExtension on fhir.DeviceUseStatement {
  /// DeviceUseStatementTableCompanion
  DeviceUseStatementTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DeviceUseStatementTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DeviceUseStatementHistoryTableExtension
extension DeviceUseStatementHistoryTableExtension
    on DeviceUseStatementTableCompanion {
  /// DeviceUseStatementHistoryTableCompanion
  DeviceUseStatementHistoryTableCompanion get companion {
    return DeviceUseStatementHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DiagnosticReportTableExtension
extension DiagnosticReportTableExtension on fhir.DiagnosticReport {
  /// DiagnosticReportTableCompanion
  DiagnosticReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DiagnosticReportTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DiagnosticReportHistoryTableExtension
extension DiagnosticReportHistoryTableExtension
    on DiagnosticReportTableCompanion {
  /// DiagnosticReportHistoryTableCompanion
  DiagnosticReportHistoryTableCompanion get companion {
    return DiagnosticReportHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DocumentManifestTableExtension
extension DocumentManifestTableExtension on fhir.DocumentManifest {
  /// DocumentManifestTableCompanion
  DocumentManifestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DocumentManifestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DocumentManifestHistoryTableExtension
extension DocumentManifestHistoryTableExtension
    on DocumentManifestTableCompanion {
  /// DocumentManifestHistoryTableCompanion
  DocumentManifestHistoryTableCompanion get companion {
    return DocumentManifestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// DocumentReferenceTableExtension
extension DocumentReferenceTableExtension on fhir.DocumentReference {
  /// DocumentReferenceTableCompanion
  DocumentReferenceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return DocumentReferenceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// DocumentReferenceHistoryTableExtension
extension DocumentReferenceHistoryTableExtension
    on DocumentReferenceTableCompanion {
  /// DocumentReferenceHistoryTableCompanion
  DocumentReferenceHistoryTableCompanion get companion {
    return DocumentReferenceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EncounterTableExtension
extension EncounterTableExtension on fhir.Encounter {
  /// EncounterTableCompanion
  EncounterTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Encounter;
    return EncounterTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject!.reference!.value!),
      type: Value(resource.type?.firstOrNull?.coding?.firstOrNull?.code?.value),
      startDateTime: Value(
        resource.period?.start?.valueDateTime?.millisecondsSinceEpoch,
      ),
      endDateTime: Value(
        resource.period?.end?.valueDateTime?.millisecondsSinceEpoch,
      ),
      status: Value(resource.status.value),
    );
  }
}

/// EncounterHistoryTableExtension
extension EncounterHistoryTableExtension on EncounterTableCompanion {
  /// EncounterHistoryTableCompanion
  EncounterHistoryTableCompanion get companion {
    return EncounterHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EnrollmentRequestTableExtension
extension EnrollmentRequestTableExtension on fhir.EnrollmentRequest {
  /// EnrollmentRequestTableCompanion
  EnrollmentRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EnrollmentRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EnrollmentRequestHistoryTableExtension
extension EnrollmentRequestHistoryTableExtension
    on EnrollmentRequestTableCompanion {
  /// EnrollmentRequestHistoryTableCompanion
  EnrollmentRequestHistoryTableCompanion get companion {
    return EnrollmentRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EnrollmentResponseTableExtension
extension EnrollmentResponseTableExtension on fhir.EnrollmentResponse {
  /// EnrollmentResponseTableCompanion
  EnrollmentResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EnrollmentResponseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EnrollmentResponseHistoryTableExtension
extension EnrollmentResponseHistoryTableExtension
    on EnrollmentResponseTableCompanion {
  /// EnrollmentResponseHistoryTableCompanion
  EnrollmentResponseHistoryTableCompanion get companion {
    return EnrollmentResponseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EpisodeOfCareTableExtension
extension EpisodeOfCareTableExtension on fhir.EpisodeOfCare {
  /// EpisodeOfCareTableCompanion
  EpisodeOfCareTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EpisodeOfCareTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EpisodeOfCareHistoryTableExtension
extension EpisodeOfCareHistoryTableExtension on EpisodeOfCareTableCompanion {
  /// EpisodeOfCareHistoryTableCompanion
  EpisodeOfCareHistoryTableCompanion get companion {
    return EpisodeOfCareHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EventDefinitionTableExtension
extension EventDefinitionTableExtension on fhir.EventDefinition {
  /// EventDefinitionTableCompanion
  EventDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EventDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EventDefinitionHistoryTableExtension
extension EventDefinitionHistoryTableExtension
    on EventDefinitionTableCompanion {
  /// EventDefinitionHistoryTableCompanion
  EventDefinitionHistoryTableCompanion get companion {
    return EventDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EvidenceTableExtension
extension EvidenceTableExtension on fhir.Evidence {
  /// EvidenceTableCompanion
  EvidenceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EvidenceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EvidenceHistoryTableExtension
extension EvidenceHistoryTableExtension on EvidenceTableCompanion {
  /// EvidenceHistoryTableCompanion
  EvidenceHistoryTableCompanion get companion {
    return EvidenceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EvidenceReportTableExtension
extension EvidenceReportTableExtension on fhir.EvidenceReport {
  /// EvidenceReportTableCompanion
  EvidenceReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EvidenceReportTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EvidenceReportHistoryTableExtension
extension EvidenceReportHistoryTableExtension on EvidenceReportTableCompanion {
  /// EvidenceReportHistoryTableCompanion
  EvidenceReportHistoryTableCompanion get companion {
    return EvidenceReportHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EvidenceVariableTableExtension
extension EvidenceVariableTableExtension on fhir.EvidenceVariable {
  /// EvidenceVariableTableCompanion
  EvidenceVariableTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return EvidenceVariableTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EvidenceVariableHistoryTableExtension
extension EvidenceVariableHistoryTableExtension
    on EvidenceVariableTableCompanion {
  /// EvidenceVariableHistoryTableCompanion
  EvidenceVariableHistoryTableCompanion get companion {
    return EvidenceVariableHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ExampleScenarioTableExtension
extension ExampleScenarioTableExtension on fhir.ExampleScenario {
  /// ExampleScenarioTableCompanion
  ExampleScenarioTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ExampleScenarioTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ExampleScenarioHistoryTableExtension
extension ExampleScenarioHistoryTableExtension
    on ExampleScenarioTableCompanion {
  /// ExampleScenarioHistoryTableCompanion
  ExampleScenarioHistoryTableCompanion get companion {
    return ExampleScenarioHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ExplanationOfBenefitTableExtension
extension ExplanationOfBenefitTableExtension on fhir.ExplanationOfBenefit {
  /// ExplanationOfBenefitTableCompanion
  ExplanationOfBenefitTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ExplanationOfBenefitTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ExplanationOfBenefitHistoryTableExtension
extension ExplanationOfBenefitHistoryTableExtension
    on ExplanationOfBenefitTableCompanion {
  /// ExplanationOfBenefitHistoryTableCompanion
  ExplanationOfBenefitHistoryTableCompanion get companion {
    return ExplanationOfBenefitHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// FamilyMemberHistoryTableExtension
extension FamilyMemberHistoryTableExtension on fhir.FamilyMemberHistory {
  /// FamilyMemberHistoryTableCompanion
  FamilyMemberHistoryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return FamilyMemberHistoryTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// FamilyMemberHistoryHistoryTableExtension
extension FamilyMemberHistoryHistoryTableExtension
    on FamilyMemberHistoryTableCompanion {
  /// FamilyMemberHistoryHistoryTableCompanion
  FamilyMemberHistoryHistoryTableCompanion get companion {
    return FamilyMemberHistoryHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// EndpointTableExtension
extension EndpointTableExtension on fhir.FhirEndpoint {
  /// EndpointTableCompanion
  FhirEndpointTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return FhirEndpointTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EndpointHistoryTableExtension
extension EndpointHistoryTableExtension on FhirEndpointTableCompanion {
  /// EndpointHistoryTableCompanion
  FhirEndpointHistoryTableCompanion get companion {
    return FhirEndpointHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// GroupTableExtension
extension GroupTableExtension on fhir.FhirGroup {
  /// GroupTableCompanion
  FhirGroupTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return FhirGroupTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// GroupHistoryTableExtension
extension GroupHistoryTableExtension on FhirGroupTableCompanion {
  /// GroupHistoryTableCompanion
  FhirGroupHistoryTableCompanion get companion {
    return FhirGroupHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ListTableExtension
extension ListTableExtension on fhir.FhirList {
  /// ListTableCompanion
  FhirListTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return FhirListTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ListHistoryTableExtension
extension ListHistoryTableExtension on FhirListTableCompanion {
  /// ListHistoryTableCompanion
  FhirListHistoryTableCompanion get companion {
    return FhirListHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// FlagTableExtension
extension FlagTableExtension on fhir.Flag {
  /// FlagTableCompanion
  FlagTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return FlagTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// FlagHistoryTableExtension
extension FlagHistoryTableExtension on FlagTableCompanion {
  /// FlagHistoryTableCompanion
  FlagHistoryTableCompanion get companion {
    return FlagHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// GoalTableExtension
extension GoalTableExtension on fhir.Goal {
  /// GoalTableCompanion
  GoalTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return GoalTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// GoalHistoryTableExtension
extension GoalHistoryTableExtension on GoalTableCompanion {
  /// GoalHistoryTableCompanion
  GoalHistoryTableCompanion get companion {
    return GoalHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// GraphDefinitionTableExtension
extension GraphDefinitionTableExtension on fhir.GraphDefinition {
  /// GraphDefinitionTableCompanion
  GraphDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return GraphDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// GraphDefinitionHistoryTableExtension
extension GraphDefinitionHistoryTableExtension
    on GraphDefinitionTableCompanion {
  /// GraphDefinitionHistoryTableCompanion
  GraphDefinitionHistoryTableCompanion get companion {
    return GraphDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// GuidanceResponseTableExtension
extension GuidanceResponseTableExtension on fhir.GuidanceResponse {
  /// GuidanceResponseTableCompanion
  GuidanceResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return GuidanceResponseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// GuidanceResponseHistoryTableExtension
extension GuidanceResponseHistoryTableExtension
    on GuidanceResponseTableCompanion {
  /// GuidanceResponseHistoryTableCompanion
  GuidanceResponseHistoryTableCompanion get companion {
    return GuidanceResponseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// HealthcareServiceTableExtension
extension HealthcareServiceTableExtension on fhir.HealthcareService {
  /// HealthcareServiceTableCompanion
  HealthcareServiceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return HealthcareServiceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// HealthcareServiceHistoryTableExtension
extension HealthcareServiceHistoryTableExtension
    on HealthcareServiceTableCompanion {
  /// HealthcareServiceHistoryTableCompanion
  HealthcareServiceHistoryTableCompanion get companion {
    return HealthcareServiceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ImagingStudyTableExtension
extension ImagingStudyTableExtension on fhir.ImagingStudy {
  /// ImagingStudyTableCompanion
  ImagingStudyTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ImagingStudyTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ImagingStudyHistoryTableExtension
extension ImagingStudyHistoryTableExtension on ImagingStudyTableCompanion {
  /// ImagingStudyHistoryTableCompanion
  ImagingStudyHistoryTableCompanion get companion {
    return ImagingStudyHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ImmunizationTableExtension
extension ImmunizationTableExtension on fhir.Immunization {
  /// ImmunizationTableCompanion
  ImmunizationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ImmunizationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ImmunizationHistoryTableExtension
extension ImmunizationHistoryTableExtension on ImmunizationTableCompanion {
  /// ImmunizationHistoryTableCompanion
  ImmunizationHistoryTableCompanion get companion {
    return ImmunizationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ImmunizationEvaluationTableExtension
extension ImmunizationEvaluationTableExtension on fhir.ImmunizationEvaluation {
  /// ImmunizationEvaluationTableCompanion
  ImmunizationEvaluationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ImmunizationEvaluationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ImmunizationEvaluationHistoryTableExtension
extension ImmunizationEvaluationHistoryTableExtension
    on ImmunizationEvaluationTableCompanion {
  /// ImmunizationEvaluationHistoryTableCompanion
  ImmunizationEvaluationHistoryTableCompanion get companion {
    return ImmunizationEvaluationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ImmunizationRecommendationTableExtension
extension ImmunizationRecommendationTableExtension
    on fhir.ImmunizationRecommendation {
  /// ImmunizationRecommendationTableCompanion
  ImmunizationRecommendationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ImmunizationRecommendationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ImmunizationRecommendationHistoryTableExtension
extension ImmunizationRecommendationHistoryTableExtension
    on ImmunizationRecommendationTableCompanion {
  /// ImmunizationRecommendationHistoryTableCompanion
  ImmunizationRecommendationHistoryTableCompanion get companion {
    return ImmunizationRecommendationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ImplementationGuideTableExtension
extension ImplementationGuideTableExtension on fhir.ImplementationGuide {
  /// ImplementationGuideTableCompanion
  ImplementationGuideTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ImplementationGuideTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ImplementationGuideHistoryTableExtension
extension ImplementationGuideHistoryTableExtension
    on ImplementationGuideTableCompanion {
  /// ImplementationGuideHistoryTableCompanion
  ImplementationGuideHistoryTableCompanion get companion {
    return ImplementationGuideHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// IngredientTableExtension
extension IngredientTableExtension on fhir.Ingredient {
  /// IngredientTableCompanion
  IngredientTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return IngredientTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// IngredientHistoryTableExtension
extension IngredientHistoryTableExtension on IngredientTableCompanion {
  /// IngredientHistoryTableCompanion
  IngredientHistoryTableCompanion get companion {
    return IngredientHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// InsurancePlanTableExtension
extension InsurancePlanTableExtension on fhir.InsurancePlan {
  /// InsurancePlanTableCompanion
  InsurancePlanTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return InsurancePlanTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// InsurancePlanHistoryTableExtension
extension InsurancePlanHistoryTableExtension on InsurancePlanTableCompanion {
  /// InsurancePlanHistoryTableCompanion
  InsurancePlanHistoryTableCompanion get companion {
    return InsurancePlanHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// InvoiceTableExtension
extension InvoiceTableExtension on fhir.Invoice {
  /// InvoiceTableCompanion
  InvoiceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return InvoiceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// InvoiceHistoryTableExtension
extension InvoiceHistoryTableExtension on InvoiceTableCompanion {
  /// InvoiceHistoryTableCompanion
  InvoiceHistoryTableCompanion get companion {
    return InvoiceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// LibraryTableExtension
extension LibraryTableExtension on fhir.Library {
  /// LibraryTableCompanion
  LibraryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return LibraryTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// LibraryHistoryTableExtension
extension LibraryHistoryTableExtension on LibraryTableCompanion {
  /// LibraryHistoryTableCompanion
  LibraryHistoryTableCompanion get companion {
    return LibraryHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// LinkageTableExtension
extension LinkageTableExtension on fhir.Linkage {
  /// LinkageTableCompanion
  LinkageTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return LinkageTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// LinkageHistoryTableExtension
extension LinkageHistoryTableExtension on LinkageTableCompanion {
  /// LinkageHistoryTableCompanion
  LinkageHistoryTableCompanion get companion {
    return LinkageHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// LocationTableExtension
extension LocationTableExtension on fhir.Location {
  /// LocationTableCompanion
  LocationTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Location;
    return LocationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      name: Value(resource.name?.value),
      type: Value(resource.type?.firstOrNull?.coding?.firstOrNull?.code?.value),
      address: Value(resource.address?.text?.value),
      managingOrganization: Value(
        resource.managingOrganization?.reference?.value,
      ),
    );
  }
}

/// LocationHistoryTableExtension
extension LocationHistoryTableExtension on LocationTableCompanion {
  /// LocationHistoryTableCompanion
  LocationHistoryTableCompanion get companion {
    return LocationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ManufacturedItemDefinitionTableExtension
extension ManufacturedItemDefinitionTableExtension
    on fhir.ManufacturedItemDefinition {
  /// ManufacturedItemDefinitionTableCompanion
  ManufacturedItemDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ManufacturedItemDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ManufacturedItemDefinitionHistoryTableExtension
extension ManufacturedItemDefinitionHistoryTableExtension
    on ManufacturedItemDefinitionTableCompanion {
  /// ManufacturedItemDefinitionHistoryTableCompanion
  ManufacturedItemDefinitionHistoryTableCompanion get companion {
    return ManufacturedItemDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MeasureTableExtension
extension MeasureTableExtension on fhir.Measure {
  /// MeasureTableCompanion
  MeasureTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MeasureTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MeasureHistoryTableExtension
extension MeasureHistoryTableExtension on MeasureTableCompanion {
  /// MeasureHistoryTableCompanion
  MeasureHistoryTableCompanion get companion {
    return MeasureHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MeasureReportTableExtension
extension MeasureReportTableExtension on fhir.MeasureReport {
  /// MeasureReportTableCompanion
  MeasureReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MeasureReportTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MeasureReportHistoryTableExtension
extension MeasureReportHistoryTableExtension on MeasureReportTableCompanion {
  /// MeasureReportHistoryTableCompanion
  MeasureReportHistoryTableCompanion get companion {
    return MeasureReportHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MediaTableExtension
extension MediaTableExtension on fhir.Media {
  /// MediaTableCompanion
  MediaTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MediaTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MediaHistoryTableExtension
extension MediaHistoryTableExtension on MediaTableCompanion {
  /// MediaHistoryTableCompanion
  MediaHistoryTableCompanion get companion {
    return MediaHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicationTableExtension
extension MedicationTableExtension on fhir.Medication {
  /// MedicationTableCompanion
  MedicationTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Medication;
    return MedicationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      code: Value(resource.code?.coding?.firstOrNull?.code?.value),
      status: Value(resource.status?.value),
      manufacturer: Value(resource.manufacturer?.reference?.value),
      form: Value(resource.form?.coding?.firstOrNull?.code?.value),
    );
  }
}

/// MedicationHistoryTableExtension
extension MedicationHistoryTableExtension on MedicationTableCompanion {
  /// MedicationHistoryTableCompanion
  MedicationHistoryTableCompanion get companion {
    return MedicationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicationAdministrationTableExtension
extension MedicationAdministrationTableExtension
    on fhir.MedicationAdministration {
  /// MedicationAdministrationTableCompanion
  MedicationAdministrationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true)
        as fhir.MedicationAdministration;
    return MedicationAdministrationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject.reference!.value!),
      medicationId: Value(
        resource.medicationX.isAs<fhir.Reference>()?.reference?.value ??
            resource.medicationX
                .isAs<fhir.CodeableConcept>()
                ?.coding
                ?.firstOrNull
                ?.code
                ?.value ??
            '',
      ),
      effectiveDateTime: Value(
        resource.effectiveX
            .isAs<fhir.FhirDateTime>()
            ?.valueDateTime
            ?.millisecondsSinceEpoch,
      ),
      status: Value(resource.status.value),
    );
  }
}

/// MedicationAdministrationHistoryTableExtension
extension MedicationAdministrationHistoryTableExtension
    on MedicationAdministrationTableCompanion {
  /// MedicationAdministrationHistoryTableCompanion
  MedicationAdministrationHistoryTableCompanion get companion {
    return MedicationAdministrationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicationDispenseTableExtension
extension MedicationDispenseTableExtension on fhir.MedicationDispense {
  /// MedicationDispenseTableCompanion
  MedicationDispenseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true)
        as fhir.MedicationDispense;
    return MedicationDispenseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject!.reference!.value!),
      medicationId: Value(
        resource.medicationX.isAs<fhir.Reference>()?.reference?.value ??
            resource.medicationX
                .isAs<fhir.CodeableConcept>()
                ?.coding
                ?.firstOrNull
                ?.code
                ?.value ??
            '',
      ),
      quantity: Value(resource.quantity?.value?.toString()),
      daysSupply: Value(resource.daysSupply?.value?.round()),
      status: Value(resource.status.value),
    );
  }
}

/// MedicationDispenseHistoryTableExtension
extension MedicationDispenseHistoryTableExtension
    on MedicationDispenseTableCompanion {
  /// MedicationDispenseHistoryTableCompanion
  MedicationDispenseHistoryTableCompanion get companion {
    return MedicationDispenseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicationKnowledgeTableExtension
extension MedicationKnowledgeTableExtension on fhir.MedicationKnowledge {
  /// MedicationKnowledgeTableCompanion
  MedicationKnowledgeTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MedicationKnowledgeTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicationKnowledgeHistoryTableExtension
extension MedicationKnowledgeHistoryTableExtension
    on MedicationKnowledgeTableCompanion {
  /// MedicationKnowledgeHistoryTableCompanion
  MedicationKnowledgeHistoryTableCompanion get companion {
    return MedicationKnowledgeHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicationRequestTableExtension
extension MedicationRequestTableExtension on fhir.MedicationRequest {
  /// MedicationRequestTableCompanion
  MedicationRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true)
        as fhir.MedicationRequest;
    return MedicationRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject.reference!.value!),
      medicationId: Value(
        resource.medicationX.isAs<fhir.Reference>()?.reference?.value ??
            resource.medicationX
                .isAs<fhir.CodeableConcept>()
                ?.coding
                ?.firstOrNull
                ?.code
                ?.value ??
            '',
      ),
      intent: Value(resource.intent.value),
      priority: Value(resource.priority?.value),
      status: Value(resource.status.value),
    );
  }
}

/// MedicationRequestHistoryTableExtension
extension MedicationRequestHistoryTableExtension
    on MedicationRequestTableCompanion {
  /// MedicationRequestHistoryTableCompanion
  MedicationRequestHistoryTableCompanion get companion {
    return MedicationRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicationStatementTableExtension
extension MedicationStatementTableExtension on fhir.MedicationStatement {
  /// MedicationStatementTableCompanion
  MedicationStatementTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MedicationStatementTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicationStatementHistoryTableExtension
extension MedicationStatementHistoryTableExtension
    on MedicationStatementTableCompanion {
  /// MedicationStatementHistoryTableCompanion
  MedicationStatementHistoryTableCompanion get companion {
    return MedicationStatementHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MedicinalProductDefinitionTableExtension
extension MedicinalProductDefinitionTableExtension
    on fhir.MedicinalProductDefinition {
  /// MedicinalProductDefinitionTableCompanion
  MedicinalProductDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MedicinalProductDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicinalProductDefinitionHistoryTableExtension
extension MedicinalProductDefinitionHistoryTableExtension
    on MedicinalProductDefinitionTableCompanion {
  /// MedicinalProductDefinitionHistoryTableCompanion
  MedicinalProductDefinitionHistoryTableCompanion get companion {
    return MedicinalProductDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MessageDefinitionTableExtension
extension MessageDefinitionTableExtension on fhir.MessageDefinition {
  /// MessageDefinitionTableCompanion
  MessageDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MessageDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MessageDefinitionHistoryTableExtension
extension MessageDefinitionHistoryTableExtension
    on MessageDefinitionTableCompanion {
  /// MessageDefinitionHistoryTableCompanion
  MessageDefinitionHistoryTableCompanion get companion {
    return MessageDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MessageHeaderTableExtension
extension MessageHeaderTableExtension on fhir.MessageHeader {
  /// MessageHeaderTableCompanion
  MessageHeaderTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MessageHeaderTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MessageHeaderHistoryTableExtension
extension MessageHeaderHistoryTableExtension on MessageHeaderTableCompanion {
  /// MessageHeaderHistoryTableCompanion
  MessageHeaderHistoryTableCompanion get companion {
    return MessageHeaderHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// MolecularSequenceTableExtension
extension MolecularSequenceTableExtension on fhir.MolecularSequence {
  /// MolecularSequenceTableCompanion
  MolecularSequenceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return MolecularSequenceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MolecularSequenceHistoryTableExtension
extension MolecularSequenceHistoryTableExtension
    on MolecularSequenceTableCompanion {
  /// MolecularSequenceHistoryTableCompanion
  MolecularSequenceHistoryTableCompanion get companion {
    return MolecularSequenceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// NamingSystemTableExtension
extension NamingSystemTableExtension on fhir.NamingSystem {
  /// NamingSystemTableCompanion
  NamingSystemTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return NamingSystemTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// NamingSystemHistoryTableExtension
extension NamingSystemHistoryTableExtension on NamingSystemTableCompanion {
  /// NamingSystemHistoryTableCompanion
  NamingSystemHistoryTableCompanion get companion {
    return NamingSystemHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// NutritionOrderTableExtension
extension NutritionOrderTableExtension on fhir.NutritionOrder {
  /// NutritionOrderTableCompanion
  NutritionOrderTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return NutritionOrderTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// NutritionOrderHistoryTableExtension
extension NutritionOrderHistoryTableExtension on NutritionOrderTableCompanion {
  /// NutritionOrderHistoryTableCompanion
  NutritionOrderHistoryTableCompanion get companion {
    return NutritionOrderHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// NutritionProductTableExtension
extension NutritionProductTableExtension on fhir.NutritionProduct {
  /// NutritionProductTableCompanion
  NutritionProductTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return NutritionProductTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// NutritionProductHistoryTableExtension
extension NutritionProductHistoryTableExtension
    on NutritionProductTableCompanion {
  /// NutritionProductHistoryTableCompanion
  NutritionProductHistoryTableCompanion get companion {
    return NutritionProductHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ObservationTableExtension
extension ObservationTableExtension on fhir.Observation {
  /// ObservationTableCompanion
  ObservationTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Observation;
    return ObservationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject!.reference!.value!),
      type: Value(resource.code.coding?.firstOrNull?.code?.value),
      value: Value(
        resource.valueX?.isAs<fhir.Quantity>()?.value?.value?.toDouble(),
      ),
      unit: Value(resource.valueX?.isAs<fhir.Quantity>()?.unit?.value),
      effectiveDateTime: Value(
        resource.effectiveX
            ?.isAs<fhir.FhirDateTime>()
            ?.valueDateTime
            ?.millisecondsSinceEpoch,
      ),
    );
  }
}

/// ObservationHistoryTableExtension
extension ObservationHistoryTableExtension on ObservationTableCompanion {
  /// ObservationHistoryTableCompanion
  ObservationHistoryTableCompanion get companion {
    return ObservationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ObservationDefinitionTableExtension
extension ObservationDefinitionTableExtension on fhir.ObservationDefinition {
  /// ObservationDefinitionTableCompanion
  ObservationDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ObservationDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ObservationDefinitionHistoryTableExtension
extension ObservationDefinitionHistoryTableExtension
    on ObservationDefinitionTableCompanion {
  /// ObservationDefinitionHistoryTableCompanion
  ObservationDefinitionHistoryTableCompanion get companion {
    return ObservationDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// OperationDefinitionTableExtension
extension OperationDefinitionTableExtension on fhir.OperationDefinition {
  /// OperationDefinitionTableCompanion
  OperationDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return OperationDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// OperationDefinitionHistoryTableExtension
extension OperationDefinitionHistoryTableExtension
    on OperationDefinitionTableCompanion {
  /// OperationDefinitionHistoryTableCompanion
  OperationDefinitionHistoryTableCompanion get companion {
    return OperationDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// OperationOutcomeTableExtension
extension OperationOutcomeTableExtension on fhir.OperationOutcome {
  /// OperationOutcomeTableCompanion
  OperationOutcomeTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return OperationOutcomeTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// OperationOutcomeHistoryTableExtension
extension OperationOutcomeHistoryTableExtension
    on OperationOutcomeTableCompanion {
  /// OperationOutcomeHistoryTableCompanion
  OperationOutcomeHistoryTableCompanion get companion {
    return OperationOutcomeHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// OrganizationTableExtension
extension OrganizationTableExtension on fhir.Organization {
  /// OrganizationTableCompanion
  OrganizationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return OrganizationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// OrganizationHistoryTableExtension
extension OrganizationHistoryTableExtension on OrganizationTableCompanion {
  /// OrganizationHistoryTableCompanion
  OrganizationHistoryTableCompanion get companion {
    return OrganizationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// OrganizationAffiliationTableExtension
extension OrganizationAffiliationTableExtension
    on fhir.OrganizationAffiliation {
  /// OrganizationAffiliationTableCompanion
  OrganizationAffiliationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return OrganizationAffiliationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// OrganizationAffiliationHistoryTableExtension
extension OrganizationAffiliationHistoryTableExtension
    on OrganizationAffiliationTableCompanion {
  /// OrganizationAffiliationHistoryTableCompanion
  OrganizationAffiliationHistoryTableCompanion get companion {
    return OrganizationAffiliationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PackagedProductDefinitionTableExtension
extension PackagedProductDefinitionTableExtension
    on fhir.PackagedProductDefinition {
  /// PackagedProductDefinitionTableCompanion
  PackagedProductDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PackagedProductDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PackagedProductDefinitionHistoryTableExtension
extension PackagedProductDefinitionHistoryTableExtension
    on PackagedProductDefinitionTableCompanion {
  /// PackagedProductDefinitionHistoryTableCompanion
  PackagedProductDefinitionHistoryTableCompanion get companion {
    return PackagedProductDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ParametersTableExtension
extension ParametersTableExtension on fhir.Parameters {
  /// ParametersTableCompanion
  ParametersTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ParametersTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ParametersHistoryTableExtension
extension ParametersHistoryTableExtension on ParametersTableCompanion {
  /// ParametersHistoryTableCompanion
  ParametersHistoryTableCompanion get companion {
    return ParametersHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PatientTableExtension
extension PatientTableExtension on fhir.Patient {
  /// PatientTableCompanion
  PatientTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Patient;
    return PatientTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      active: Value(resource.active?.value),
      identifier: Value(resource.identifier?.firstOrNull?.value?.value),
      familyNames: Value(resource.name?.firstOrNull?.family?.value),
      givenNames: Value(resource.name?.firstOrNull?.given?.join(' ')),
      gender: Value(resource.gender?.value),
      birthDate: Value(
        resource.birthDate?.valueDateTime?.millisecondsSinceEpoch,
      ),
      deceased: Value(resource.deceasedX?.isAs<fhir.FhirBoolean>()?.value),
      managingOrganization: Value(
        resource.managingOrganization?.reference?.value,
      ),
    );
  }
}

/// PatientHistoryTableExtension
extension PatientHistoryTableExtension on PatientTableCompanion {
  /// PatientHistoryTableCompanion
  PatientHistoryTableCompanion get companion {
    return PatientHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PaymentNoticeTableExtension
extension PaymentNoticeTableExtension on fhir.PaymentNotice {
  /// PaymentNoticeTableCompanion
  PaymentNoticeTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PaymentNoticeTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PaymentNoticeHistoryTableExtension
extension PaymentNoticeHistoryTableExtension on PaymentNoticeTableCompanion {
  /// PaymentNoticeHistoryTableCompanion
  PaymentNoticeHistoryTableCompanion get companion {
    return PaymentNoticeHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PaymentReconciliationTableExtension
extension PaymentReconciliationTableExtension on fhir.PaymentReconciliation {
  /// PaymentReconciliationTableCompanion
  PaymentReconciliationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PaymentReconciliationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PaymentReconciliationHistoryTableExtension
extension PaymentReconciliationHistoryTableExtension
    on PaymentReconciliationTableCompanion {
  /// PaymentReconciliationHistoryTableCompanion
  PaymentReconciliationHistoryTableCompanion get companion {
    return PaymentReconciliationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PersonTableExtension
extension PersonTableExtension on fhir.Person {
  /// PersonTableCompanion
  PersonTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PersonTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PersonHistoryTableExtension
extension PersonHistoryTableExtension on PersonTableCompanion {
  /// PersonHistoryTableCompanion
  PersonHistoryTableCompanion get companion {
    return PersonHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PlanDefinitionTableExtension
extension PlanDefinitionTableExtension on fhir.PlanDefinition {
  /// PlanDefinitionTableCompanion
  PlanDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PlanDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PlanDefinitionHistoryTableExtension
extension PlanDefinitionHistoryTableExtension on PlanDefinitionTableCompanion {
  /// PlanDefinitionHistoryTableCompanion
  PlanDefinitionHistoryTableCompanion get companion {
    return PlanDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PractitionerTableExtension
extension PractitionerTableExtension on fhir.Practitioner {
  /// PractitionerTableCompanion
  PractitionerTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PractitionerTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PractitionerHistoryTableExtension
extension PractitionerHistoryTableExtension on PractitionerTableCompanion {
  /// PractitionerHistoryTableCompanion
  PractitionerHistoryTableCompanion get companion {
    return PractitionerHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// PractitionerRoleTableExtension
extension PractitionerRoleTableExtension on fhir.PractitionerRole {
  /// PractitionerRoleTableCompanion
  PractitionerRoleTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return PractitionerRoleTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PractitionerRoleHistoryTableExtension
extension PractitionerRoleHistoryTableExtension
    on PractitionerRoleTableCompanion {
  /// PractitionerRoleHistoryTableCompanion
  PractitionerRoleHistoryTableCompanion get companion {
    return PractitionerRoleHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ProcedureTableExtension
extension ProcedureTableExtension on fhir.Procedure {
  /// ProcedureTableCompanion
  ProcedureTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Procedure;
    return ProcedureTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject.reference!.value!),
      code: Value(resource.code!.coding!.firstOrNull!.code!.value!),
      performedDateTime: Value(
        resource.performedX
            ?.isAs<fhir.FhirDateTime>()
            ?.valueDateTime
            ?.millisecondsSinceEpoch,
      ),
      status: Value(resource.status.value),
    );
  }
}

/// ProcedureHistoryTableExtension
extension ProcedureHistoryTableExtension on ProcedureTableCompanion {
  /// ProcedureHistoryTableCompanion
  ProcedureHistoryTableCompanion get companion {
    return ProcedureHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ProvenanceTableExtension
extension ProvenanceTableExtension on fhir.Provenance {
  /// ProvenanceTableCompanion
  ProvenanceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ProvenanceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ProvenanceHistoryTableExtension
extension ProvenanceHistoryTableExtension on ProvenanceTableCompanion {
  /// ProvenanceHistoryTableCompanion
  ProvenanceHistoryTableCompanion get companion {
    return ProvenanceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// QuestionnaireTableExtension
extension QuestionnaireTableExtension on fhir.Questionnaire {
  /// QuestionnaireTableCompanion
  QuestionnaireTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return QuestionnaireTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// QuestionnaireHistoryTableExtension
extension QuestionnaireHistoryTableExtension on QuestionnaireTableCompanion {
  /// QuestionnaireHistoryTableCompanion
  QuestionnaireHistoryTableCompanion get companion {
    return QuestionnaireHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// QuestionnaireResponseTableExtension
extension QuestionnaireResponseTableExtension on fhir.QuestionnaireResponse {
  /// QuestionnaireResponseTableCompanion
  QuestionnaireResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return QuestionnaireResponseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// QuestionnaireResponseHistoryTableExtension
extension QuestionnaireResponseHistoryTableExtension
    on QuestionnaireResponseTableCompanion {
  /// QuestionnaireResponseHistoryTableCompanion
  QuestionnaireResponseHistoryTableCompanion get companion {
    return QuestionnaireResponseHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// RegulatedAuthorizationTableExtension
extension RegulatedAuthorizationTableExtension on fhir.RegulatedAuthorization {
  /// RegulatedAuthorizationTableCompanion
  RegulatedAuthorizationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return RegulatedAuthorizationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// RegulatedAuthorizationHistoryTableExtension
extension RegulatedAuthorizationHistoryTableExtension
    on RegulatedAuthorizationTableCompanion {
  /// RegulatedAuthorizationHistoryTableCompanion
  RegulatedAuthorizationHistoryTableCompanion get companion {
    return RegulatedAuthorizationHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// RelatedPersonTableExtension
extension RelatedPersonTableExtension on fhir.RelatedPerson {
  /// RelatedPersonTableCompanion
  RelatedPersonTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return RelatedPersonTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// RelatedPersonHistoryTableExtension
extension RelatedPersonHistoryTableExtension on RelatedPersonTableCompanion {
  /// RelatedPersonHistoryTableCompanion
  RelatedPersonHistoryTableCompanion get companion {
    return RelatedPersonHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// RequestGroupTableExtension
extension RequestGroupTableExtension on fhir.RequestGroup {
  /// RequestGroupTableCompanion
  RequestGroupTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return RequestGroupTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// RequestGroupHistoryTableExtension
extension RequestGroupHistoryTableExtension on RequestGroupTableCompanion {
  /// RequestGroupHistoryTableCompanion
  RequestGroupHistoryTableCompanion get companion {
    return RequestGroupHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ResearchDefinitionTableExtension
extension ResearchDefinitionTableExtension on fhir.ResearchDefinition {
  /// ResearchDefinitionTableCompanion
  ResearchDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ResearchDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ResearchDefinitionHistoryTableExtension
extension ResearchDefinitionHistoryTableExtension
    on ResearchDefinitionTableCompanion {
  /// ResearchDefinitionHistoryTableCompanion
  ResearchDefinitionHistoryTableCompanion get companion {
    return ResearchDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ResearchElementDefinitionTableExtension
extension ResearchElementDefinitionTableExtension
    on fhir.ResearchElementDefinition {
  /// ResearchElementDefinitionTableCompanion
  ResearchElementDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ResearchElementDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ResearchElementDefinitionHistoryTableExtension
extension ResearchElementDefinitionHistoryTableExtension
    on ResearchElementDefinitionTableCompanion {
  /// ResearchElementDefinitionHistoryTableCompanion
  ResearchElementDefinitionHistoryTableCompanion get companion {
    return ResearchElementDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ResearchStudyTableExtension
extension ResearchStudyTableExtension on fhir.ResearchStudy {
  /// ResearchStudyTableCompanion
  ResearchStudyTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ResearchStudyTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ResearchStudyHistoryTableExtension
extension ResearchStudyHistoryTableExtension on ResearchStudyTableCompanion {
  /// ResearchStudyHistoryTableCompanion
  ResearchStudyHistoryTableCompanion get companion {
    return ResearchStudyHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ResearchSubjectTableExtension
extension ResearchSubjectTableExtension on fhir.ResearchSubject {
  /// ResearchSubjectTableCompanion
  ResearchSubjectTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ResearchSubjectTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ResearchSubjectHistoryTableExtension
extension ResearchSubjectHistoryTableExtension
    on ResearchSubjectTableCompanion {
  /// ResearchSubjectHistoryTableCompanion
  ResearchSubjectHistoryTableCompanion get companion {
    return ResearchSubjectHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// RiskAssessmentTableExtension
extension RiskAssessmentTableExtension on fhir.RiskAssessment {
  /// RiskAssessmentTableCompanion
  RiskAssessmentTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return RiskAssessmentTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// RiskAssessmentHistoryTableExtension
extension RiskAssessmentHistoryTableExtension on RiskAssessmentTableCompanion {
  /// RiskAssessmentHistoryTableCompanion
  RiskAssessmentHistoryTableCompanion get companion {
    return RiskAssessmentHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ScheduleTableExtension
extension ScheduleTableExtension on fhir.Schedule {
  /// ScheduleTableCompanion
  ScheduleTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ScheduleTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ScheduleHistoryTableExtension
extension ScheduleHistoryTableExtension on ScheduleTableCompanion {
  /// ScheduleHistoryTableCompanion
  ScheduleHistoryTableCompanion get companion {
    return ScheduleHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SearchParameterTableExtension
extension SearchParameterTableExtension on fhir.SearchParameter {
  /// SearchParameterTableCompanion
  SearchParameterTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SearchParameterTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SearchParameterHistoryTableExtension
extension SearchParameterHistoryTableExtension
    on SearchParameterTableCompanion {
  /// SearchParameterHistoryTableCompanion
  SearchParameterHistoryTableCompanion get companion {
    return SearchParameterHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ServiceRequestTableExtension
extension ServiceRequestTableExtension on fhir.ServiceRequest {
  /// ServiceRequestTableCompanion
  ServiceRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ServiceRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ServiceRequestHistoryTableExtension
extension ServiceRequestHistoryTableExtension on ServiceRequestTableCompanion {
  /// ServiceRequestHistoryTableCompanion
  ServiceRequestHistoryTableCompanion get companion {
    return ServiceRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SlotTableExtension
extension SlotTableExtension on fhir.Slot {
  /// SlotTableCompanion
  SlotTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SlotTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SlotHistoryTableExtension
extension SlotHistoryTableExtension on SlotTableCompanion {
  /// SlotHistoryTableCompanion
  SlotHistoryTableCompanion get companion {
    return SlotHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SpecimenTableExtension
extension SpecimenTableExtension on fhir.Specimen {
  /// SpecimenTableCompanion
  SpecimenTableCompanion get companion {
    final resource =
        newIdIfNoId().updateVersion(versionIdAsTime: true) as fhir.Specimen;
    return SpecimenTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
      patientId: Value(resource.subject?.reference?.value ?? ''),
      type: Value(resource.type!.coding!.firstOrNull!.code!.value!),
      collectedDateTime: Value(
        resource.collection?.collectedX
            ?.isAs<fhir.FhirDateTime>()
            ?.valueDateTime
            ?.millisecondsSinceEpoch,
      ),
      status: Value(resource.status?.value),
    );
  }
}

/// SpecimenHistoryTableExtension
extension SpecimenHistoryTableExtension on SpecimenTableCompanion {
  /// SpecimenHistoryTableCompanion
  SpecimenHistoryTableCompanion get companion {
    return SpecimenHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SpecimenDefinitionTableExtension
extension SpecimenDefinitionTableExtension on fhir.SpecimenDefinition {
  /// SpecimenDefinitionTableCompanion
  SpecimenDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SpecimenDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SpecimenDefinitionHistoryTableExtension
extension SpecimenDefinitionHistoryTableExtension
    on SpecimenDefinitionTableCompanion {
  /// SpecimenDefinitionHistoryTableCompanion
  SpecimenDefinitionHistoryTableCompanion get companion {
    return SpecimenDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// StructureDefinitionTableExtension
extension StructureDefinitionTableExtension on fhir.StructureDefinition {
  /// StructureDefinitionTableCompanion
  StructureDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return StructureDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// StructureDefinitionHistoryTableExtension
extension StructureDefinitionHistoryTableExtension
    on StructureDefinitionTableCompanion {
  /// StructureDefinitionHistoryTableCompanion
  StructureDefinitionHistoryTableCompanion get companion {
    return StructureDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// StructureMapTableExtension
extension StructureMapTableExtension on fhir.StructureMap {
  /// StructureMapTableCompanion
  StructureMapTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return StructureMapTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// StructureMapHistoryTableExtension
extension StructureMapHistoryTableExtension on StructureMapTableCompanion {
  /// StructureMapHistoryTableCompanion
  StructureMapHistoryTableCompanion get companion {
    return StructureMapHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SubscriptionTableExtension
extension SubscriptionTableExtension on fhir.Subscription {
  /// SubscriptionTableCompanion
  SubscriptionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SubscriptionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SubscriptionHistoryTableExtension
extension SubscriptionHistoryTableExtension on SubscriptionTableCompanion {
  /// SubscriptionHistoryTableCompanion
  SubscriptionHistoryTableCompanion get companion {
    return SubscriptionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SubscriptionStatusTableExtension
extension SubscriptionStatusTableExtension on fhir.SubscriptionStatus {
  /// SubscriptionStatusTableCompanion
  SubscriptionStatusTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SubscriptionStatusTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SubscriptionStatusHistoryTableExtension
extension SubscriptionStatusHistoryTableExtension
    on SubscriptionStatusTableCompanion {
  /// SubscriptionStatusHistoryTableCompanion
  SubscriptionStatusHistoryTableCompanion get companion {
    return SubscriptionStatusHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SubscriptionTopicTableExtension
extension SubscriptionTopicTableExtension on fhir.SubscriptionTopic {
  /// SubscriptionTopicTableCompanion
  SubscriptionTopicTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SubscriptionTopicTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SubscriptionTopicHistoryTableExtension
extension SubscriptionTopicHistoryTableExtension
    on SubscriptionTopicTableCompanion {
  /// SubscriptionTopicHistoryTableCompanion
  SubscriptionTopicHistoryTableCompanion get companion {
    return SubscriptionTopicHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SubstanceTableExtension
extension SubstanceTableExtension on fhir.Substance {
  /// SubstanceTableCompanion
  SubstanceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SubstanceTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SubstanceHistoryTableExtension
extension SubstanceHistoryTableExtension on SubstanceTableCompanion {
  /// SubstanceHistoryTableCompanion
  SubstanceHistoryTableCompanion get companion {
    return SubstanceHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SubstanceDefinitionTableExtension
extension SubstanceDefinitionTableExtension on fhir.SubstanceDefinition {
  /// SubstanceDefinitionTableCompanion
  SubstanceDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SubstanceDefinitionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SubstanceDefinitionHistoryTableExtension
extension SubstanceDefinitionHistoryTableExtension
    on SubstanceDefinitionTableCompanion {
  /// SubstanceDefinitionHistoryTableCompanion
  SubstanceDefinitionHistoryTableCompanion get companion {
    return SubstanceDefinitionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SupplyDeliveryTableExtension
extension SupplyDeliveryTableExtension on fhir.SupplyDelivery {
  /// SupplyDeliveryTableCompanion
  SupplyDeliveryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SupplyDeliveryTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SupplyDeliveryHistoryTableExtension
extension SupplyDeliveryHistoryTableExtension on SupplyDeliveryTableCompanion {
  /// SupplyDeliveryHistoryTableCompanion
  SupplyDeliveryHistoryTableCompanion get companion {
    return SupplyDeliveryHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// SupplyRequestTableExtension
extension SupplyRequestTableExtension on fhir.SupplyRequest {
  /// SupplyRequestTableCompanion
  SupplyRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return SupplyRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SupplyRequestHistoryTableExtension
extension SupplyRequestHistoryTableExtension on SupplyRequestTableCompanion {
  /// SupplyRequestHistoryTableCompanion
  SupplyRequestHistoryTableCompanion get companion {
    return SupplyRequestHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// TaskTableExtension
extension TaskTableExtension on fhir.Task {
  /// TaskTableCompanion
  TaskTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return TaskTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// TaskHistoryTableExtension
extension TaskHistoryTableExtension on TaskTableCompanion {
  /// TaskHistoryTableCompanion
  TaskHistoryTableCompanion get companion {
    return TaskHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// TerminologyCapabilitiesTableExtension
extension TerminologyCapabilitiesTableExtension
    on fhir.TerminologyCapabilities {
  /// TerminologyCapabilitiesTableCompanion
  TerminologyCapabilitiesTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return TerminologyCapabilitiesTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// TerminologyCapabilitiesHistoryTableExtension
extension TerminologyCapabilitiesHistoryTableExtension
    on TerminologyCapabilitiesTableCompanion {
  /// TerminologyCapabilitiesHistoryTableCompanion
  TerminologyCapabilitiesHistoryTableCompanion get companion {
    return TerminologyCapabilitiesHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// TestReportTableExtension
extension TestReportTableExtension on fhir.TestReport {
  /// TestReportTableCompanion
  TestReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return TestReportTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// TestReportHistoryTableExtension
extension TestReportHistoryTableExtension on TestReportTableCompanion {
  /// TestReportHistoryTableCompanion
  TestReportHistoryTableCompanion get companion {
    return TestReportHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// TestScriptTableExtension
extension TestScriptTableExtension on fhir.TestScript {
  /// TestScriptTableCompanion
  TestScriptTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return TestScriptTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// TestScriptHistoryTableExtension
extension TestScriptHistoryTableExtension on TestScriptTableCompanion {
  /// TestScriptHistoryTableCompanion
  TestScriptHistoryTableCompanion get companion {
    return TestScriptHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// ValueSetTableExtension
extension ValueSetTableExtension on fhir.ValueSet {
  /// ValueSetTableCompanion
  ValueSetTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return ValueSetTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ValueSetHistoryTableExtension
extension ValueSetHistoryTableExtension on ValueSetTableCompanion {
  /// ValueSetHistoryTableCompanion
  ValueSetHistoryTableCompanion get companion {
    return ValueSetHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// VerificationResultTableExtension
extension VerificationResultTableExtension on fhir.VerificationResult {
  /// VerificationResultTableCompanion
  VerificationResultTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return VerificationResultTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// VerificationResultHistoryTableExtension
extension VerificationResultHistoryTableExtension
    on VerificationResultTableCompanion {
  /// VerificationResultHistoryTableCompanion
  VerificationResultHistoryTableCompanion get companion {
    return VerificationResultHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}

/// VisionPrescriptionTableExtension
extension VisionPrescriptionTableExtension on fhir.VisionPrescription {
  /// VisionPrescriptionTableCompanion
  VisionPrescriptionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion(versionIdAsTime: true);
    return VisionPrescriptionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// VisionPrescriptionHistoryTableExtension
extension VisionPrescriptionHistoryTableExtension
    on VisionPrescriptionTableCompanion {
  /// VisionPrescriptionHistoryTableCompanion
  VisionPrescriptionHistoryTableCompanion get companion {
    return VisionPrescriptionHistoryTableCompanion(
      id: id,
      lastUpdated: lastUpdated,
      resource: resource,
    );
  }
}
