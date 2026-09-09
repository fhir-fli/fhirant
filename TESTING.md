# TESTING.md — FHIRant Test Inventory

## Summary

**1,272 tests** across 99 test files, all passing. Counted 2026-09-09 by
running every package the way `.github/workflows/ci.yml` runs it, not from
memory (the 2026-08-30 figure was 936 across 69; before that a months-old 690
across 45 that listed the Flutter app not at all and gave `flutter test` for
packages that have no `flutter_test` dependency and cannot be run that way).
The server, db and app packages need the gitignored `pubspec_overrides.yaml`
pointing `fhir_r4` and `fhir_r4_db` at the dev checkouts until the family's
next release.

The tool is not a preference. A package whose pubspec has `sdk: flutter`
must use `flutter test`; the pure Dart ones must use `dart test`.

| Package | Tests | Files | Command |
|---------|-------|-------|---------|
| fhirant_server | 1,110 | 87 | `cd packages/fhirant_server && dart test` |
| fhirant_db | 128 | 6 | `cd packages/fhirant_db && dart test` |
| fhirant | 34 | 4 | `cd packages/fhirant && flutter test` |
| fhirant_secure_storage | 11 | 1 | `cd packages/fhirant_secure_storage && flutter test` |
| fhirant_logging | 8 | 1 | `cd packages/fhirant_logging && dart test` |

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
| `test/handlers/elements_test.dart` | _elements and _summary response shaping, from the generated element metadata |
| `test/handlers/search_and_or_test.dart` | Repeated parameter = AND, comma = OR, through the REST path |
| `test/handlers/unsupported_modifier_test.dart` | A modifier the store does not support is a 400 |
| `test/handlers/search_refusal_test.dart` | The store's three refusals reach the client as 400 OperationOutcomes, at every entry point |
| `test/handlers/search_links_test.dart` | Self and paging links carry the parameters used; `_query` refused; `_count=0` |

### fhirant_server — Middleware Tests (4 files)

| File | Description |
|------|-------------|
| `test/middleware/auth_middleware_test.dart` | JWT validation, scope enforcement |
| `test/middleware/audit_middleware_test.dart` | AuditEvent creation |
| `test/middleware/cors_middleware_test.dart` | CORS headers |
| `test/middleware/content_negotiation_test.dart` | Accept/Content-Type handling |

### fhirant_server — Utility Tests (6 files)

| File | Description |
|------|-------------|
| `test/utils/search_parser_test.dart` | Search parameter parsing |
| `test/utils/smart_scopes_test.dart` | SMART scope parsing + enforcement |
| `test/utils/password_hasher_test.dart` | bcrypt hashing |
| `test/utils/password_policy_test.dart` | Password strength rules |
| `test/utils/json_patch_test.dart` | RFC 6902 arrays: `-` appends, add inserts and shifts, replace overwrites, move to `-` (6) |
| `test/utils/spec_loader_test.dart` | The specification loaded from an asset bundle in chunks, once (3) |

### fhirant_server — Service Tests (4 files)

| File | Description |
|------|-------------|
| `test/services/subscription_service_test.dart` | Criteria through the REST search, server-decided status, rest-hook delivery, failure policy, `end`; delivery from the queue after the write, deadline, order, back-pressure (30) |
| `test/services/websocket_subscriptions_test.dart` | `bind`/`ping` protocol and a websocket Subscription end to end (10) |
| `test/services/backup_service_test.dart` | Bundle-envelope backup and restore (10) |
| `test/services/backup_file_test.dart` | Encrypted SQLite backup file: create, restore, JSON detection (7) |

### fhirant_server — Integration Tests (13 files)

| File | Description |
|------|-------------|
| `test/integration/crud_lifecycle_test.dart` | Full create/read/update/delete cycle |
| `test/integration/search_e2e_test.dart` | Search with real DB |
| `test/integration/has_search_e2e_test.dart` | _has reverse chaining |
| `test/integration/bundle_e2e_test.dart` | Transaction/batch with real DB |
| `test/integration/compartment_e2e_test.dart` | Compartment search with real DB |
| `test/integration/export_integration_test.dart` | Bulk export end-to-end |
| `test/integration/export_scale_test.dart` | REVIEW-2026-09-06 finding 34: export file is the stored JSON streamed with Content-Length, `Expires` = completion + retention, the sweep removes expired jobs and orphan directories, a job left running at restart is reported failed, an empty type leaves no output item (5) |
| `test/integration/auth_flow_test.dart` | Full auth lifecycle |
| `test/integration/dev_mode_test.dart` | Dev mode auth bypass |
| `test/integration/smart_scopes_e2e_test.dart` | SMART scope enforcement end-to-end |
| `test/integration/middleware_pipeline_test.dart` | Full middleware chain |
| `test/integration/include_e2e_test.dart` | `_include`/`_revinclude` by search parameter through the reference index; the page's include budget (`maxIncluded`) and its outcome entry |
| `test/integration/system_search_e2e_test.dart` | The all-types search: common-parameter rule, one page across types |
| `test/integration/authorization_review_test.dart` | REVIEW-2026-09-06 §1: scope grant, refresh tokens, compartments, lockout, PKCE, pipeline order (19) |
| `test/integration/authorization_review_2026_09_08_test.dart` | REVIEW-2026-09-08 §1: the root path, Bundle entries, per-type compartment, history, system search, `$document`, `$evaluate`, conditional create/delete, includes, write bodies, export ownership, account re-read, authorize redirect, dev-mode registration (36) |
| `test/integration/wrong_answers_review_2026_09_08_test.dart` | REVIEW-2026-09-08 §2: POST ignores the client id, If-Match on PATCH and Bundle entries, JSON Patch replace, Bundle entry searches and conditional deletes, transaction processing order (2026-09-06 row 16), history paging links, versioned Location, OperationOutcome 404s, SUBSETTED as a tag, `$export` parameter refusal (22) |
| `test/integration/store_review_2026_09_08_test.dart` | REVIEW-2026-09-08 rows 35, 36, 42: restore merges accounts by username, the tombstone is a history column, the envelope check reads the file's head (5) |
| `test/integration/backup_file_e2e_test.dart` | `$backup` as an encrypted SQLite file, streamed; `$restore` of that file, the envelope or a Bundle (4) |
| `test/integration/integrity_review_test.dart` | REVIEW-2026-09-06 §3 at the HTTP surface: If-Match inside the write, stored resource returned, deleted-resource history and 410, meta kept on update, history paged in SQL (11) |
| `test/integration/hygiene_review_test.dart` | REVIEW-2026-09-06 §2 rows 21, 23, 24, 26 at the HTTP surface: `-` append through PATCH, Parameters patch 415 alone and in a Bundle, unsupported ValueSet compose refused by `$expand`, `$validate-code` and `:in`, `exclude.concept` honoured, unknown parameter ignored, a value ending in `:missing` is a value (9) |
| `test/integration/scale_review_test.dart` | REVIEW-2026-09-06 §5 at the HTTP surface: `_count` refused below zero and capped at 500 with the client's value in the self link, `$everything` paged before hydrating with links, conditional delete bounded at 100 and transactional (7) |
| `test/integration/base_url_test.dart` | `FhirAntServer.baseUrl` reaches the store; absolute references under it match |
| `test/integration/encounter_date_e2e_test.dart` | A Period-valued date parameter through the REST path |

### fhirant_db — Unit Tests (6 files)

| File | Description |
|------|-------------|
| `test/unit/fhirant_db_test.dart` | CRUD operations |
| `test/unit/history_test.dart` | Version history |
| `test/unit/search_test.dart` | Search parameter indexing + querying |
| `test/unit/schema_upgrade_test.dart` | Schema 14 rebuilds the search index from the stored resources |
| `test/unit/backup_file_test.dart` | `copyEncrypted`/`restoreEncrypted` refuse a build without the cipher (3) |
| `test/unit/export_stream_test.dart` | `exportJson` streams the stored JSON by rowid keyset, `since` and `ids` chunks; finished-job and stale-job queries for the export sweep (7) |

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
