package couchbase

import (
	"fmt"
	"log"
	"time"

	"github.com/couchbase/gocb/v2"
)

var Cluster *gocb.Cluster
var Bucket *gocb.Bucket

func InitCouchbaseConnection() error {
    // Connect to the Couchbase cluster
    var err error
    Cluster, err = gocb.Connect("couchbase://localhost", gocb.ClusterOptions{
        Username: "Administrator",
        Password: "password", // Use the admin username and password you set during installation
    })
    if err != nil {
        return fmt.Errorf("failed to connect to Couchbase cluster: %w", err)
    }

    // Get a reference to the `fhirant` bucket
    Bucket = Cluster.Bucket("fhirant")

    // Ensure bucket is ready
    err = Bucket.WaitUntilReady(5*time.Second, nil)
    if err != nil {
        return fmt.Errorf("failed to connect to bucket: %w", err)
    }

    log.Println("Connected to Couchbase bucket successfully")
    return nil
}
