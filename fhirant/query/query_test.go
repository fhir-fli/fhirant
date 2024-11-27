package query_test

import (
	"fhirant/query"
	"testing"
)

func TestBuildSelectQuery(t *testing.T) {
	qb := query.QueryBuilder{
		Schema: map[string]interface{}{
			"Patient": {}, // Simulated schema entry
		},
	}

	query, err := qb.BuildSelectQuery("Patient", map[string]interface{}{
		"gender": "male",
	})
	if err != nil {
		t.Fatalf("failed to build query: %v", err)
	}

	expected := "SELECT * FROM fhir_resources WHERE resource_type = 'Patient' AND JSON_EXTRACT(resource_data, '$.gender') = 'male'"
	if query != expected {
		t.Errorf("expected %s, got %s", expected, query)
	}
}
