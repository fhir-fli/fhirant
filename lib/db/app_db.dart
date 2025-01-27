// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant/fhirant.dart';
import 'package:path/path.dart' as path;

part 'app_db.g.dart';

@DriftDatabase(
  tables: [
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
  ],
)
/// Database for the application
class AppDatabase extends _$AppDatabase {
  /// Creates an instance of the database
  AppDatabase() : super(_openConnection());

  /// Default database version for migrations
  @override
  int get schemaVersion => 1;

  /// Opens a connection to the database
  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = Directory.current;
      final file = File(path.join(dbFolder.path, 'app_database.sqlite'));
      return NativeDatabase(file);
    });
  }
}

/// AccountTableExtension
extension AccountTableExtension on fhir.Account {
  /// AccountTableCompanion
  AccountTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension AccountHistoryTableExtension on AccountDrift {
  /// AccountHistoryTableCompanion
  AccountHistoryTableCompanion get companion {
    return AccountHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ActivityDefinitionTableExtension
extension ActivityDefinitionTableExtension on fhir.ActivityDefinition {
  /// ActivityDefinitionTableCompanion
  ActivityDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ActivityDefinitionHistoryTableExtension on ActivityDefinitionDrift {
  /// ActivityDefinitionHistoryTableCompanion
  ActivityDefinitionHistoryTableCompanion get companion {
    return ActivityDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// AdministrableProductDefinitionTableExtension
extension AdministrableProductDefinitionTableExtension
    on fhir.AdministrableProductDefinition {
  /// AdministrableProductDefinitionTableCompanion
  AdministrableProductDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on AdministrableProductDefinitionDrift {
  /// AdministrableProductDefinitionHistoryTableCompanion
  AdministrableProductDefinitionHistoryTableCompanion get companion {
    return AdministrableProductDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// AdverseEventTableExtension
extension AdverseEventTableExtension on fhir.AdverseEvent {
  /// AdverseEventTableCompanion
  AdverseEventTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension AdverseEventHistoryTableExtension on AdverseEventDrift {
  /// AdverseEventHistoryTableCompanion
  AdverseEventHistoryTableCompanion get companion {
    return AdverseEventHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// AllergyIntoleranceTableExtension
extension AllergyIntoleranceTableExtension on fhir.AllergyIntolerance {
  /// AllergyIntoleranceTableCompanion
  AllergyIntoleranceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension AllergyIntoleranceHistoryTableExtension on AllergyIntoleranceDrift {
  /// AllergyIntoleranceHistoryTableCompanion
  AllergyIntoleranceHistoryTableCompanion get companion {
    return AllergyIntoleranceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// AppointmentTableExtension
extension AppointmentTableExtension on fhir.Appointment {
  /// AppointmentTableCompanion
  AppointmentTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension AppointmentHistoryTableExtension on AppointmentDrift {
  /// AppointmentHistoryTableCompanion
  AppointmentHistoryTableCompanion get companion {
    return AppointmentHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// AppointmentResponseTableExtension
extension AppointmentResponseTableExtension on fhir.AppointmentResponse {
  /// AppointmentResponseTableCompanion
  AppointmentResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension AppointmentResponseHistoryTableExtension on AppointmentResponseDrift {
  /// AppointmentResponseHistoryTableCompanion
  AppointmentResponseHistoryTableCompanion get companion {
    return AppointmentResponseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// AuditEventTableExtension
extension AuditEventTableExtension on fhir.AuditEvent {
  /// AuditEventTableCompanion
  AuditEventTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension AuditEventHistoryTableExtension on AuditEventDrift {
  /// AuditEventHistoryTableCompanion
  AuditEventHistoryTableCompanion get companion {
    return AuditEventHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// BasicTableExtension
extension BasicTableExtension on fhir.Basic {
  /// BasicTableCompanion
  BasicTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension BasicHistoryTableExtension on BasicDrift {
  /// BasicHistoryTableCompanion
  BasicHistoryTableCompanion get companion {
    return BasicHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// BinaryTableExtension
extension BinaryTableExtension on fhir.Binary {
  /// BinaryTableCompanion
  BinaryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension BinaryHistoryTableExtension on BinaryDrift {
  /// BinaryHistoryTableCompanion
  BinaryHistoryTableCompanion get companion {
    return BinaryHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// BiologicallyDerivedProductTableExtension
extension BiologicallyDerivedProductTableExtension
    on fhir.BiologicallyDerivedProduct {
  /// BiologicallyDerivedProductTableCompanion
  BiologicallyDerivedProductTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on BiologicallyDerivedProductDrift {
  /// BiologicallyDerivedProductHistoryTableCompanion
  BiologicallyDerivedProductHistoryTableCompanion get companion {
    return BiologicallyDerivedProductHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// BodyStructureTableExtension
extension BodyStructureTableExtension on fhir.BodyStructure {
  /// BodyStructureTableCompanion
  BodyStructureTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension BodyStructureHistoryTableExtension on BodyStructureDrift {
  /// BodyStructureHistoryTableCompanion
  BodyStructureHistoryTableCompanion get companion {
    return BodyStructureHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// BundleTableExtension
extension BundleTableExtension on fhir.Bundle {
  /// BundleTableCompanion
  BundleTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension BundleHistoryTableExtension on BundleDrift {
  /// BundleHistoryTableCompanion
  BundleHistoryTableCompanion get companion {
    return BundleHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CapabilityStatementTableExtension
extension CapabilityStatementTableExtension on fhir.CapabilityStatement {
  /// CapabilityStatementTableCompanion
  CapabilityStatementTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CapabilityStatementHistoryTableExtension on CapabilityStatementDrift {
  /// CapabilityStatementHistoryTableCompanion
  CapabilityStatementHistoryTableCompanion get companion {
    return CapabilityStatementHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CarePlanTableExtension
extension CarePlanTableExtension on fhir.CarePlan {
  /// CarePlanTableCompanion
  CarePlanTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CarePlanHistoryTableExtension on CarePlanDrift {
  /// CarePlanHistoryTableCompanion
  CarePlanHistoryTableCompanion get companion {
    return CarePlanHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CareTeamTableExtension
extension CareTeamTableExtension on fhir.CareTeam {
  /// CareTeamTableCompanion
  CareTeamTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CareTeamHistoryTableExtension on CareTeamDrift {
  /// CareTeamHistoryTableCompanion
  CareTeamHistoryTableCompanion get companion {
    return CareTeamHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CatalogEntryTableExtension
extension CatalogEntryTableExtension on fhir.CatalogEntry {
  /// CatalogEntryTableCompanion
  CatalogEntryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CatalogEntryHistoryTableExtension on CatalogEntryDrift {
  /// CatalogEntryHistoryTableCompanion
  CatalogEntryHistoryTableCompanion get companion {
    return CatalogEntryHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ChargeItemTableExtension
extension ChargeItemTableExtension on fhir.ChargeItem {
  /// ChargeItemTableCompanion
  ChargeItemTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ChargeItemHistoryTableExtension on ChargeItemDrift {
  /// ChargeItemHistoryTableCompanion
  ChargeItemHistoryTableCompanion get companion {
    return ChargeItemHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ChargeItemDefinitionTableExtension
extension ChargeItemDefinitionTableExtension on fhir.ChargeItemDefinition {
  /// ChargeItemDefinitionTableCompanion
  ChargeItemDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ChargeItemDefinitionDrift {
  /// ChargeItemDefinitionHistoryTableCompanion
  ChargeItemDefinitionHistoryTableCompanion get companion {
    return ChargeItemDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CitationTableExtension
extension CitationTableExtension on fhir.Citation {
  /// CitationTableCompanion
  CitationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CitationHistoryTableExtension on CitationDrift {
  /// CitationHistoryTableCompanion
  CitationHistoryTableCompanion get companion {
    return CitationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ClaimTableExtension
extension ClaimTableExtension on fhir.Claim {
  /// ClaimTableCompanion
  ClaimTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ClaimHistoryTableExtension on ClaimDrift {
  /// ClaimHistoryTableCompanion
  ClaimHistoryTableCompanion get companion {
    return ClaimHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ClaimResponseTableExtension
extension ClaimResponseTableExtension on fhir.ClaimResponse {
  /// ClaimResponseTableCompanion
  ClaimResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ClaimResponseHistoryTableExtension on ClaimResponseDrift {
  /// ClaimResponseHistoryTableCompanion
  ClaimResponseHistoryTableCompanion get companion {
    return ClaimResponseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ClinicalImpressionTableExtension
extension ClinicalImpressionTableExtension on fhir.ClinicalImpression {
  /// ClinicalImpressionTableCompanion
  ClinicalImpressionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ClinicalImpressionHistoryTableExtension on ClinicalImpressionDrift {
  /// ClinicalImpressionHistoryTableCompanion
  ClinicalImpressionHistoryTableCompanion get companion {
    return ClinicalImpressionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ClinicalUseDefinitionTableExtension
extension ClinicalUseDefinitionTableExtension on fhir.ClinicalUseDefinition {
  /// ClinicalUseDefinitionTableCompanion
  ClinicalUseDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ClinicalUseDefinitionDrift {
  /// ClinicalUseDefinitionHistoryTableCompanion
  ClinicalUseDefinitionHistoryTableCompanion get companion {
    return ClinicalUseDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CodeSystemTableExtension
extension CodeSystemTableExtension on fhir.CodeSystem {
  /// CodeSystemTableCompanion
  CodeSystemTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CodeSystemHistoryTableExtension on CodeSystemDrift {
  /// CodeSystemHistoryTableCompanion
  CodeSystemHistoryTableCompanion get companion {
    return CodeSystemHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CommunicationTableExtension
extension CommunicationTableExtension on fhir.Communication {
  /// CommunicationTableCompanion
  CommunicationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CommunicationHistoryTableExtension on CommunicationDrift {
  /// CommunicationHistoryTableCompanion
  CommunicationHistoryTableCompanion get companion {
    return CommunicationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CommunicationRequestTableExtension
extension CommunicationRequestTableExtension on fhir.CommunicationRequest {
  /// CommunicationRequestTableCompanion
  CommunicationRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on CommunicationRequestDrift {
  /// CommunicationRequestHistoryTableCompanion
  CommunicationRequestHistoryTableCompanion get companion {
    return CommunicationRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CompartmentDefinitionTableExtension
extension CompartmentDefinitionTableExtension on fhir.CompartmentDefinition {
  /// CompartmentDefinitionTableCompanion
  CompartmentDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on CompartmentDefinitionDrift {
  /// CompartmentDefinitionHistoryTableCompanion
  CompartmentDefinitionHistoryTableCompanion get companion {
    return CompartmentDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CompositionTableExtension
extension CompositionTableExtension on fhir.Composition {
  /// CompositionTableCompanion
  CompositionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CompositionHistoryTableExtension on CompositionDrift {
  /// CompositionHistoryTableCompanion
  CompositionHistoryTableCompanion get companion {
    return CompositionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ConceptMapTableExtension
extension ConceptMapTableExtension on fhir.ConceptMap {
  /// ConceptMapTableCompanion
  ConceptMapTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ConceptMapHistoryTableExtension on ConceptMapDrift {
  /// ConceptMapHistoryTableCompanion
  ConceptMapHistoryTableCompanion get companion {
    return ConceptMapHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ConditionTableExtension
extension ConditionTableExtension on fhir.Condition {
  /// ConditionTableCompanion
  ConditionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return ConditionTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ConditionHistoryTableExtension
extension ConditionHistoryTableExtension on ConditionDrift {
  /// ConditionHistoryTableCompanion
  ConditionHistoryTableCompanion get companion {
    return ConditionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ConsentTableExtension
extension ConsentTableExtension on fhir.Consent {
  /// ConsentTableCompanion
  ConsentTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ConsentHistoryTableExtension on ConsentDrift {
  /// ConsentHistoryTableCompanion
  ConsentHistoryTableCompanion get companion {
    return ConsentHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ContractTableExtension
extension ContractTableExtension on fhir.Contract {
  /// ContractTableCompanion
  ContractTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ContractHistoryTableExtension on ContractDrift {
  /// ContractHistoryTableCompanion
  ContractHistoryTableCompanion get companion {
    return ContractHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CoverageTableExtension
extension CoverageTableExtension on fhir.Coverage {
  /// CoverageTableCompanion
  CoverageTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension CoverageHistoryTableExtension on CoverageDrift {
  /// CoverageHistoryTableCompanion
  CoverageHistoryTableCompanion get companion {
    return CoverageHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CoverageEligibilityRequestTableExtension
extension CoverageEligibilityRequestTableExtension
    on fhir.CoverageEligibilityRequest {
  /// CoverageEligibilityRequestTableCompanion
  CoverageEligibilityRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on CoverageEligibilityRequestDrift {
  /// CoverageEligibilityRequestHistoryTableCompanion
  CoverageEligibilityRequestHistoryTableCompanion get companion {
    return CoverageEligibilityRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// CoverageEligibilityResponseTableExtension
extension CoverageEligibilityResponseTableExtension
    on fhir.CoverageEligibilityResponse {
  /// CoverageEligibilityResponseTableCompanion
  CoverageEligibilityResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on CoverageEligibilityResponseDrift {
  /// CoverageEligibilityResponseHistoryTableCompanion
  CoverageEligibilityResponseHistoryTableCompanion get companion {
    return CoverageEligibilityResponseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DetectedIssueTableExtension
extension DetectedIssueTableExtension on fhir.DetectedIssue {
  /// DetectedIssueTableCompanion
  DetectedIssueTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DetectedIssueHistoryTableExtension on DetectedIssueDrift {
  /// DetectedIssueHistoryTableCompanion
  DetectedIssueHistoryTableCompanion get companion {
    return DetectedIssueHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DeviceTableExtension
extension DeviceTableExtension on fhir.Device {
  /// DeviceTableCompanion
  DeviceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DeviceHistoryTableExtension on DeviceDrift {
  /// DeviceHistoryTableCompanion
  DeviceHistoryTableCompanion get companion {
    return DeviceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DeviceDefinitionTableExtension
extension DeviceDefinitionTableExtension on fhir.DeviceDefinition {
  /// DeviceDefinitionTableCompanion
  DeviceDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DeviceDefinitionHistoryTableExtension on DeviceDefinitionDrift {
  /// DeviceDefinitionHistoryTableCompanion
  DeviceDefinitionHistoryTableCompanion get companion {
    return DeviceDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DeviceMetricTableExtension
extension DeviceMetricTableExtension on fhir.DeviceMetric {
  /// DeviceMetricTableCompanion
  DeviceMetricTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DeviceMetricHistoryTableExtension on DeviceMetricDrift {
  /// DeviceMetricHistoryTableCompanion
  DeviceMetricHistoryTableCompanion get companion {
    return DeviceMetricHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DeviceRequestTableExtension
extension DeviceRequestTableExtension on fhir.DeviceRequest {
  /// DeviceRequestTableCompanion
  DeviceRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DeviceRequestHistoryTableExtension on DeviceRequestDrift {
  /// DeviceRequestHistoryTableCompanion
  DeviceRequestHistoryTableCompanion get companion {
    return DeviceRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DeviceUseStatementTableExtension
extension DeviceUseStatementTableExtension on fhir.DeviceUseStatement {
  /// DeviceUseStatementTableCompanion
  DeviceUseStatementTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DeviceUseStatementHistoryTableExtension on DeviceUseStatementDrift {
  /// DeviceUseStatementHistoryTableCompanion
  DeviceUseStatementHistoryTableCompanion get companion {
    return DeviceUseStatementHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DiagnosticReportTableExtension
extension DiagnosticReportTableExtension on fhir.DiagnosticReport {
  /// DiagnosticReportTableCompanion
  DiagnosticReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DiagnosticReportHistoryTableExtension on DiagnosticReportDrift {
  /// DiagnosticReportHistoryTableCompanion
  DiagnosticReportHistoryTableCompanion get companion {
    return DiagnosticReportHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DocumentManifestTableExtension
extension DocumentManifestTableExtension on fhir.DocumentManifest {
  /// DocumentManifestTableCompanion
  DocumentManifestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DocumentManifestHistoryTableExtension on DocumentManifestDrift {
  /// DocumentManifestHistoryTableCompanion
  DocumentManifestHistoryTableCompanion get companion {
    return DocumentManifestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// DocumentReferenceTableExtension
extension DocumentReferenceTableExtension on fhir.DocumentReference {
  /// DocumentReferenceTableCompanion
  DocumentReferenceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension DocumentReferenceHistoryTableExtension on DocumentReferenceDrift {
  /// DocumentReferenceHistoryTableCompanion
  DocumentReferenceHistoryTableCompanion get companion {
    return DocumentReferenceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EncounterTableExtension
extension EncounterTableExtension on fhir.Encounter {
  /// EncounterTableCompanion
  EncounterTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return EncounterTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// EncounterHistoryTableExtension
extension EncounterHistoryTableExtension on EncounterDrift {
  /// EncounterHistoryTableCompanion
  EncounterHistoryTableCompanion get companion {
    return EncounterHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EnrollmentRequestTableExtension
extension EnrollmentRequestTableExtension on fhir.EnrollmentRequest {
  /// EnrollmentRequestTableCompanion
  EnrollmentRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EnrollmentRequestHistoryTableExtension on EnrollmentRequestDrift {
  /// EnrollmentRequestHistoryTableCompanion
  EnrollmentRequestHistoryTableCompanion get companion {
    return EnrollmentRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EnrollmentResponseTableExtension
extension EnrollmentResponseTableExtension on fhir.EnrollmentResponse {
  /// EnrollmentResponseTableCompanion
  EnrollmentResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EnrollmentResponseHistoryTableExtension on EnrollmentResponseDrift {
  /// EnrollmentResponseHistoryTableCompanion
  EnrollmentResponseHistoryTableCompanion get companion {
    return EnrollmentResponseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EpisodeOfCareTableExtension
extension EpisodeOfCareTableExtension on fhir.EpisodeOfCare {
  /// EpisodeOfCareTableCompanion
  EpisodeOfCareTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EpisodeOfCareHistoryTableExtension on EpisodeOfCareDrift {
  /// EpisodeOfCareHistoryTableCompanion
  EpisodeOfCareHistoryTableCompanion get companion {
    return EpisodeOfCareHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EventDefinitionTableExtension
extension EventDefinitionTableExtension on fhir.EventDefinition {
  /// EventDefinitionTableCompanion
  EventDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EventDefinitionHistoryTableExtension on EventDefinitionDrift {
  /// EventDefinitionHistoryTableCompanion
  EventDefinitionHistoryTableCompanion get companion {
    return EventDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EvidenceTableExtension
extension EvidenceTableExtension on fhir.Evidence {
  /// EvidenceTableCompanion
  EvidenceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EvidenceHistoryTableExtension on EvidenceDrift {
  /// EvidenceHistoryTableCompanion
  EvidenceHistoryTableCompanion get companion {
    return EvidenceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EvidenceReportTableExtension
extension EvidenceReportTableExtension on fhir.EvidenceReport {
  /// EvidenceReportTableCompanion
  EvidenceReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EvidenceReportHistoryTableExtension on EvidenceReportDrift {
  /// EvidenceReportHistoryTableCompanion
  EvidenceReportHistoryTableCompanion get companion {
    return EvidenceReportHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EvidenceVariableTableExtension
extension EvidenceVariableTableExtension on fhir.EvidenceVariable {
  /// EvidenceVariableTableCompanion
  EvidenceVariableTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EvidenceVariableHistoryTableExtension on EvidenceVariableDrift {
  /// EvidenceVariableHistoryTableCompanion
  EvidenceVariableHistoryTableCompanion get companion {
    return EvidenceVariableHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ExampleScenarioTableExtension
extension ExampleScenarioTableExtension on fhir.ExampleScenario {
  /// ExampleScenarioTableCompanion
  ExampleScenarioTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ExampleScenarioHistoryTableExtension on ExampleScenarioDrift {
  /// ExampleScenarioHistoryTableCompanion
  ExampleScenarioHistoryTableCompanion get companion {
    return ExampleScenarioHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ExplanationOfBenefitTableExtension
extension ExplanationOfBenefitTableExtension on fhir.ExplanationOfBenefit {
  /// ExplanationOfBenefitTableCompanion
  ExplanationOfBenefitTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ExplanationOfBenefitDrift {
  /// ExplanationOfBenefitHistoryTableCompanion
  ExplanationOfBenefitHistoryTableCompanion get companion {
    return ExplanationOfBenefitHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// FamilyMemberHistoryTableExtension
extension FamilyMemberHistoryTableExtension on fhir.FamilyMemberHistory {
  /// FamilyMemberHistoryTableCompanion
  FamilyMemberHistoryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension FamilyMemberHistoryHistoryTableExtension on FamilyMemberHistoryDrift {
  /// FamilyMemberHistoryHistoryTableCompanion
  FamilyMemberHistoryHistoryTableCompanion get companion {
    return FamilyMemberHistoryHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// EndpointTableExtension
extension EndpointTableExtension on fhir.FhirEndpoint {
  /// EndpointTableCompanion
  FhirEndpointTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension EndpointHistoryTableExtension on FhirEndpointDrift {
  /// EndpointHistoryTableCompanion
  FhirEndpointHistoryTableCompanion get companion {
    return FhirEndpointHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// GroupTableExtension
extension GroupTableExtension on fhir.FhirGroup {
  /// GroupTableCompanion
  FhirGroupTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension GroupHistoryTableExtension on FhirGroupDrift {
  /// GroupHistoryTableCompanion
  FhirGroupHistoryTableCompanion get companion {
    return FhirGroupHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ListTableExtension
extension ListTableExtension on fhir.FhirList {
  /// ListTableCompanion
  FhirListTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ListHistoryTableExtension on FhirListDrift {
  /// ListHistoryTableCompanion
  FhirListHistoryTableCompanion get companion {
    return FhirListHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// FlagTableExtension
extension FlagTableExtension on fhir.Flag {
  /// FlagTableCompanion
  FlagTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension FlagHistoryTableExtension on FlagDrift {
  /// FlagHistoryTableCompanion
  FlagHistoryTableCompanion get companion {
    return FlagHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// GoalTableExtension
extension GoalTableExtension on fhir.Goal {
  /// GoalTableCompanion
  GoalTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension GoalHistoryTableExtension on GoalDrift {
  /// GoalHistoryTableCompanion
  GoalHistoryTableCompanion get companion {
    return GoalHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// GraphDefinitionTableExtension
extension GraphDefinitionTableExtension on fhir.GraphDefinition {
  /// GraphDefinitionTableCompanion
  GraphDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension GraphDefinitionHistoryTableExtension on GraphDefinitionDrift {
  /// GraphDefinitionHistoryTableCompanion
  GraphDefinitionHistoryTableCompanion get companion {
    return GraphDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// GuidanceResponseTableExtension
extension GuidanceResponseTableExtension on fhir.GuidanceResponse {
  /// GuidanceResponseTableCompanion
  GuidanceResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension GuidanceResponseHistoryTableExtension on GuidanceResponseDrift {
  /// GuidanceResponseHistoryTableCompanion
  GuidanceResponseHistoryTableCompanion get companion {
    return GuidanceResponseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// HealthcareServiceTableExtension
extension HealthcareServiceTableExtension on fhir.HealthcareService {
  /// HealthcareServiceTableCompanion
  HealthcareServiceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension HealthcareServiceHistoryTableExtension on HealthcareServiceDrift {
  /// HealthcareServiceHistoryTableCompanion
  HealthcareServiceHistoryTableCompanion get companion {
    return HealthcareServiceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ImagingStudyTableExtension
extension ImagingStudyTableExtension on fhir.ImagingStudy {
  /// ImagingStudyTableCompanion
  ImagingStudyTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ImagingStudyHistoryTableExtension on ImagingStudyDrift {
  /// ImagingStudyHistoryTableCompanion
  ImagingStudyHistoryTableCompanion get companion {
    return ImagingStudyHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ImmunizationTableExtension
extension ImmunizationTableExtension on fhir.Immunization {
  /// ImmunizationTableCompanion
  ImmunizationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ImmunizationHistoryTableExtension on ImmunizationDrift {
  /// ImmunizationHistoryTableCompanion
  ImmunizationHistoryTableCompanion get companion {
    return ImmunizationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ImmunizationEvaluationTableExtension
extension ImmunizationEvaluationTableExtension on fhir.ImmunizationEvaluation {
  /// ImmunizationEvaluationTableCompanion
  ImmunizationEvaluationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ImmunizationEvaluationDrift {
  /// ImmunizationEvaluationHistoryTableCompanion
  ImmunizationEvaluationHistoryTableCompanion get companion {
    return ImmunizationEvaluationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ImmunizationRecommendationTableExtension
extension ImmunizationRecommendationTableExtension
    on fhir.ImmunizationRecommendation {
  /// ImmunizationRecommendationTableCompanion
  ImmunizationRecommendationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ImmunizationRecommendationDrift {
  /// ImmunizationRecommendationHistoryTableCompanion
  ImmunizationRecommendationHistoryTableCompanion get companion {
    return ImmunizationRecommendationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ImplementationGuideTableExtension
extension ImplementationGuideTableExtension on fhir.ImplementationGuide {
  /// ImplementationGuideTableCompanion
  ImplementationGuideTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ImplementationGuideHistoryTableExtension on ImplementationGuideDrift {
  /// ImplementationGuideHistoryTableCompanion
  ImplementationGuideHistoryTableCompanion get companion {
    return ImplementationGuideHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// IngredientTableExtension
extension IngredientTableExtension on fhir.Ingredient {
  /// IngredientTableCompanion
  IngredientTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension IngredientHistoryTableExtension on IngredientDrift {
  /// IngredientHistoryTableCompanion
  IngredientHistoryTableCompanion get companion {
    return IngredientHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// InsurancePlanTableExtension
extension InsurancePlanTableExtension on fhir.InsurancePlan {
  /// InsurancePlanTableCompanion
  InsurancePlanTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension InsurancePlanHistoryTableExtension on InsurancePlanDrift {
  /// InsurancePlanHistoryTableCompanion
  InsurancePlanHistoryTableCompanion get companion {
    return InsurancePlanHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// InvoiceTableExtension
extension InvoiceTableExtension on fhir.Invoice {
  /// InvoiceTableCompanion
  InvoiceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension InvoiceHistoryTableExtension on InvoiceDrift {
  /// InvoiceHistoryTableCompanion
  InvoiceHistoryTableCompanion get companion {
    return InvoiceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// LibraryTableExtension
extension LibraryTableExtension on fhir.Library {
  /// LibraryTableCompanion
  LibraryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension LibraryHistoryTableExtension on LibraryDrift {
  /// LibraryHistoryTableCompanion
  LibraryHistoryTableCompanion get companion {
    return LibraryHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// LinkageTableExtension
extension LinkageTableExtension on fhir.Linkage {
  /// LinkageTableCompanion
  LinkageTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension LinkageHistoryTableExtension on LinkageDrift {
  /// LinkageHistoryTableCompanion
  LinkageHistoryTableCompanion get companion {
    return LinkageHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// LocationTableExtension
extension LocationTableExtension on fhir.Location {
  /// LocationTableCompanion
  LocationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return LocationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// LocationHistoryTableExtension
extension LocationHistoryTableExtension on LocationDrift {
  /// LocationHistoryTableCompanion
  LocationHistoryTableCompanion get companion {
    return LocationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ManufacturedItemDefinitionTableExtension
extension ManufacturedItemDefinitionTableExtension
    on fhir.ManufacturedItemDefinition {
  /// ManufacturedItemDefinitionTableCompanion
  ManufacturedItemDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ManufacturedItemDefinitionDrift {
  /// ManufacturedItemDefinitionHistoryTableCompanion
  ManufacturedItemDefinitionHistoryTableCompanion get companion {
    return ManufacturedItemDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MeasureTableExtension
extension MeasureTableExtension on fhir.Measure {
  /// MeasureTableCompanion
  MeasureTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MeasureHistoryTableExtension on MeasureDrift {
  /// MeasureHistoryTableCompanion
  MeasureHistoryTableCompanion get companion {
    return MeasureHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MeasureReportTableExtension
extension MeasureReportTableExtension on fhir.MeasureReport {
  /// MeasureReportTableCompanion
  MeasureReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MeasureReportHistoryTableExtension on MeasureReportDrift {
  /// MeasureReportHistoryTableCompanion
  MeasureReportHistoryTableCompanion get companion {
    return MeasureReportHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MediaTableExtension
extension MediaTableExtension on fhir.Media {
  /// MediaTableCompanion
  MediaTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MediaHistoryTableExtension on MediaDrift {
  /// MediaHistoryTableCompanion
  MediaHistoryTableCompanion get companion {
    return MediaHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicationTableExtension
extension MedicationTableExtension on fhir.Medication {
  /// MedicationTableCompanion
  MedicationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return MedicationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicationHistoryTableExtension
extension MedicationHistoryTableExtension on MedicationDrift {
  /// MedicationHistoryTableCompanion
  MedicationHistoryTableCompanion get companion {
    return MedicationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicationAdministrationTableExtension
extension MedicationAdministrationTableExtension
    on fhir.MedicationAdministration {
  /// MedicationAdministrationTableCompanion
  MedicationAdministrationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return MedicationAdministrationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicationAdministrationHistoryTableExtension
extension MedicationAdministrationHistoryTableExtension
    on MedicationAdministrationDrift {
  /// MedicationAdministrationHistoryTableCompanion
  MedicationAdministrationHistoryTableCompanion get companion {
    return MedicationAdministrationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicationDispenseTableExtension
extension MedicationDispenseTableExtension on fhir.MedicationDispense {
  /// MedicationDispenseTableCompanion
  MedicationDispenseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return MedicationDispenseTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicationDispenseHistoryTableExtension
extension MedicationDispenseHistoryTableExtension on MedicationDispenseDrift {
  /// MedicationDispenseHistoryTableCompanion
  MedicationDispenseHistoryTableCompanion get companion {
    return MedicationDispenseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicationKnowledgeTableExtension
extension MedicationKnowledgeTableExtension on fhir.MedicationKnowledge {
  /// MedicationKnowledgeTableCompanion
  MedicationKnowledgeTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MedicationKnowledgeHistoryTableExtension on MedicationKnowledgeDrift {
  /// MedicationKnowledgeHistoryTableCompanion
  MedicationKnowledgeHistoryTableCompanion get companion {
    return MedicationKnowledgeHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicationRequestTableExtension
extension MedicationRequestTableExtension on fhir.MedicationRequest {
  /// MedicationRequestTableCompanion
  MedicationRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return MedicationRequestTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// MedicationRequestHistoryTableExtension
extension MedicationRequestHistoryTableExtension on MedicationRequestDrift {
  /// MedicationRequestHistoryTableCompanion
  MedicationRequestHistoryTableCompanion get companion {
    return MedicationRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicationStatementTableExtension
extension MedicationStatementTableExtension on fhir.MedicationStatement {
  /// MedicationStatementTableCompanion
  MedicationStatementTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MedicationStatementHistoryTableExtension on MedicationStatementDrift {
  /// MedicationStatementHistoryTableCompanion
  MedicationStatementHistoryTableCompanion get companion {
    return MedicationStatementHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MedicinalProductDefinitionTableExtension
extension MedicinalProductDefinitionTableExtension
    on fhir.MedicinalProductDefinition {
  /// MedicinalProductDefinitionTableCompanion
  MedicinalProductDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on MedicinalProductDefinitionDrift {
  /// MedicinalProductDefinitionHistoryTableCompanion
  MedicinalProductDefinitionHistoryTableCompanion get companion {
    return MedicinalProductDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MessageDefinitionTableExtension
extension MessageDefinitionTableExtension on fhir.MessageDefinition {
  /// MessageDefinitionTableCompanion
  MessageDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MessageDefinitionHistoryTableExtension on MessageDefinitionDrift {
  /// MessageDefinitionHistoryTableCompanion
  MessageDefinitionHistoryTableCompanion get companion {
    return MessageDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MessageHeaderTableExtension
extension MessageHeaderTableExtension on fhir.MessageHeader {
  /// MessageHeaderTableCompanion
  MessageHeaderTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MessageHeaderHistoryTableExtension on MessageHeaderDrift {
  /// MessageHeaderHistoryTableCompanion
  MessageHeaderHistoryTableCompanion get companion {
    return MessageHeaderHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// MolecularSequenceTableExtension
extension MolecularSequenceTableExtension on fhir.MolecularSequence {
  /// MolecularSequenceTableCompanion
  MolecularSequenceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension MolecularSequenceHistoryTableExtension on MolecularSequenceDrift {
  /// MolecularSequenceHistoryTableCompanion
  MolecularSequenceHistoryTableCompanion get companion {
    return MolecularSequenceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// NamingSystemTableExtension
extension NamingSystemTableExtension on fhir.NamingSystem {
  /// NamingSystemTableCompanion
  NamingSystemTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension NamingSystemHistoryTableExtension on NamingSystemDrift {
  /// NamingSystemHistoryTableCompanion
  NamingSystemHistoryTableCompanion get companion {
    return NamingSystemHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// NutritionOrderTableExtension
extension NutritionOrderTableExtension on fhir.NutritionOrder {
  /// NutritionOrderTableCompanion
  NutritionOrderTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension NutritionOrderHistoryTableExtension on NutritionOrderDrift {
  /// NutritionOrderHistoryTableCompanion
  NutritionOrderHistoryTableCompanion get companion {
    return NutritionOrderHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// NutritionProductTableExtension
extension NutritionProductTableExtension on fhir.NutritionProduct {
  /// NutritionProductTableCompanion
  NutritionProductTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension NutritionProductHistoryTableExtension on NutritionProductDrift {
  /// NutritionProductHistoryTableCompanion
  NutritionProductHistoryTableCompanion get companion {
    return NutritionProductHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ObservationTableExtension
extension ObservationTableExtension on fhir.Observation {
  /// ObservationTableCompanion
  ObservationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return ObservationTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ObservationHistoryTableExtension
extension ObservationHistoryTableExtension on ObservationDrift {
  /// ObservationHistoryTableCompanion
  ObservationHistoryTableCompanion get companion {
    return ObservationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ObservationDefinitionTableExtension
extension ObservationDefinitionTableExtension on fhir.ObservationDefinition {
  /// ObservationDefinitionTableCompanion
  ObservationDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ObservationDefinitionDrift {
  /// ObservationDefinitionHistoryTableCompanion
  ObservationDefinitionHistoryTableCompanion get companion {
    return ObservationDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// OperationDefinitionTableExtension
extension OperationDefinitionTableExtension on fhir.OperationDefinition {
  /// OperationDefinitionTableCompanion
  OperationDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension OperationDefinitionHistoryTableExtension on OperationDefinitionDrift {
  /// OperationDefinitionHistoryTableCompanion
  OperationDefinitionHistoryTableCompanion get companion {
    return OperationDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// OperationOutcomeTableExtension
extension OperationOutcomeTableExtension on fhir.OperationOutcome {
  /// OperationOutcomeTableCompanion
  OperationOutcomeTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension OperationOutcomeHistoryTableExtension on OperationOutcomeDrift {
  /// OperationOutcomeHistoryTableCompanion
  OperationOutcomeHistoryTableCompanion get companion {
    return OperationOutcomeHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// OrganizationTableExtension
extension OrganizationTableExtension on fhir.Organization {
  /// OrganizationTableCompanion
  OrganizationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension OrganizationHistoryTableExtension on OrganizationDrift {
  /// OrganizationHistoryTableCompanion
  OrganizationHistoryTableCompanion get companion {
    return OrganizationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// OrganizationAffiliationTableExtension
extension OrganizationAffiliationTableExtension
    on fhir.OrganizationAffiliation {
  /// OrganizationAffiliationTableCompanion
  OrganizationAffiliationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on OrganizationAffiliationDrift {
  /// OrganizationAffiliationHistoryTableCompanion
  OrganizationAffiliationHistoryTableCompanion get companion {
    return OrganizationAffiliationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PackagedProductDefinitionTableExtension
extension PackagedProductDefinitionTableExtension
    on fhir.PackagedProductDefinition {
  /// PackagedProductDefinitionTableCompanion
  PackagedProductDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on PackagedProductDefinitionDrift {
  /// PackagedProductDefinitionHistoryTableCompanion
  PackagedProductDefinitionHistoryTableCompanion get companion {
    return PackagedProductDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ParametersTableExtension
extension ParametersTableExtension on fhir.Parameters {
  /// ParametersTableCompanion
  ParametersTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ParametersHistoryTableExtension on ParametersDrift {
  /// ParametersHistoryTableCompanion
  ParametersHistoryTableCompanion get companion {
    return ParametersHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PatientTableExtension
extension PatientTableExtension on fhir.Patient {
  /// PatientTableCompanion
  PatientTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return PatientTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// PatientHistoryTableExtension
extension PatientHistoryTableExtension on PatientDrift {
  /// PatientHistoryTableCompanion
  PatientHistoryTableCompanion get companion {
    return PatientHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PaymentNoticeTableExtension
extension PaymentNoticeTableExtension on fhir.PaymentNotice {
  /// PaymentNoticeTableCompanion
  PaymentNoticeTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension PaymentNoticeHistoryTableExtension on PaymentNoticeDrift {
  /// PaymentNoticeHistoryTableCompanion
  PaymentNoticeHistoryTableCompanion get companion {
    return PaymentNoticeHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PaymentReconciliationTableExtension
extension PaymentReconciliationTableExtension on fhir.PaymentReconciliation {
  /// PaymentReconciliationTableCompanion
  PaymentReconciliationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on PaymentReconciliationDrift {
  /// PaymentReconciliationHistoryTableCompanion
  PaymentReconciliationHistoryTableCompanion get companion {
    return PaymentReconciliationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PersonTableExtension
extension PersonTableExtension on fhir.Person {
  /// PersonTableCompanion
  PersonTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension PersonHistoryTableExtension on PersonDrift {
  /// PersonHistoryTableCompanion
  PersonHistoryTableCompanion get companion {
    return PersonHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PlanDefinitionTableExtension
extension PlanDefinitionTableExtension on fhir.PlanDefinition {
  /// PlanDefinitionTableCompanion
  PlanDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension PlanDefinitionHistoryTableExtension on PlanDefinitionDrift {
  /// PlanDefinitionHistoryTableCompanion
  PlanDefinitionHistoryTableCompanion get companion {
    return PlanDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PractitionerTableExtension
extension PractitionerTableExtension on fhir.Practitioner {
  /// PractitionerTableCompanion
  PractitionerTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension PractitionerHistoryTableExtension on PractitionerDrift {
  /// PractitionerHistoryTableCompanion
  PractitionerHistoryTableCompanion get companion {
    return PractitionerHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// PractitionerRoleTableExtension
extension PractitionerRoleTableExtension on fhir.PractitionerRole {
  /// PractitionerRoleTableCompanion
  PractitionerRoleTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension PractitionerRoleHistoryTableExtension on PractitionerRoleDrift {
  /// PractitionerRoleHistoryTableCompanion
  PractitionerRoleHistoryTableCompanion get companion {
    return PractitionerRoleHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ProcedureTableExtension
extension ProcedureTableExtension on fhir.Procedure {
  /// ProcedureTableCompanion
  ProcedureTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return ProcedureTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// ProcedureHistoryTableExtension
extension ProcedureHistoryTableExtension on ProcedureDrift {
  /// ProcedureHistoryTableCompanion
  ProcedureHistoryTableCompanion get companion {
    return ProcedureHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ProvenanceTableExtension
extension ProvenanceTableExtension on fhir.Provenance {
  /// ProvenanceTableCompanion
  ProvenanceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ProvenanceHistoryTableExtension on ProvenanceDrift {
  /// ProvenanceHistoryTableCompanion
  ProvenanceHistoryTableCompanion get companion {
    return ProvenanceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// QuestionnaireTableExtension
extension QuestionnaireTableExtension on fhir.Questionnaire {
  /// QuestionnaireTableCompanion
  QuestionnaireTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension QuestionnaireHistoryTableExtension on QuestionnaireDrift {
  /// QuestionnaireHistoryTableCompanion
  QuestionnaireHistoryTableCompanion get companion {
    return QuestionnaireHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// QuestionnaireResponseTableExtension
extension QuestionnaireResponseTableExtension on fhir.QuestionnaireResponse {
  /// QuestionnaireResponseTableCompanion
  QuestionnaireResponseTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on QuestionnaireResponseDrift {
  /// QuestionnaireResponseHistoryTableCompanion
  QuestionnaireResponseHistoryTableCompanion get companion {
    return QuestionnaireResponseHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// RegulatedAuthorizationTableExtension
extension RegulatedAuthorizationTableExtension on fhir.RegulatedAuthorization {
  /// RegulatedAuthorizationTableCompanion
  RegulatedAuthorizationTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on RegulatedAuthorizationDrift {
  /// RegulatedAuthorizationHistoryTableCompanion
  RegulatedAuthorizationHistoryTableCompanion get companion {
    return RegulatedAuthorizationHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// RelatedPersonTableExtension
extension RelatedPersonTableExtension on fhir.RelatedPerson {
  /// RelatedPersonTableCompanion
  RelatedPersonTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension RelatedPersonHistoryTableExtension on RelatedPersonDrift {
  /// RelatedPersonHistoryTableCompanion
  RelatedPersonHistoryTableCompanion get companion {
    return RelatedPersonHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// RequestGroupTableExtension
extension RequestGroupTableExtension on fhir.RequestGroup {
  /// RequestGroupTableCompanion
  RequestGroupTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension RequestGroupHistoryTableExtension on RequestGroupDrift {
  /// RequestGroupHistoryTableCompanion
  RequestGroupHistoryTableCompanion get companion {
    return RequestGroupHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ResearchDefinitionTableExtension
extension ResearchDefinitionTableExtension on fhir.ResearchDefinition {
  /// ResearchDefinitionTableCompanion
  ResearchDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ResearchDefinitionHistoryTableExtension on ResearchDefinitionDrift {
  /// ResearchDefinitionHistoryTableCompanion
  ResearchDefinitionHistoryTableCompanion get companion {
    return ResearchDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ResearchElementDefinitionTableExtension
extension ResearchElementDefinitionTableExtension
    on fhir.ResearchElementDefinition {
  /// ResearchElementDefinitionTableCompanion
  ResearchElementDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on ResearchElementDefinitionDrift {
  /// ResearchElementDefinitionHistoryTableCompanion
  ResearchElementDefinitionHistoryTableCompanion get companion {
    return ResearchElementDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ResearchStudyTableExtension
extension ResearchStudyTableExtension on fhir.ResearchStudy {
  /// ResearchStudyTableCompanion
  ResearchStudyTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ResearchStudyHistoryTableExtension on ResearchStudyDrift {
  /// ResearchStudyHistoryTableCompanion
  ResearchStudyHistoryTableCompanion get companion {
    return ResearchStudyHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ResearchSubjectTableExtension
extension ResearchSubjectTableExtension on fhir.ResearchSubject {
  /// ResearchSubjectTableCompanion
  ResearchSubjectTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ResearchSubjectHistoryTableExtension on ResearchSubjectDrift {
  /// ResearchSubjectHistoryTableCompanion
  ResearchSubjectHistoryTableCompanion get companion {
    return ResearchSubjectHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// RiskAssessmentTableExtension
extension RiskAssessmentTableExtension on fhir.RiskAssessment {
  /// RiskAssessmentTableCompanion
  RiskAssessmentTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension RiskAssessmentHistoryTableExtension on RiskAssessmentDrift {
  /// RiskAssessmentHistoryTableCompanion
  RiskAssessmentHistoryTableCompanion get companion {
    return RiskAssessmentHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ScheduleTableExtension
extension ScheduleTableExtension on fhir.Schedule {
  /// ScheduleTableCompanion
  ScheduleTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ScheduleHistoryTableExtension on ScheduleDrift {
  /// ScheduleHistoryTableCompanion
  ScheduleHistoryTableCompanion get companion {
    return ScheduleHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SearchParameterTableExtension
extension SearchParameterTableExtension on fhir.SearchParameter {
  /// SearchParameterTableCompanion
  SearchParameterTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SearchParameterHistoryTableExtension on SearchParameterDrift {
  /// SearchParameterHistoryTableCompanion
  SearchParameterHistoryTableCompanion get companion {
    return SearchParameterHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ServiceRequestTableExtension
extension ServiceRequestTableExtension on fhir.ServiceRequest {
  /// ServiceRequestTableCompanion
  ServiceRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ServiceRequestHistoryTableExtension on ServiceRequestDrift {
  /// ServiceRequestHistoryTableCompanion
  ServiceRequestHistoryTableCompanion get companion {
    return ServiceRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SlotTableExtension
extension SlotTableExtension on fhir.Slot {
  /// SlotTableCompanion
  SlotTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SlotHistoryTableExtension on SlotDrift {
  /// SlotHistoryTableCompanion
  SlotHistoryTableCompanion get companion {
    return SlotHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SpecimenTableExtension
extension SpecimenTableExtension on fhir.Specimen {
  /// SpecimenTableCompanion
  SpecimenTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
    return SpecimenTableCompanion(
      id: Value(resource.id!.value!),
      lastUpdated: Value(
        resource.meta!.lastUpdated!.valueDateTime!.millisecondsSinceEpoch,
      ),
      resource: Value(resource.toJsonString()),
    );
  }
}

/// SpecimenHistoryTableExtension
extension SpecimenHistoryTableExtension on SpecimenDrift {
  /// SpecimenHistoryTableCompanion
  SpecimenHistoryTableCompanion get companion {
    return SpecimenHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SpecimenDefinitionTableExtension
extension SpecimenDefinitionTableExtension on fhir.SpecimenDefinition {
  /// SpecimenDefinitionTableCompanion
  SpecimenDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SpecimenDefinitionHistoryTableExtension on SpecimenDefinitionDrift {
  /// SpecimenDefinitionHistoryTableCompanion
  SpecimenDefinitionHistoryTableCompanion get companion {
    return SpecimenDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// StructureDefinitionTableExtension
extension StructureDefinitionTableExtension on fhir.StructureDefinition {
  /// StructureDefinitionTableCompanion
  StructureDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension StructureDefinitionHistoryTableExtension on StructureDefinitionDrift {
  /// StructureDefinitionHistoryTableCompanion
  StructureDefinitionHistoryTableCompanion get companion {
    return StructureDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// StructureMapTableExtension
extension StructureMapTableExtension on fhir.StructureMap {
  /// StructureMapTableCompanion
  StructureMapTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension StructureMapHistoryTableExtension on StructureMapDrift {
  /// StructureMapHistoryTableCompanion
  StructureMapHistoryTableCompanion get companion {
    return StructureMapHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SubscriptionTableExtension
extension SubscriptionTableExtension on fhir.Subscription {
  /// SubscriptionTableCompanion
  SubscriptionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SubscriptionHistoryTableExtension on SubscriptionDrift {
  /// SubscriptionHistoryTableCompanion
  SubscriptionHistoryTableCompanion get companion {
    return SubscriptionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SubscriptionStatusTableExtension
extension SubscriptionStatusTableExtension on fhir.SubscriptionStatus {
  /// SubscriptionStatusTableCompanion
  SubscriptionStatusTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SubscriptionStatusHistoryTableExtension on SubscriptionStatusDrift {
  /// SubscriptionStatusHistoryTableCompanion
  SubscriptionStatusHistoryTableCompanion get companion {
    return SubscriptionStatusHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SubscriptionTopicTableExtension
extension SubscriptionTopicTableExtension on fhir.SubscriptionTopic {
  /// SubscriptionTopicTableCompanion
  SubscriptionTopicTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SubscriptionTopicHistoryTableExtension on SubscriptionTopicDrift {
  /// SubscriptionTopicHistoryTableCompanion
  SubscriptionTopicHistoryTableCompanion get companion {
    return SubscriptionTopicHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SubstanceTableExtension
extension SubstanceTableExtension on fhir.Substance {
  /// SubstanceTableCompanion
  SubstanceTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SubstanceHistoryTableExtension on SubstanceDrift {
  /// SubstanceHistoryTableCompanion
  SubstanceHistoryTableCompanion get companion {
    return SubstanceHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SubstanceDefinitionTableExtension
extension SubstanceDefinitionTableExtension on fhir.SubstanceDefinition {
  /// SubstanceDefinitionTableCompanion
  SubstanceDefinitionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SubstanceDefinitionHistoryTableExtension on SubstanceDefinitionDrift {
  /// SubstanceDefinitionHistoryTableCompanion
  SubstanceDefinitionHistoryTableCompanion get companion {
    return SubstanceDefinitionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SupplyDeliveryTableExtension
extension SupplyDeliveryTableExtension on fhir.SupplyDelivery {
  /// SupplyDeliveryTableCompanion
  SupplyDeliveryTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SupplyDeliveryHistoryTableExtension on SupplyDeliveryDrift {
  /// SupplyDeliveryHistoryTableCompanion
  SupplyDeliveryHistoryTableCompanion get companion {
    return SupplyDeliveryHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// SupplyRequestTableExtension
extension SupplyRequestTableExtension on fhir.SupplyRequest {
  /// SupplyRequestTableCompanion
  SupplyRequestTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension SupplyRequestHistoryTableExtension on SupplyRequestDrift {
  /// SupplyRequestHistoryTableCompanion
  SupplyRequestHistoryTableCompanion get companion {
    return SupplyRequestHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// TaskTableExtension
extension TaskTableExtension on fhir.Task {
  /// TaskTableCompanion
  TaskTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension TaskHistoryTableExtension on TaskDrift {
  /// TaskHistoryTableCompanion
  TaskHistoryTableCompanion get companion {
    return TaskHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// TerminologyCapabilitiesTableExtension
extension TerminologyCapabilitiesTableExtension
    on fhir.TerminologyCapabilities {
  /// TerminologyCapabilitiesTableCompanion
  TerminologyCapabilitiesTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
    on TerminologyCapabilitiesDrift {
  /// TerminologyCapabilitiesHistoryTableCompanion
  TerminologyCapabilitiesHistoryTableCompanion get companion {
    return TerminologyCapabilitiesHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// TestReportTableExtension
extension TestReportTableExtension on fhir.TestReport {
  /// TestReportTableCompanion
  TestReportTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension TestReportHistoryTableExtension on TestReportDrift {
  /// TestReportHistoryTableCompanion
  TestReportHistoryTableCompanion get companion {
    return TestReportHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// TestScriptTableExtension
extension TestScriptTableExtension on fhir.TestScript {
  /// TestScriptTableCompanion
  TestScriptTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension TestScriptHistoryTableExtension on TestScriptDrift {
  /// TestScriptHistoryTableCompanion
  TestScriptHistoryTableCompanion get companion {
    return TestScriptHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// ValueSetTableExtension
extension ValueSetTableExtension on fhir.ValueSet {
  /// ValueSetTableCompanion
  ValueSetTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension ValueSetHistoryTableExtension on ValueSetDrift {
  /// ValueSetHistoryTableCompanion
  ValueSetHistoryTableCompanion get companion {
    return ValueSetHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// VerificationResultTableExtension
extension VerificationResultTableExtension on fhir.VerificationResult {
  /// VerificationResultTableCompanion
  VerificationResultTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension VerificationResultHistoryTableExtension on VerificationResultDrift {
  /// VerificationResultHistoryTableCompanion
  VerificationResultHistoryTableCompanion get companion {
    return VerificationResultHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}

/// VisionPrescriptionTableExtension
extension VisionPrescriptionTableExtension on fhir.VisionPrescription {
  /// VisionPrescriptionTableCompanion
  VisionPrescriptionTableCompanion get companion {
    final resource = newIdIfNoId().updateVersion();
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
extension VisionPrescriptionHistoryTableExtension on VisionPrescriptionDrift {
  /// VisionPrescriptionHistoryTableCompanion
  VisionPrescriptionHistoryTableCompanion get companion {
    return VisionPrescriptionHistoryTableCompanion(
      id: Value(id),
      lastUpdated: Value(lastUpdated),
      resource: Value(resource),
    );
  }
}
