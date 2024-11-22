package pocketfhir

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/caddyserver/caddy/v2"
	_ "github.com/caddyserver/caddy/v2/modules/standard"
)

// caddyConfig is a struct that contains the configuration parameters for starting the Caddy server.
type caddyConfig struct {
	PbPort      string
	HttpPort    string
	HttpsPort   string
	PbUrl       string
	StoragePath string
	IpAddress   string
}

// startCaddyInstance initializes and starts the Caddy server instance.
func startCaddyInstance(config caddyConfig) error {
	// Change working directory
	if err := os.Chdir(config.StoragePath); err != nil {
		log.Fatalf("Failed to change working directory to %s: %v", config.StoragePath, err)
		return err
	}

	// Log consolidated configuration details
	log.Printf("Starting Caddy server with configuration: %+v", config)

	// Generate the Caddy config
	caddyCfg := createConfig(config)

	// Serialize for debugging
	configJSON, err := json.MarshalIndent(caddyCfg, "", "  ")
	if err != nil {
		log.Fatalf("Failed to serialize Caddy config: %v", err)
		return err
	}
	log.Printf("Generated Caddy config: %s", string(configJSON))

	// Load Caddy with the generated config JSON
	log.Println("Loading Caddy configuration...")
	err = caddy.Load(configJSON, true)
	if err != nil {
		log.Fatalf("[ERROR] Failed to load Caddy configuration: %v", err)
		return err
	}
	log.Println("Caddy server started successfully.")
	return nil
}

// createConfig generates a basic Caddy configuration to run a reverse proxy with HTTP and a static file server.
func createConfig(config caddyConfig) *caddy.Config {
	// Define paths for certs and proxy logs
	pbProxyPath := fmt.Sprintf("%s/proxy_access.log", config.StoragePath)

	// Generate the full configuration using helpers
	loggingConfig := generateLoggingConfig(pbProxyPath)
	storageConfig := generateStorageConfig(config.StoragePath)
	httpAppConfig := generateHttpAppConfig(config)
	tlsConfig := generateTlsConfig(config.IpAddress)

	// Combine all configurations into the final JSON
	combinedConfig := fmt.Sprintf(`{
        %s,
        %s,
        "apps": {
            %s,
            %s
        }
    }`, loggingConfig, storageConfig, httpAppConfig, tlsConfig)

	var caddyConfig caddy.Config
	err := json.Unmarshal([]byte(combinedConfig), &caddyConfig)
	if err != nil {
		log.Fatalf("Failed to parse JSON configuration: %v", err)
	}

	return &caddyConfig
}

// Generates the logging configuration section
func generateLoggingConfig(pbProxyPath string) string {
	return fmt.Sprintf(`"logging": {
            "logs": {
                "pb_proxy": {
                    "writer": {
                        "output": "file",
                        "filename": "%s"
                    },
                    "encoder": {
                        "format": "json"
                    },
                    "include": [
                        "http.log.access.pb_proxy"
                    ]
                }
            }
        }`, pbProxyPath)
}

// Generates the storage configuration section
func generateStorageConfig(storagePath string) string {
	return fmt.Sprintf(`"storage": {
            "module": "file_system",
            "root": "%s"
        }`, storagePath)
}

// Generates the HTTP application configuration section
func generateHttpAppConfig(config caddyConfig) string {
	httpsServerConfig := generateHttpsServerConfig(config)
	return fmt.Sprintf(`"http": {
            "http_port": %s,
            "servers": {
                %s
            }
        }`, config.HttpPort, httpsServerConfig)
}

// Generates the HTTP server configuration for reverse proxy with health checks
func generateHttpsServerConfig(config caddyConfig) string {
	return fmt.Sprintf(`"srv_https": {
            "listen": [":%s"],
            "routes": [
                {
                    "match": [{"host": ["%s"]}],
                    "handle": [
                        {
                            "handler": "reverse_proxy",
                            "transport": {
                                "protocol": "http",
                                "read_timeout": 360000000000
                            },
                            "health_checks": {
                                "active": {
                                    "interval": 10000000000,
                                    "timeout": 2000000000,
                                    "uri": "/api/health"
                                }
                            },
                            "upstreams": [
                                {
                                    "dial": "%s:%s"
                                }
                            ]
                        }
                    ]
                }
            ]
        }`, config.HttpsPort, config.IpAddress, config.PbUrl, config.PbPort)
}

// Generates the TLS automation configuration
func generateTlsConfig(ipAddress string) string {
	return fmt.Sprintf(`"tls": {
            "automation": {
                "policies": [
                    {
                        "subjects": [
                            "%s"
                        ],
                        "issuers": [
                            {
                                "module": "internal"
                            }
                        ]
                    }
                ]
            }
        }`, ipAddress)
}
