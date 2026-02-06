# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

FHIRant (Fast Healthcare Interoperability Resources Agile Networking Tool) is a FHIR R4 server built with Dart. It lives within the larger `fhir/` monorepo and depends on sibling packages (`fhir_r4`, `fhir_r4_path`, `fhir_r4_mapping`, `fhir_r4_validation`) via path dependencies.

## Package Structure

```
fhirant/
└── packages/
    ├── fhirant_server/       # Shelf-based HTTP server, routing, handlers
    ├── fhirant_db/           # Drift/SQLite database with search indexing
    ├── fhirant_logging/      # Singleton JSON logging service
    └── fhirant_secure_storage/  # Encrypted credential/key storage
```

**Dependency graph:** `fhirant_server → fhirant_db → fhirant_secure_storage → fhirant_logging`

## Common Commands

```bash
# Bootstrap all packages (from repo root)
melos bootstrap

# Run the server
dart run packages/fhirant_server/bin/server.dart --port 8080 --db-path data/db

# Run all tests in fhirant_server (uses flutter_test due to Flutter dependencies in fhirant_db)
cd packages/fhirant_server && flutter test

# Run a specific test file
cd packages/fhirant_server && flutter test test/utils/search_parser_test.dart

# Analyze a package
dart analyze packages/fhirant_server

# Format a package
dart format packages/fhirant_server

# Regenerate Drift database code (after changing table definitions)
cd packages/fhirant_db && dart run build_runner build --delete-conflicting-outputs
```

## Critical File Access Rules

**NEVER recursively read:**
- `packages/fhirant_db/lib/db/search/search_parameters.dart` — 25,700 lines of generated search parameter extraction code
- `packages/fhirant_db/lib/db/fhirant_db.g.dart` — Generated Drift ORM code
- `packages/fhirant_server/assets/fhir_spec/` — FHIR specification files
- `packages/fhirant_server/assets/mimic/` — MIMIC-IV test data

**Safe to read:**
- `lib/src/**/*.dart` source files in any package
- `test/**_test.dart` test files
- `pubspec.yaml`, `melos.yaml`, `analysis_options.yaml`

## Architecture

### Server Layer (`fhirant_server`)

Shelf + shelf_router HTTP server. All handlers live in `lib/src/handlers/`. The main class `FhirAntServer` builds a router with this route structure:

| Route Pattern | Handler | Purpose |
|---|---|---|
| `GET /metadata` | `metadataHandler` | CapabilityStatement |
| `GET /<type>` | `getResourcesHandler` | Search + pagination |
| `POST /<type>` | `postResourceHandler` | Create resource |
| `GET /<type>/<id>` | `getResourceByIdHandler` | Read resource |
| `PUT /<type>/<id>` | `putResourceHandler` | Update resource |
| `PATCH /<type>/<id>` | `patchResourceHandler` | JSON Patch |
| `DELETE /<type>/<id>` | `deleteResourceHandler` | Delete resource |
| `GET /<type>/<id>/_history` | `resourceHistoryHandler` | Resource history |
| `GET /<type>/<id>/_history/<vid>` | `vreadResourceHandler` | Version read |
| `POST /` | `bundleHandler` | Transaction/Batch |
| `ALL /<type>/$validate` | `validateHandler` | Validation |

Key file: `resource_handler.dart` — contains CRUD + search logic. Uses `SearchParameterParser` to split query params into search parameters, pagination, sort, and _include/_revinclude directives.

Middleware pipeline: logging → rate limiting (10 req/60s) → router.

### Database Layer (`fhirant_db`)

Drift ORM over SQLite with SQLCipher encryption. Key abstraction: `FuegoDbInterface` (abstract) → `FhirAntDbInterface` (concrete).

**Tables:** `resources` (current versions), `resources_history` (all versions), `logs`, plus 9 search parameter tables (string, token, date, number, quantity, reference, uri, composite, special).

**Search flow:**
1. On resource save, `search_parameters.dart` extracts all searchable values and indexes them into the appropriate tables
2. On search, parameters are routed to the correct table by type detection
3. AND logic across parameters (set intersection of resource IDs), OR logic within a parameter (comma-separated values)
4. Reference chaining resolves through intermediate resource lookups
5. Results are sorted and paginated

**Interface contract** (`fuego_db_interface.dart`):
- CRUD: `getResource()`, `saveResource()`, `deleteResource()`
- Search: `search()`, `searchCount()`
- History: `getResourceHistory()`
- Pagination: `getResourcesWithPagination()`, `getResourceCount()`

### Secure Storage (`fhirant_secure_storage`)

Wraps `flutter_secure_storage` for encryption keys, SSL certificates, and passkeys. Can auto-generate self-signed certificates and 256-bit encryption keys.

### Logging (`fhirant_logging`)

Singleton `FhirantLogging()` that writes JSON-formatted logs to console and `server_logs.json`. Levels: INFO, WARNING, ERROR.

## Testing

Tests use `flutter_test` + `mocktail`. The `FuegoDbInterface` is mocked in server handler tests.

**Test locations:**
- `packages/fhirant_server/test/handlers/` — handler unit tests (mock DB)
- `packages/fhirant_server/test/utils/` — utility tests (SearchParameterParser)

Database tests require sqlite3 native library to be installed on the system.

## Server CLI Options

```
--port, -p          Server port (default: 8080)
--db-path           Database path (default: data/db)
--sqlcipher-path    Custom SQLCipher library path
--config, -c        YAML configuration file
--https             Enable HTTPS
--cert-path         HTTPS certificate path
--key-path          HTTPS private key path
```

Environment variable `FHIRANT_ENCRYPTION_KEY` provides the database encryption key.

## Code Style

Packages use `flutter_lints`. The parent monorepo uses `very_good_analysis` — see the parent `fhir/CLAUDE.md` for those customizations.

## Key Design Decisions

- **Resources stored as JSON strings** in the database, deserialized via `Resource.fromJson()`
- **Version ID = timestamp** — resources auto-versioned on save with `updateVersion(versionIdAsTime: true)`
- **IDs auto-generated** if missing via `newIdIfNoId()`
- **Search parameter extraction is generated code** — `search_parameters.dart` is produced from FHIR SearchParameter definitions, do not edit by hand
- **All FHIR resource types** are valid URL path segments and map to `R4ResourceType` enum values
