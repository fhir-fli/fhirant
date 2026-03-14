# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Documents

- **SPEC.md** — Feature specifications, architecture, and Given/When/Then scenarios
- **PLAN.md** — Remaining work with checkboxes (update after completing each step)
- **TESTING.md** — Test inventory, running instructions, and coverage gaps

## Repository Overview

FHIRant (Fast Healthcare Interoperability Resources Agile Networking Tool) is a FHIR R4 server built with Dart. It runs standalone as a CLI process or embedded in the Flutter mobile app. It lives within the larger `fhir/` monorepo and depends on sibling packages (`fhir_r4`, `fhir_r4_path`, `fhir_r4_mapping`, `fhir_r4_validation`) via path dependencies.

## Package Structure

```
fhirant/
└── packages/
    ├── fhirant/               # Flutter mobile app (dashboard, resource browser)
    ├── fhirant_server/        # Shelf-based HTTP server, routing, handlers
    ├── fhirant_db/            # Drift/SQLite database with search indexing
    ├── fhirant_logging/       # Singleton JSON logging service
    └── fhirant_secure_storage/  # Encrypted credential/key storage
```

**Dependency graph:** `fhirant (Flutter app) → fhirant_server → fhirant_db → fhirant_secure_storage → fhirant_logging`

## Common Commands

```bash
# Bootstrap all packages (from repo root)
melos bootstrap

# Run the server (dev mode — no auth required)
dart run packages/fhirant_server/bin/server.dart --port 8080 --db-path data/db

# Run all server tests
cd packages/fhirant_server && flutter test

# Run all database tests
cd packages/fhirant_db && flutter test

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

Shelf + shelf_router HTTP server. The main class `FhirAntServer` (in `lib/src/fhirant_server.dart`) builds a router with 75+ route registrations.

#### Middleware Pipeline

Requests pass through middleware in this order:

1. **Logging** — logs method, path, status, duration, client IP; emits to `requestLog` stream
2. **CORS** — cross-origin headers for web clients
3. **Content Negotiation** — validates Accept/Content-Type headers
4. **Auth** — JWT validation + SMART scope enforcement (or dev-mode bypass injecting synthetic admin)
5. **Audit** — writes AuditEvent resources to DB for CRUD operations
6. **Rate Limiting** — configurable max requests per duration (default 10/60s)
7. **Router** — dispatches to handler

#### Route Table

| Domain | Route Pattern | Handler | Purpose |
|--------|---|---|---|
| **Auth** | `POST /auth/register` | `registerHandler` | Create user account |
| | `POST /auth/login` | `loginHandler` | Authenticate, get JWT |
| | `POST /auth/token` | `refreshHandler` | Refresh access token |
| | `POST /auth/revoke` | `revokeHandler` | Revoke refresh token |
| | `POST /auth/logout` | `logoutHandler` | Log out |
| | `GET /auth/authorize` | `authorizeGetHandler` | OAuth authorize (GET) |
| | `POST /auth/authorize` | `authorizePostHandler` / `authorizeJsonHandler` | OAuth authorize (POST) |
| **Admin** | `POST /admin/unlock/<userId>` | `unlockAccountHandler` | Unlock locked account |
| **Public** | `GET /` | `baseHandler` | Server info |
| | `GET /favicon.ico` | `favicoHandler` | Favicon |
| | `GET /health` | `healthHandler` | Health check + uptime |
| | `GET /metadata` | `metadataHandler` | CapabilityStatement |
| | `GET /.well-known/smart-configuration` | `smartConfigHandler` | SMART config discovery |
| **CQL** | `POST /Library/<id>/$evaluate` | `libraryEvaluateHandler` | Evaluate CQL library by ID |
| | `POST /Library/$evaluate` | `libraryEvaluateByUrlHandler` | Evaluate CQL library by URL |
| | `POST /$cql` | `cqlHandler` | Ad-hoc CQL evaluation |
| **Validation** | `ALL /$validate` | `validateHandler` | Validate resource (system) |
| | `ALL /<type>/$validate` | `validateHandler` | Validate resource (typed) |
| **Terminology** | `GET\|POST /CodeSystem/<id>/$validate-code` | `validateCodeHandler` | Validate code in CodeSystem |
| | `GET\|POST /CodeSystem/$validate-code` | `validateCodeHandler` | Validate code (by params) |
| | `GET\|POST /ValueSet/<id>/$validate-code` | `validateCodeHandler` | Validate code in ValueSet |
| | `GET\|POST /ValueSet/$validate-code` | `validateCodeHandler` | Validate code (by params) |
| | `GET\|POST /CodeSystem/<id>/$lookup` | `lookupHandler` | Code lookup |
| | `GET\|POST /CodeSystem/$lookup` | `lookupHandler` | Code lookup (by params) |
| | `GET\|POST /ValueSet/<id>/$expand` | `expandHandler` | ValueSet expansion |
| | `GET\|POST /ValueSet/$expand` | `expandHandler` | ValueSet expansion (by params) |
| **Backup/Restore** | `POST /$backup` | `backupHandler` | Full database backup |
| | `POST /$restore` | `restoreHandler` | Restore from backup |
| **FHIRPath** | `GET\|POST /$fhirpath` | `fhirPathHandler` | Evaluate FHIRPath expressions |
| **Forecasting** | `POST /$immds-forecast` | `immdsForecastHandler` | Immunization forecast (CDC) |
| | `POST /$immds-forecast-who` | `immdsForecastWhoHandler` | Immunization forecast (WHO) |
| **Mapping** | `POST /$transform` | `mappingHandler` | FHIR Mapping Language transform |
| **Bulk Export** | `GET /$export` | `exportKickoffHandler` | System-level bulk export |
| | `GET /Group/<id>/$export` | `exportKickoffHandler` | Group-level bulk export |
| | `GET /Patient/$export` | `exportKickoffHandler` | Patient-level bulk export |
| | `GET /$export-poll-status/<jobId>` | `exportStatusHandler` | Check export status |
| | `DELETE /$export-poll-status/<jobId>` | `exportDeleteHandler` | Cancel/delete export |
| | `GET /$export-file/<jobId>/<fileName>` | `exportFileHandler` | Download export file |
| **Document** | `GET /Composition/<id>/$document` | `documentHandler` | Generate document Bundle |
| **Everything** | `GET /<type>/<id>/$everything` | `everythingHandler` | Patient/Encounter $everything |
| **Meta** | `GET /<type>/<id>/$meta` | `metaHandler` | Get resource meta |
| | `POST /<type>/<id>/$meta-add` | `metaAddHandler` | Add meta tags |
| | `POST /<type>/<id>/$meta-delete` | `metaDeleteHandler` | Remove meta tags |
| **History** | `GET /<type>/<id>/_history/<vid>` | `vreadResourceHandler` | Version read |
| | `GET /<type>/<id>/_history` | `resourceHistoryHandler` | Resource history |
| | `GET /<type>/_history` | `typeHistoryHandler` | Type-level history |
| | `GET /_history` | `systemHistoryHandler` | System-level history |
| **Compartment** | `GET /<type>/<id>/<resourceType>` | `compartmentSearchHandler` | Compartment search |
| **Search** | `POST /_search` | `postSystemSearchHandler` | System-level POST search |
| | `POST /<type>/_search` | `postSearchHandler` | Type-level POST search |
| **CRUD** | `POST /` | `bundleHandler` | Transaction/Batch bundle |
| | `GET /<type>` | `getResourcesHandler` | Search resources |
| | `POST /<type>` | `postResourceHandler` | Create resource |
| | `GET /<type>/<id>` | `getResourceByIdHandler` | Read resource |
| | `PUT /<type>/<id>` | `putResourceHandler` | Update resource |
| | `PATCH /<type>/<id>` | `patchResourceHandler` | JSON Patch |
| | `DELETE /<type>/<id>` | `deleteResourceHandler` | Delete resource |
| | `DELETE /<type>` | `conditionalDeleteHandler` | Conditional delete |

### Authentication & Authorization

- **OAuth 2.0** with PKCE, authorization code flow
- **JWT tokens**: HS256, 8-hour access tokens, 7-day refresh tokens
- **SMART on FHIR scopes**: `patient/*.read`, `user/Observation.write`, `system/*.*`, etc.
- **Account lockout**: 5 failed login attempts → 15-minute lockout
- **Token revocation**: explicit revoke + hourly cleanup of expired tokens
- **Dev mode**: `devMode: true` bypasses auth, injects synthetic admin user
- **User roles**: admin, clinician, readonly

### FHIR Operations

All implemented operations:

- `$validate` — Resource validation (system-level and type-level)
- `$everything` — Patient/Encounter compartment export
- `$document` — Composition-based document Bundle generation
- `$meta` / `$meta-add` / `$meta-delete` — Meta tag management
- `$backup` / `$restore` — Full database backup and restore
- `$fhirpath` — Server-side FHIRPath expression evaluation
- `$cql` — Clinical Quality Language evaluation
- `Library/$evaluate` — CQL library evaluation
- `$transform` — FHIR Mapping Language transformations
- `$immds-forecast` / `$immds-forecast-who` — Immunization forecasting (CDC/WHO schedules)
- `$export` — Async bulk data export (system/group/patient level, NDJSON)
- `$validate-code` — Terminology code validation (CodeSystem, ValueSet)
- `$lookup` — CodeSystem code lookup
- `$expand` — ValueSet expansion

### Database Layer (`fhirant_db`)

Drift ORM over SQLite with SQLCipher encryption. The main database class is `FhirAntDb` (in `db/fhirant_db.dart`).

**Tables:** `resources` (current versions), `resources_history` (all versions), `logs`, `users`, `revoked_tokens`, `export_jobs`, plus 9 search parameter tables (string, token, date, number, quantity, reference, uri, composite, special).

**Search flow:**
1. On resource save, `search_parameters.dart` extracts all searchable values and indexes them into the appropriate tables
2. On search, parameters are routed to the correct table by type detection
3. AND logic across parameters (set intersection of resource IDs), OR logic within a parameter (comma-separated values)
4. Reference chaining resolves through intermediate resource lookups
5. Results are sorted and paginated

### Secure Storage (`fhirant_secure_storage`)

Wraps `flutter_secure_storage` for encryption keys, SSL certificates, and passkeys. Can auto-generate self-signed certificates and 256-bit encryption keys.

### Logging (`fhirant_logging`)

Singleton `FhirantLogging()` that writes JSON-formatted logs to console and optional file. Levels: INFO, WARNING, ERROR.

### Mobile App (`packages/fhirant/`)

Flutter app wrapping the server for on-device use. Published on Google Play Store.

- **Dashboard UI**: Material 3 with server control, network info (QR code), resource counts, live request log
- **Resource Browser**: JSON/YAML toggle, clickable FHIR references with navigation stack
- **MIMIC sample data**: bulk-loadable clinical data for demos
- **Android**: foreground service keeps server running when backgrounded
- **iOS**: server stops when app goes to background (OS limitation)

## Testing

**690 tests** across 45 test files, all passing.

- **Server tests** (582 tests, 42 files): `cd packages/fhirant_server && flutter test`
- **DB tests** (108 tests, 3 files): `cd packages/fhirant_db && flutter test`

See **TESTING.md** for full inventory by file.

Tests use `flutter_test` + `mocktail`. `FhirAntDb` is mocked in server handler tests. Database tests require sqlite3 native library.

## Server CLI Options

```
--port, -p          Server port (default: 8080)
--db-path           Database path (default: data/db)
--sqlcipher-path    Custom SQLCipher library path
--config, -c        YAML configuration file
--https             Enable HTTPS
--cert-path         HTTPS certificate path
--key-path          HTTPS private key path
--dev               Enable dev mode (no authentication)
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
