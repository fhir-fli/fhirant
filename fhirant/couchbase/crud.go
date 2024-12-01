package couchbase

import (
	"fmt"

	"github.com/couchbase/gocb/v2"
)

// CreateOrUpdateResource creates or updates a FHIR resource in the Couchbase bucket
func CreateOrUpdateResource(resourceType, resourceID string, resourceData map[string]interface{}) error {
    collection := Bucket.DefaultCollection()

    key := fmt.Sprintf("%s::%s", resourceType, resourceID)
    _, err := collection.Upsert(key, resourceData, &gocb.UpsertOptions{})
    if err != nil {
        return fmt.Errorf("failed to create or update resource: %w", err)
    }

    return nil
}
