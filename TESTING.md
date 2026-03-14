# TESTING.md — FHIRant Test Inventory

## Summary

**690 tests** across 45 test files, all passing.

| Package | Tests | Files | Command |
|---------|-------|-------|---------|
| fhirant_server | 582 | 42 | `cd packages/fhirant_server && flutter test` |
| fhirant_db | 108 | 3 | `cd packages/fhirant_db && flutter test` |
| fhirant_logging | 0 | 0 | — |
| fhirant_secure_storage | 0 | 0 | — |

## Test Organization

### fhirant_server — Handler Tests (24 files)

| File | Description |
|------|-------------|
| `test/handlers/auth_handler_test.dart` | Register + login flows |
| `test/handlers/authorize_handler_test.dart` | OAuth authorize endpoint |
| `test/handlers/refresh_handler_test.dart` | Token refresh |
| `test/handlers/revoke_handler_test.dart` | Token revocation |
| `test/handlers/resource_handler_test.dart` | GET resources / search |
| `test/handlers/get_resource_by_id_handler_test.dart` | GET by ID |
| `test/handlers/post_resource_handler_test.dart` | POST create |
| `test/handlers/put_resource_handler_test.dart` | PUT update |
| `test/handlers/patch_handler_test.dart` | PATCH (JSON Patch) |
| `test/handlers/bundle_handler_test.dart` | Transaction/batch bundles |
| `test/handlers/history_handler_test.dart` | History endpoints |
| `test/handlers/compartment_handler_test.dart` | Compartment search |
| `test/handlers/metadata_handler_test.dart` | CapabilityStatement |
| `test/handlers/health_handler_test.dart` | Health check |
| `test/handlers/validate_handler_test.dart` | $validate |
| `test/handlers/terminology_handler_test.dart` | $validate-code, $lookup, $expand |
| `test/handlers/export_handler_test.dart` | Bulk export |
| `test/handlers/backup_handler_test.dart` | $backup / $restore |
| `test/handlers/fhirpath_handler_test.dart` | $fhirpath |
| `test/handlers/cql_handler_test.dart` | $cql / Library/$evaluate |
| `test/handlers/forecast_handler_test.dart` | $immds-forecast |
| `test/handlers/document_handler_test.dart` | $document |
| `test/handlers/meta_handler_test.dart` | $meta / $meta-add / $meta-delete |
| `test/handlers/elements_test.dart` | _elements response shaping |

### fhirant_server — Middleware Tests (4 files)

| File | Description |
|------|-------------|
| `test/middleware/auth_middleware_test.dart` | JWT validation, scope enforcement |
| `test/middleware/audit_middleware_test.dart` | AuditEvent creation |
| `test/middleware/cors_middleware_test.dart` | CORS headers |
| `test/middleware/content_negotiation_test.dart` | Accept/Content-Type handling |

### fhirant_server — Utility Tests (4 files)

| File | Description |
|------|-------------|
| `test/utils/search_parser_test.dart` | Search parameter parsing |
| `test/utils/smart_scopes_test.dart` | SMART scope parsing + enforcement |
| `test/utils/password_hasher_test.dart` | bcrypt hashing |
| `test/utils/password_policy_test.dart` | Password strength rules |

### fhirant_server — Integration Tests (10 files)

| File | Description |
|------|-------------|
| `test/integration/crud_lifecycle_test.dart` | Full create/read/update/delete cycle |
| `test/integration/search_e2e_test.dart` | Search with real DB |
| `test/integration/has_search_e2e_test.dart` | _has reverse chaining |
| `test/integration/bundle_e2e_test.dart` | Transaction/batch with real DB |
| `test/integration/compartment_e2e_test.dart` | Compartment search with real DB |
| `test/integration/export_integration_test.dart` | Bulk export end-to-end |
| `test/integration/auth_flow_test.dart` | Full auth lifecycle |
| `test/integration/dev_mode_test.dart` | Dev mode auth bypass |
| `test/integration/smart_scopes_e2e_test.dart` | SMART scope enforcement end-to-end |
| `test/integration/middleware_pipeline_test.dart` | Full middleware chain |

### fhirant_db — Unit Tests (3 files)

| File | Description |
|------|-------------|
| `test/unit/fhirant_db_test.dart` | CRUD operations |
| `test/unit/history_test.dart` | Version history |
| `test/unit/search_test.dart` | Search parameter indexing + querying |

## Running Tests

```bash
# All server tests
cd packages/fhirant_server && flutter test

# All database tests
cd packages/fhirant_db && flutter test

# Single test file
cd packages/fhirant_server && flutter test test/handlers/auth_handler_test.dart

# With verbose output
cd packages/fhirant_server && flutter test --reporter expanded

# With coverage
cd packages/fhirant_server && flutter test --coverage
```

## Test Infrastructure

- **Framework**: `flutter_test` (required because `fhirant_db` has Flutter dependencies)
- **Mocking**: `mocktail` — `FhirAntDb` is mocked in all server handler tests
- **Integration tests**: use real in-memory `FhirAntDb` instances (no SQLCipher, no encryption)
- **DB tests**: require sqlite3 native library installed on the system

## Coverage Gaps

- **fhirant_secure_storage** — 0 tests. Wraps `flutter_secure_storage`; needs mock-based unit tests.
- **fhirant_logging** — 0 tests. Simple singleton; needs basic smoke tests.
- **Coverage reporting** — not yet configured in CI.
- **Conformance suite** — no automated FHIR conformance/Touchstone testing.
