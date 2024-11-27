package query

import (
	"fmt"
)

type QueryBuilder struct {
	Schema map[string]interface{}
}

func (qb *QueryBuilder) BuildSelectQuery(resourceType string, filters map[string]interface{}) (string, error) {
	base := fmt.Sprintf("SELECT * FROM fhir_resources WHERE resource_type = '%s'", resourceType)

	for key, value := range filters {
		filter := fmt.Sprintf(" AND JSON_EXTRACT(resource_data, '$.%s') = '%v'", key, value)
		base += filter
	}

	return base, nil
}
