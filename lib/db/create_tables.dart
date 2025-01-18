// ignore_for_file: lines_longer_than_80_chars

part of 'db_service.dart';

/// Create tables in the database
void createTables(Database db) {
  _createAccountTables(db);
  _createActivityDefinitionTables(db);
  _createAdministrableProductDefinitionTables(db);
  _createAdverseEventTables(db);
  _createAllergyIntoleranceTables(db);
  _createAppointmentTables(db);
  _createAppointmentResponseTables(db);
  _createAuditEventTables(db);
  _createBasicTables(db);
  _createBinaryTables(db);
  _createBiologicallyDerivedProductTables(db);
  _createBodyStructureTables(db);
  _createBundleTables(db);
  _createCapabilityStatementTables(db);
  _createCarePlanTables(db);
  _createCareTeamTables(db);
  _createCatalogEntryTables(db);
  _createChargeItemTables(db);
  _createChargeItemDefinitionTables(db);
  _createCitationTables(db);
  _createClaimTables(db);
  _createClaimResponseTables(db);
  _createClinicalImpressionTables(db);
  _createClinicalUseDefinitionTables(db);
  _createCodeSystemTables(db);
  _createCommunicationTables(db);
  _createCommunicationRequestTables(db);
  _createCompartmentDefinitionTables(db);
  _createCompositionTables(db);
  _createConceptMapTables(db);
  _createConditionTables(db);
  _createConsentTables(db);
  _createContractTables(db);
  _createCoverageTables(db);
  _createCoverageEligibilityRequestTables(db);
  _createCoverageEligibilityResponseTables(db);
  _createDetectedIssueTables(db);
  _createDeviceTables(db);
  _createDeviceDefinitionTables(db);
  _createDeviceMetricTables(db);
  _createDeviceRequestTables(db);
  _createDeviceUseStatementTables(db);
  _createDiagnosticReportTables(db);
  _createDocumentManifestTables(db);
  _createDocumentReferenceTables(db);
  _createEncounterTables(db);
  _createEnrollmentRequestTables(db);
  _createEnrollmentResponseTables(db);
  _createEpisodeOfCareTables(db);
  _createEventDefinitionTables(db);
  _createEvidenceTables(db);
  _createEvidenceReportTables(db);
  _createEvidenceVariableTables(db);
  _createExampleScenarioTables(db);
  _createExplanationOfBenefitTables(db);
  _createFamilyMemberHistoryTables(db);
  _createEndpointTables(db);
  _createGroupTables(db);
  _createListTables(db);
  _createFlagTables(db);
  _createGoalTables(db);
  _createGraphDefinitionTables(db);
  _createGuidanceResponseTables(db);
  _createHealthcareServiceTables(db);
  _createImagingStudyTables(db);
  _createImmunizationTables(db);
  _createImmunizationEvaluationTables(db);
  _createImmunizationRecommendationTables(db);
  _createImplementationGuideTables(db);
  _createIngredientTables(db);
  _createInsurancePlanTables(db);
  _createInvoiceTables(db);
  _createLibraryTables(db);
  _createLinkageTables(db);
  _createLocationTables(db);
  _createManufacturedItemDefinitionTables(db);
  _createMeasureTables(db);
  _createMeasureReportTables(db);
  _createMediaTables(db);
  _createMedicationTables(db);
  _createMedicationAdministrationTables(db);
  _createMedicationDispenseTables(db);
  _createMedicationKnowledgeTables(db);
  _createMedicationRequestTables(db);
  _createMedicationStatementTables(db);
  _createMedicinalProductDefinitionTables(db);
  _createMessageDefinitionTables(db);
  _createMessageHeaderTables(db);
  _createMolecularSequenceTables(db);
  _createNamingSystemTables(db);
  _createNutritionOrderTables(db);
  _createNutritionProductTables(db);
  _createObservationTables(db);
  _createObservationDefinitionTables(db);
  _createOperationDefinitionTables(db);
  _createOperationOutcomeTables(db);
  _createOrganizationTables(db);
  _createOrganizationAffiliationTables(db);
  _createPackagedProductDefinitionTables(db);
  _createParametersTables(db);
  _createPatientTables(db);
  _createPaymentNoticeTables(db);
  _createPaymentReconciliationTables(db);
  _createPersonTables(db);
  _createPlanDefinitionTables(db);
  _createPractitionerTables(db);
  _createPractitionerRoleTables(db);
  _createProcedureTables(db);
  _createProvenanceTables(db);
  _createQuestionnaireTables(db);
  _createQuestionnaireResponseTables(db);
  _createRegulatedAuthorizationTables(db);
  _createRelatedPersonTables(db);
  _createRequestGroupTables(db);
  _createResearchDefinitionTables(db);
  _createResearchElementDefinitionTables(db);
  _createResearchStudyTables(db);
  _createResearchSubjectTables(db);
  _createRiskAssessmentTables(db);
  _createScheduleTables(db);
  _createSearchParameterTables(db);
  _createServiceRequestTables(db);
  _createSlotTables(db);
  _createSpecimenTables(db);
  _createSpecimenDefinitionTables(db);
  _createStructureDefinitionTables(db);
  _createStructureMapTables(db);
  _createSubscriptionTables(db);
  _createSubscriptionStatusTables(db);
  _createSubscriptionTopicTables(db);
  _createSubstanceTables(db);
  _createSubstanceDefinitionTables(db);
  _createSupplyDeliveryTables(db);
  _createSupplyRequestTables(db);
  _createTaskTables(db);
  _createTerminologyCapabilitiesTables(db);
  _createTestReportTables(db);
  _createTestScriptTables(db);
  _createValueSetTables(db);
  _createVerificationResultTables(db);
  _createVisionPrescriptionTables(db);
}

/// Create the primary and history tables for
/// [Account] resources
void _createAccountTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Account (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AccountHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ActivityDefinition] resources
void _createActivityDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ActivityDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ActivityDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [AdministrableProductDefinition] resources
void _createAdministrableProductDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS AdministrableProductDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AdministrableProductDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [AdverseEvent] resources
void _createAdverseEventTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS AdverseEvent (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AdverseEventHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [AllergyIntolerance] resources
void _createAllergyIntoleranceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS AllergyIntolerance (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AllergyIntoleranceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Appointment] resources
void _createAppointmentTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Appointment (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AppointmentHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [AppointmentResponse] resources
void _createAppointmentResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS AppointmentResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AppointmentResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [AuditEvent] resources
void _createAuditEventTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS AuditEvent (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AuditEventHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Basic] resources
void _createBasicTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Basic (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS BasicHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Binary] resources
void _createBinaryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Binary (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS BinaryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [BiologicallyDerivedProduct] resources
void _createBiologicallyDerivedProductTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS BiologicallyDerivedProduct (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS BiologicallyDerivedProductHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [BodyStructure] resources
void _createBodyStructureTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS BodyStructure (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS BodyStructureHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Bundle] resources
void _createBundleTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Bundle (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS BundleHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CapabilityStatement] resources
void _createCapabilityStatementTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CapabilityStatement (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_capability_statement_url ON CapabilityStatement (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_capability_statement_status ON CapabilityStatement (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS CapabilityStatementHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CarePlan] resources
void _createCarePlanTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CarePlan (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CarePlanHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CareTeam] resources
void _createCareTeamTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CareTeam (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CareTeamHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CatalogEntry] resources
void _createCatalogEntryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CatalogEntry (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CatalogEntryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ChargeItem] resources
void _createChargeItemTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ChargeItem (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ChargeItemHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ChargeItemDefinition] resources
void _createChargeItemDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ChargeItemDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ChargeItemDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Citation] resources
void _createCitationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Citation (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CitationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Claim] resources
void _createClaimTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Claim (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClaimHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ClaimResponse] resources
void _createClaimResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClaimResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClaimResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ClinicalImpression] resources
void _createClinicalImpressionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClinicalImpression (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClinicalImpressionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ClinicalUseDefinition] resources
void _createClinicalUseDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClinicalUseDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ClinicalUseDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CodeSystem] resources
void _createCodeSystemTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CodeSystem (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_code_system_url ON CodeSystem (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_code_system_status ON CodeSystem (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS CodeSystemHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Communication] resources
void _createCommunicationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Communication (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CommunicationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CommunicationRequest] resources
void _createCommunicationRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CommunicationRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CommunicationRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CompartmentDefinition] resources
void _createCompartmentDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CompartmentDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CompartmentDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Composition] resources
void _createCompositionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Composition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CompositionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ConceptMap] resources
void _createConceptMapTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConceptMap (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_concept_map_url ON ConceptMap (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_concept_map_status ON ConceptMap (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConceptMapHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Condition] resources
void _createConditionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Condition (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      clinicalStatus TEXT,
      verificationStatus TEXT,
      code TEXT NOT NULL,
      onsetDateTime DATETIME,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_condition_patientId ON Condition (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_condition_clinicalStatus ON Condition (clinicalStatus);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConditionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Consent] resources
void _createConsentTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Consent (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConsentHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Contract] resources
void _createContractTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Contract (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ContractHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Coverage] resources
void _createCoverageTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Coverage (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CoverageEligibilityRequest] resources
void _createCoverageEligibilityRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [CoverageEligibilityResponse] resources
void _createCoverageEligibilityResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DetectedIssue] resources
void _createDetectedIssueTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DetectedIssue (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DetectedIssueHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Device] resources
void _createDeviceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Device (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DeviceDefinition] resources
void _createDeviceDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DeviceMetric] resources
void _createDeviceMetricTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceMetric (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceMetricHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DeviceRequest] resources
void _createDeviceRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DeviceUseStatement] resources
void _createDeviceUseStatementTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceUseStatement (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceUseStatementHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DiagnosticReport] resources
void _createDiagnosticReportTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DiagnosticReport (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DiagnosticReportHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DocumentManifest] resources
void _createDocumentManifestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DocumentManifest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DocumentManifestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [DocumentReference] resources
void _createDocumentReferenceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DocumentReference (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DocumentReferenceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Encounter] resources
void _createEncounterTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Encounter (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      type TEXT NOT NULL,
      startDateTime DATETIME,
      endDateTime DATETIME,
      practitioner TEXT,
      organization TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_encounter_patientId ON Encounter (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_encounter_type ON Encounter (type);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS EncounterHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [EnrollmentRequest] resources
void _createEnrollmentRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EnrollmentRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EnrollmentRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [EnrollmentResponse] resources
void _createEnrollmentResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EnrollmentResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EnrollmentResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [EpisodeOfCare] resources
void _createEpisodeOfCareTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EpisodeOfCare (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EpisodeOfCareHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [EventDefinition] resources
void _createEventDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EventDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EventDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Evidence] resources
void _createEvidenceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Evidence (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [EvidenceReport] resources
void _createEvidenceReportTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceReport (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceReportHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [EvidenceVariable] resources
void _createEvidenceVariableTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceVariable (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceVariableHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ExampleScenario] resources
void _createExampleScenarioTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ExampleScenario (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ExampleScenarioHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ExplanationOfBenefit] resources
void _createExplanationOfBenefitTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ExplanationOfBenefit (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ExplanationOfBenefitHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [FamilyMemberHistory] resources
void _createFamilyMemberHistoryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS FamilyMemberHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS FamilyMemberHistoryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [FhirEndpoint] resources
void _createEndpointTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Endpoint (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EndpointHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [FhirGroup] resources
void _createGroupTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Group (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS GroupHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [List] resources
void _createListTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS List (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ListHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Flag] resources
void _createFlagTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Flag (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS FlagHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Goal] resources
void _createGoalTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Goal (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS GoalHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [GraphDefinition] resources
void _createGraphDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [GuidanceResponse] resources
void _createGuidanceResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS GuidanceResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS GuidanceResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [HealthcareService] resources
void _createHealthcareServiceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS HealthcareService (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS HealthcareServiceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ImagingStudy] resources
void _createImagingStudyTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImagingStudy (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImagingStudyHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Immunization] resources
void _createImmunizationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Immunization (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImmunizationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ImmunizationEvaluation] resources
void _createImmunizationEvaluationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImmunizationEvaluation (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImmunizationEvaluationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ImmunizationRecommendation] resources
void _createImmunizationRecommendationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImmunizationRecommendation (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImmunizationRecommendationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ImplementationGuide] resources
void _createImplementationGuideTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImplementationGuide (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_implementation_guide_url ON ImplementationGuide (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_implementation_guide_status ON ImplementationGuide (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImplementationGuideHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Ingredient] resources
void _createIngredientTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Ingredient (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS IngredientHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [InsurancePlan] resources
void _createInsurancePlanTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS InsurancePlan (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS InsurancePlanHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Invoice] resources
void _createInvoiceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Invoice (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS InvoiceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Library] resources
void _createLibraryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Library (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS LibraryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Linkage] resources
void _createLinkageTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Linkage (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS LinkageHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Location] resources
void _createLocationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Location (
      id TEXT PRIMARY KEY,
      name TEXT,
      type TEXT,
      address TEXT,
      managingOrganization TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_location_name ON Location (name);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS LocationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ManufacturedItemDefinition] resources
void _createManufacturedItemDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ManufacturedItemDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ManufacturedItemDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Measure] resources
void _createMeasureTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Measure (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MeasureHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MeasureReport] resources
void _createMeasureReportTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MeasureReport (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MeasureReportHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Media] resources
void _createMediaTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Media (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MediaHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Medication] resources
void _createMedicationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Medication (
      id TEXT PRIMARY KEY,
      code TEXT,
      status TEXT,
      manufacturer TEXT,
      form TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_medication_code ON Medication (code);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MedicationAdministration] resources
void _createMedicationAdministrationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationAdministration (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      dosage TEXT,
      effectiveDateTime DATETIME,
      status TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_med_admin_patientId ON MedicationAdministration (patientId);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationAdministrationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MedicationDispense] resources
void _createMedicationDispenseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationDispense (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      quantity TEXT,
      daysSupply INTEGER,
      status TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_med_disp_patientId ON MedicationDispense (patientId);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationDispenseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MedicationKnowledge] resources
void _createMedicationKnowledgeTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationKnowledge (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationKnowledgeHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MedicationRequest] resources
void _createMedicationRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationRequest (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      intent TEXT,
      priority TEXT,
      status TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_med_request_patientId ON MedicationRequest (patientId);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MedicationStatement] resources
void _createMedicationStatementTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationStatement (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationStatementHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MedicinalProductDefinition] resources
void _createMedicinalProductDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicinalProductDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicinalProductDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MessageDefinition] resources
void _createMessageDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MessageDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MessageDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MessageHeader] resources
void _createMessageHeaderTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MessageHeader (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MessageHeaderHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [MolecularSequence] resources
void _createMolecularSequenceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MolecularSequence (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MolecularSequenceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [NamingSystem] resources
void _createNamingSystemTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS NamingSystem (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_naming_system_url ON NamingSystem (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_naming_system_status ON NamingSystem (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS NamingSystemHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [NutritionOrder] resources
void _createNutritionOrderTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS NutritionOrder (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS NutritionOrderHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [NutritionProduct] resources
void _createNutritionProductTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS NutritionProduct (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS NutritionProductHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Observation] resources
void _createObservationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Observation (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      type TEXT NOT NULL,
      value TEXT,
      unit TEXT,
      effectiveDateTime DATETIME,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_observation_patientId ON Observation (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_observation_type ON Observation (type);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ObservationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ObservationDefinition] resources
void _createObservationDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ObservationDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ObservationDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [OperationDefinition] resources
void _createOperationDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS OperationDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS OperationDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [OperationOutcome] resources
void _createOperationOutcomeTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS OperationOutcome (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS OperationOutcomeHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Organization] resources
void _createOrganizationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Organization (
      id TEXT PRIMARY KEY,
      name TEXT,
      type TEXT,
      address TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_organization_name ON Organization (name);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS OrganizationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [OrganizationAffiliation] resources
void _createOrganizationAffiliationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS OrganizationAffiliation (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS OrganizationAffiliationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [PackagedProductDefinition] resources
void _createPackagedProductDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS PackagedProductDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PackagedProductDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Parameters] resources
void _createParametersTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Parameters (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ParametersHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Patient] resources
void _createPatientTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Patient (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL,
      active BOOLEAN,
      identifier TEXT,
      family_names TEXT,
      given_names TEXT,
      gender TEXT,
      birthDate DATETIME,
      deceased BOOLEAN,
      managingOrganization TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_patient_identifier ON Patient (identifier);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_patient_family_names ON Patient (family_names);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_patient_given_names ON Patient (given_names);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS PatientHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [PaymentNotice] resources
void _createPaymentNoticeTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS PaymentNotice (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PaymentNoticeHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [PaymentReconciliation] resources
void _createPaymentReconciliationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS PaymentReconciliation (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PaymentReconciliationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Person] resources
void _createPersonTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Person (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PersonHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [PlanDefinition] resources
void _createPlanDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS PlanDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PlanDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Practitioner] resources
void _createPractitionerTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Practitioner (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PractitionerHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [PractitionerRole] resources
void _createPractitionerRoleTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS PractitionerRole (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PractitionerRoleHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Procedure] resources
void _createProcedureTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Procedure (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      code TEXT NOT NULL,
      performedDateTime DATETIME,
      status TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_procedure_patientId ON Procedure (patientId);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ProcedureHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Provenance] resources
void _createProvenanceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Provenance (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ProvenanceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Questionnaire] resources
void _createQuestionnaireTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Questionnaire (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS QuestionnaireHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [QuestionnaireResponse] resources
void _createQuestionnaireResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS QuestionnaireResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS QuestionnaireResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [RegulatedAuthorization] resources
void _createRegulatedAuthorizationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS RegulatedAuthorization (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS RegulatedAuthorizationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [RelatedPerson] resources
void _createRelatedPersonTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS RelatedPerson (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS RelatedPersonHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [RequestGroup] resources
void _createRequestGroupTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS RequestGroup (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS RequestGroupHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ResearchDefinition] resources
void _createResearchDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ResearchElementDefinition] resources
void _createResearchElementDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchElementDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchElementDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ResearchStudy] resources
void _createResearchStudyTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchStudy (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchStudyHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ResearchSubject] resources
void _createResearchSubjectTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchSubject (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ResearchSubjectHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [RiskAssessment] resources
void _createRiskAssessmentTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS RiskAssessment (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS RiskAssessmentHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Schedule] resources
void _createScheduleTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Schedule (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ScheduleHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SearchParameter] resources
void _createSearchParameterTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SearchParameter (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SearchParameterHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ServiceRequest] resources
void _createServiceRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ServiceRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ServiceRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Slot] resources
void _createSlotTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Slot (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SlotHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Specimen] resources
void _createSpecimenTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Specimen (
      id TEXT PRIMARY KEY,
      patientId TEXT NOT NULL,
      type TEXT NOT NULL,
      collectedDateTime DATETIME,
      status TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_specimen_patientId ON Specimen (patientId);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS SpecimenHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SpecimenDefinition] resources
void _createSpecimenDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SpecimenDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SpecimenDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [StructureDefinition] resources
void _createStructureDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS StructureDefinition (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_structure_definition_url ON StructureDefinition (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_structure_definition_status ON StructureDefinition (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS StructureDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [StructureMap] resources
void _createStructureMapTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS StructureMap (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_structure_map_url ON StructureMap (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_structure_map_status ON StructureMap (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS StructureMapHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Subscription] resources
void _createSubscriptionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Subscription (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SubscriptionStatus] resources
void _createSubscriptionStatusTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionStatus (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionStatusHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SubscriptionTopic] resources
void _createSubscriptionTopicTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionTopic (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionTopicHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Substance] resources
void _createSubstanceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Substance (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubstanceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SubstanceDefinition] resources
void _createSubstanceDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubstanceDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubstanceDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SupplyDelivery] resources
void _createSupplyDeliveryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SupplyDelivery (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SupplyDeliveryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [SupplyRequest] resources
void _createSupplyRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SupplyRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS SupplyRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [Task] resources
void _createTaskTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Task (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS TaskHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [TerminologyCapabilities] resources
void _createTerminologyCapabilitiesTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS TerminologyCapabilities (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS TerminologyCapabilitiesHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [TestReport] resources
void _createTestReportTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS TestReport (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS TestReportHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [TestScript] resources
void _createTestScriptTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS TestScript (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS TestScriptHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [ValueSet] resources
void _createValueSetTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ValueSet (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_value_set_url ON ValueSet (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_value_set_status ON ValueSet (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ValueSetHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [VerificationResult] resources
void _createVerificationResultTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS VerificationResult (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS VerificationResultHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Create the primary and history tables for
/// [VisionPrescription] resources
void _createVisionPrescriptionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS VisionPrescription (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS VisionPrescriptionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}
