package db

import (
	"database/sql"
	"fmt"

	_ "github.com/fhir-fli/go-sqlite3-sqlcipher"
)

// SQLiteDB struct wraps an SQLite connection.
type SQLiteDB struct {
	conn *sql.DB
}

// ConnectSQLite establishes a connection to the SQLite (SQLCipher) database.
func ConnectSQLite(dbPath, encryptionKey string) (*SQLiteDB, error) {
	// Open the SQLite connection with encryption key (SQLCipher)
	conn, err := sql.Open("sqlite3", fmt.Sprintf("%s?_pragma_key=%s", dbPath, encryptionKey))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to SQLite: %w", err)
	}

	return &SQLiteDB{conn: conn}, nil
}

// Close terminates the SQLite connection.
func (db *SQLiteDB) Close() error {
	return db.conn.Close()
}

// GetConnection provides access to the underlying sql.DB connection.
func (db *SQLiteDB) GetConnection() *sql.DB {
	return db.conn
}

// InitSchema ensures the FHIR schema exists in the database.
// Creates a table for each resource type.
func InitSchema(db *SQLiteDB) error {
	
	for _, resourceType := range resourceTypes {
		schema := fmt.Sprintf(`
			CREATE TABLE IF NOT EXISTS %s (
				id TEXT PRIMARY KEY,
				lastUpdated DATETIME NOT NULL,
				resourceJson TEXT NOT NULL
			);
		`, resourceType)
		if _, err := db.conn.Exec(schema); err != nil {
			return fmt.Errorf("failed to initialize schema for %s: %w", resourceType, err)
		}
	}

	return nil
}

var resourceTypes = []string{
	"Account", "ActivityDefinition", "AdministrableProductDefinition", "AdverseEvent", "AllergyIntolerance",
	"Appointment", "AppointmentResponse", "AuditEvent", "Basic", "Binary", "BiologicallyDerivedProduct",
	"BodyStructure", "Bundle", "CapabilityStatement", "CarePlan", "CareTeam", "CatalogEntry",
	"ChargeItem", "ChargeItemDefinition", "Citation", "Claim", "ClaimResponse", "ClinicalImpression",
	"ClinicalUseDefinition", "CodeSystem", "Communication", "CommunicationRequest", "CompartmentDefinition",
	"Composition", "ConceptMap", "Condition", "Consent", "Contract", "Coverage",
	"CoverageEligibilityRequest", "CoverageEligibilityResponse", "DetectedIssue", "Device", "DeviceDefinition",
	"DeviceMetric", "DeviceRequest", "DeviceUseStatement", "DiagnosticReport", "DocumentManifest",
	"DocumentReference", "Encounter", "Endpoint", "EnrollmentRequest", "EnrollmentResponse",
	"EpisodeOfCare", "EventDefinition", "Evidence", "EvidenceReport", "EvidenceVariable",
	"ExampleScenario", "ExplanationOfBenefit", "FamilyMemberHistory", "Flag", "Goal",
	"GraphDefinition", "FhirGroup", "GuidanceResponse", "HealthcareService", "ImagingStudy",
	"Immunization", "ImmunizationEvaluation", "ImmunizationRecommendation", "ImplementationGuide", "Ingredient",
	"InsurancePlan", "Invoice", "Library", "Linkage", "List", "Location",
	"ManufacturedItemDefinition", "Measure", "MeasureReport", "Media", "Medication",
	"MedicationAdministration", "MedicationDispense", "MedicationKnowledge", "MedicationRequest", "MedicationStatement",
	"MedicinalProductDefinition", "MessageDefinition", "MessageHeader", "MolecularSequence", "NamingSystem",
	"NutritionOrder", "Observation", "ObservationDefinition", "OperationDefinition", "OperationOutcome",
	"Organization", "OrganizationAffiliation", "PackagedProductDefinition", "Parameters", "Patient",
	"PaymentNotice", "PaymentReconciliation", "Person", "PlanDefinition", "Practitioner",
	"PractitionerRole", "Procedure", "Provenance", "Questionnaire", "QuestionnaireResponse",
	"RegulatedAuthorization", "RelatedPerson", "RequestGroup", "ResearchDefinition", "ResearchElementDefinition",
	"ResearchStudy", "ResearchSubject", "RiskAssessment", "Schedule", "SearchParameter",
	"ServiceRequest", "Slot", "Specimen", "SpecimenDefinition", "StructureDefinition",
	"StructureMap", "Subscription", "SubscriptionStatus", "SubscriptionTopic", "Substance",
	"SubstanceDefinition", "SupplyDelivery", "SupplyRequest", "Task", "TerminologyCapabilities",
	"TestReport", "TestScript", "ValueSet", "VerificationResult", "VisionPrescription",
}
