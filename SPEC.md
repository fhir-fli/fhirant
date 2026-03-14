# SPEC.md — FHIRant Feature Specification

## Vision

FHIRant is an on-device FHIR R4 server written in Dart. It runs as a standalone CLI process or embedded inside a Flutter mobile app. The goal is a complete, standards-compliant FHIR RESTful API backed by SQLCipher-encrypted SQLite storage that works across platforms (Linux, Android, iOS, macOS, Windows).

## Architecture

### Package Diagram

```
┌──────────────────────────────────────────────┐
│           fhirant (Flutter app)              │
│  Dashboard · Resource Browser · MIMIC loader │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│           fhirant_server                     │
│  Shelf HTTP · Router · Handlers · Middleware │
│  Auth · Operations · Bulk Export             │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│           fhirant_db                         │
│  Drift ORM · SQLCipher · Search Indexing     │
│  Users · Tokens · Export Jobs · Audit Logs   │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│      fhirant_secure_storage                  │
│  Encryption keys · SSL certs · Passkeys      │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│        fhirant_logging                       │
│  Singleton JSON logger · File + console      │
└──────────────────────────────────────────────┘
```

### Tech Stack

- **Language**: Dart 3.5+
- **Server framework**: Shelf + shelf_router
- **Database**: Drift (SQLite) with SQLCipher encryption via sqlite3mc
- **FHIR library**: fhir_r4, fhir_r4_path, fhir_r4_mapping, fhir_r4_validation (path deps)
- **Auth**: JWT (HS256) via `dart_jsonwebtoken`, bcrypt password hashing
- **Mobile**: Flutter, foreground service (Android), provider state management

### External Dependencies (sibling packages)

- `fhir_r4` — FHIR R4 resource model, serialization, primitives
- `fhir_r4_path` — FHIRPath query engine
- `fhir_r4_mapping` — FHIR Mapping Language parser and engine
- `fhir_r4_validation` — Resource validation

## Constraints

1. **Must work on mobile** — no server-only dependencies; `dart:io` is available on Flutter mobile
2. **JSON only** — no XML serialization (no `application/fhir+xml`)
3. **Encrypted at rest** — SQLCipher encryption is mandatory for production; in-memory DBs for tests
4. **Single-process** — no multi-instance coordination; single SQLite connection
5. **FHIR R4** — implements FHIR R4 (4.0.1) specification only

## Feature Inventory

### Authentication & Authorization — DONE

- [x] User registration with bcrypt password hashing
- [x] Login with JWT access token (8h) + refresh token (7d)
- [x] Token refresh flow
- [x] Token revocation + hourly cleanup
- [x] Logout
- [x] OAuth 2.0 authorization code flow with PKCE
- [x] SMART on FHIR scope enforcement (`patient/*.read`, `user/Observation.write`, etc.)
- [x] Account lockout (5 failures → 15-minute lock)
- [x] Admin account unlock
- [x] Dev mode (bypass auth with synthetic admin)
- [x] SMART configuration discovery (`/.well-known/smart-configuration`)
- [x] User roles: admin, clinician, readonly

### CRUD Operations — DONE

- [x] Create (POST /{type})
- [x] Read (GET /{type}/{id})
- [x] Update (PUT /{type}/{id})
- [x] Patch (PATCH /{type}/{id}) — JSON Patch
- [x] Delete (DELETE /{type}/{id})
- [x] Conditional delete (DELETE /{type}?params)
- [x] Version read (GET /{type}/{id}/_history/{vid})
- [x] Auto-versioning with timestamp versionId

### Search — DONE (with gaps)

- [x] All search parameter types: string, token, date, number, quantity, uri, reference, composite, special
- [x] Special parameters: _id, _lastUpdated, _tag, _profile, _security, _source
- [x] AND logic across parameters, OR logic within (comma-separated)
- [x] Reference chaining (e.g., `Patient?organization.name=Hospital`)
- [x] Sorting (_sort with ascending/descending)
- [x] Pagination (_count, _offset) with Bundle links (first/prev/next/last)
- [x] _include and _revinclude
- [x] POST-based search (POST /{type}/_search, POST /_search)
- [x] Compartment search (GET /Patient/123/Observation)
- [ ] _has (reverse chaining)
- [ ] _summary, _elements (response shaping)
- [ ] _contained, _containedType
- [ ] _filter (FHIRPath-based filtering)
- [ ] Accent normalization for string searches

### History — DONE

- [x] Resource history (GET /{type}/{id}/_history)
- [x] Type history (GET /{type}/_history)
- [x] System history (GET /_history)

### Bundle Operations — DONE

- [x] Transaction bundles
- [x] Batch bundles

### FHIR Operations — DONE

- [x] $validate (system + type level)
- [x] $everything (Patient, Encounter, etc.)
- [x] $document (Composition-based)
- [x] $meta, $meta-add, $meta-delete
- [x] $backup, $restore
- [x] $fhirpath (server-side evaluation)
- [x] $cql (Clinical Quality Language)
- [x] Library/$evaluate (CQL library evaluation)
- [x] $transform (FHIR Mapping Language)
- [x] $immds-forecast, $immds-forecast-who (immunization forecasting)
- [x] $export (bulk data — system, group, patient levels)
- [x] $validate-code (CodeSystem, ValueSet)
- [x] $lookup (CodeSystem)
- [x] $expand (ValueSet)

### Middleware — DONE

- [x] Request logging with stream for live monitoring
- [x] CORS
- [x] Content negotiation
- [x] JWT auth (with dev-mode bypass)
- [x] Audit logging (AuditEvent resources)
- [x] Rate limiting (configurable)

### Mobile App — DONE

- [x] Flutter app with dashboard UI
- [x] Server start/stop with foreground service (Android)
- [x] Network info display with QR code
- [x] Resource counts (auto-refresh every 10s)
- [x] Live request log
- [x] Resource browser with JSON/YAML toggle
- [x] Clickable FHIR references with navigation stack
- [x] MIMIC-IV sample data loading
- [x] Published on Google Play Store
- [ ] iOS build and testing

### Infrastructure — PARTIAL

- [x] HTTPS support (self-signed or provided certs)
- [x] Health check endpoint
- [x] CapabilityStatement (metadata)
- [x] Configurable rate limiting
- [ ] Docker support
- [ ] CI/CD pipeline

## Given/When/Then Scenarios

### Authentication

```gherkin
Scenario: User registers and logs in
  Given the server is running
  When a user POSTs to /auth/register with username and password
  Then a 201 response is returned with the user record
  When the user POSTs to /auth/login with those credentials
  Then a 200 response is returned with access_token and refresh_token

Scenario: Token refresh
  Given a user has a valid refresh token
  When the user POSTs to /auth/token with the refresh token
  Then a new access token is returned

Scenario: Account lockout
  Given a user exists
  When 5 failed login attempts are made
  Then subsequent login attempts return 423 Locked
  And the account unlocks after 15 minutes

Scenario: SMART scope enforcement
  Given a user has scope "patient/Patient.read"
  When the user tries to POST a new Patient
  Then a 403 Forbidden is returned
  When the user tries to GET a Patient
  Then the Patient resource is returned

Scenario: Dev mode bypass
  Given the server is started with devMode: true
  When any request is made without an Authorization header
  Then the request proceeds as an admin user
```

### CRUD Operations

```gherkin
Scenario: Create and read a resource
  Given an authenticated user
  When a Patient resource is POSTed to /Patient
  Then a 201 response is returned with Location header
  And the resource has an auto-generated id and versionId
  When GET /Patient/{id} is requested
  Then the created Patient is returned

Scenario: Update a resource
  Given an existing Patient with id "123"
  When a PUT is sent to /Patient/123 with modified data
  Then a 200 response is returned
  And the versionId is incremented
  And the previous version is in history

Scenario: Delete a resource
  Given an existing Patient with id "123"
  When DELETE /Patient/123 is sent
  Then a 204 response is returned
  And GET /Patient/123 returns 410 Gone

Scenario: Conditional delete
  Given multiple Observation resources
  When DELETE /Observation?patient=123 is sent
  Then all matching Observations are deleted
```

### Search

```gherkin
Scenario: Basic search with pagination
  Given 50 Patient resources exist
  When GET /Patient?_count=10 is requested
  Then a Bundle with 10 entries is returned
  And Bundle.link contains next, last links

Scenario: Reference chaining
  Given a Patient with organization reference to "Organization/hospital-1"
  And Organization/hospital-1 has name "City Hospital"
  When GET /Patient?organization.name=City is requested
  Then the Patient is returned in results

Scenario: Compartment search
  Given Patient/123 has associated Observations
  When GET /Patient/123/Observation is requested
  Then only Observations referencing Patient/123 are returned

Scenario: Include
  Given an Observation referencing Patient/456
  When GET /Observation?_include=Observation:patient is requested
  Then the Bundle contains the Observation and Patient/456
```

### Operations

```gherkin
Scenario: Patient $everything
  Given Patient/123 exists with Observations, Conditions, and MedicationRequests
  When GET /Patient/123/$everything is requested
  Then a Bundle containing the Patient and all related resources is returned

Scenario: Composition $document
  Given a Composition resource referencing sections
  When GET /Composition/{id}/$document is requested
  Then a document Bundle is returned

Scenario: Bulk export
  Given resources exist in the database
  When GET /$export is requested with Accept: application/fhir+ndjson
  Then a 202 response is returned with Content-Location polling URL
  When the polling URL is checked after completion
  Then NDJSON file URLs are returned

Scenario: Terminology $validate-code
  Given a CodeSystem exists with code "active"
  When GET /CodeSystem/{id}/$validate-code?code=active is requested
  Then a Parameters resource is returned with result=true
```

### Mobile App

```gherkin
Scenario: Start server on Android
  Given the app is installed on Android
  When the user taps "Start Server"
  Then the server starts on the configured port
  And a foreground service notification appears
  And the QR code shows the server URL

Scenario: Server survives backgrounding on Android
  Given the server is running on Android
  When the user switches to another app
  Then the foreground service keeps the server running
  And requests from other devices still succeed

Scenario: Load MIMIC sample data
  Given the server is running with an empty database
  When the user loads MIMIC sample data
  Then clinical resources are bulk-loaded
  And the resource count card updates
```

## Boundaries

### Always

- Run `flutter test` before commits (both fhirant_server and fhirant_db)
- Return `OperationOutcome` for all error responses
- Encrypt database at rest (SQLCipher) in production
- Auto-version resources on save
- Index search parameters on resource save
- Validate resource type in URL path against `R4ResourceType` enum

### Ask First

- Schema changes to Drift tables (requires migration + build_runner)
- Changes to auth flow (JWT claims, token lifetime, scope format)
- Adding new middleware to the pipeline
- Changes to search_parameters.dart generation logic
- Modifying the mobile app's foreground service configuration

### Never

- Commit secrets or encryption keys
- Edit `search_parameters.dart` by hand (it's generated — modify the generator)
- Read test assets recursively (20,000+ files)
- Read `fhirant_db.g.dart` (generated Drift code)
- Use XML serialization (JSON only)
