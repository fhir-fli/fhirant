# FHIRant Server Implementation Plan

## Current State Analysis

### ✅ What's Working
- **Database Layer**: Search parameter tables exist (string, token, date, number, quantity, uri, reference, composite, special)
- **Database Interface**: Has `search()` method that accepts `searchParameters` map
- **Basic CRUD**: GET (by ID), POST (create), PUT (update), PATCH (partial update) are implemented
- **History**: Resource history endpoints are implemented
- **Bundle**: Transaction/batch bundle handler exists
- **Operations**: Basic `$validate` operation exists
- **Error Responses**: Already using OperationOutcome (though could be enhanced)

### ❌ Critical Gaps
1. **DELETE endpoint** - Database has `deleteResource()` but no HTTP handler
2. **Search not connected** - `getResourcesHandler` uses pagination only, ignores search parameters
3. **CapabilityStatement incomplete** - Missing search params, operations, delete interaction

## Prioritized Implementation Plan

### Phase 1: Core REST API Completion (Critical - Week 1)

#### 1.1 DELETE Endpoint (HIGH PRIORITY - 2-4 hours)
**Status**: Database method exists, just needs HTTP handler
- [ ] Add `deleteResourceHandler` in `resource_handler.dart`
- [ ] Add DELETE route in `fhirant_server.dart` router
- [ ] Return proper HTTP 204 (No Content) or 200 with OperationOutcome
- [ ] Handle soft delete vs hard delete (consider meta.status)
- [ ] Update CapabilityStatement to include delete interaction

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`
- `packages/fhirant_server/lib/src/fhirant_server.dart`

#### 1.2 Connect Search to Handler (HIGH PRIORITY - 4-6 hours)
**Status**: Database search exists, handler needs to use it
- [ ] Parse query parameters from request URL
- [ ] Separate search params from pagination params (_count, _offset, _sort)
- [ ] Call `dbInterface.search()` instead of `getResourcesWithPagination()`
- [ ] Handle special parameters (_id, _lastUpdated, etc.)
- [ ] Return proper search result Bundle with accurate total count

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`
- Create: `packages/fhirant_server/lib/src/utils/search_parser.dart` (new utility)

**Key Implementation**:
```dart
// Parse query parameters
final queryParams = request.url.queryParameters;
final searchParams = <String, List<String>>{};
final paginationParams = <String, String>{};

for (var entry in queryParams.entries) {
  if (entry.key.startsWith('_') && 
      ['_count', '_offset', '_sort', '_include', '_revinclude', 
       '_summary', '_elements'].contains(entry.key)) {
    paginationParams[entry.key] = entry.value;
  } else {
    searchParams[entry.key] = [entry.value]; // Handle comma-separated
  }
}

// Use search method
final resources = await dbInterface.search(
  resourceType: type,
  searchParameters: searchParams.isEmpty ? null : searchParams,
  count: count,
  offset: offset,
  sort: sortParams,
);
```

#### 1.3 Enhanced CapabilityStatement (MEDIUM PRIORITY - 3-4 hours)
- [ ] Add search parameters for each resource type
- [ ] Add supported operations ($validate, $everything, etc.)
- [ ] Add search parameter details (type, modifiers)
- [ ] Enable search-type and delete interactions
- [ ] Add search parameter definitions from FHIR spec

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/metadata_handler.dart`
- May need: `packages/fhirant_server/lib/src/utils/capability_builder.dart` (new)

### Phase 2: Search Enhancements (Week 2)

#### 2.1 Special Search Parameters (HIGH PRIORITY - 6-8 hours)
- [ ] Implement `_lastUpdated` search (use meta.lastUpdated)
- [ ] Implement `_tag` search (use meta.tag)
- [ ] Implement `_profile` search (use meta.profile)
- [ ] Implement `_security` search (use meta.security)
- [ ] Implement `_source` search (use meta.source)
- [ ] Implement `_has` search (reverse chaining - complex)

**Files to modify**:
- `packages/fhirant_db/lib/db/search/search.dart` (or search implementation)
- May need to extend special_search_table.dart

#### 2.2 Reference Search with Chaining (HIGH PRIORITY - 8-10 hours)
- [ ] Implement basic reference search (already have table)
- [ ] Add reference chaining support (e.g., `Patient?organization.name=Hospital`)
- [ ] Handle reverse references
- [ ] Support multiple chain levels

**Files to modify**:
- `packages/fhirant_db/lib/db/search/search.dart`
- `packages/fhirant_db/lib/db/tables/reference_search_table.dart`

#### 2.3 Composite Search (MEDIUM PRIORITY - 4-6 hours)
- [ ] Implement composite search parameter handling
- [ ] Support composite parameter syntax (e.g., `code-value-quantity=8480-6$gt100`)

**Files to modify**:
- `packages/fhirant_db/lib/db/search/search.dart`
- `packages/fhirant_db/lib/db/tables/composite_search_table.dart`

#### 2.4 Sorting (_sort) (MEDIUM PRIORITY - 3-4 hours)
- [ ] Parse `_sort` parameter (e.g., `_sort=name,-date`)
- [ ] Implement sorting in database query
- [ ] Support ascending/descending (prefix with `-`)

**Files to modify**:
- `packages/fhirant_db/lib/db/search/search.dart`
- `packages/fhirant_server/lib/src/utils/search_parser.dart`

#### 2.5 OR Logic (comma-separated values) (MEDIUM PRIORITY - 2-3 hours)
- [ ] Parse comma-separated values in search parameters
- [ ] Convert to OR logic in database query
- [ ] Example: `name=Smith,Jones` → name=Smith OR name=Jones

**Files to modify**:
- `packages/fhirant_server/lib/src/utils/search_parser.dart`
- `packages/fhirant_db/lib/db/search/search.dart`

### Phase 3: Bundle & Response Features (Week 3)

#### 3.1 Accurate Bundle Total (MEDIUM PRIORITY - 2-3 hours)
- [ ] Get total count from database (separate count query)
- [ ] Set Bundle.total to actual total, not result.length
- [ ] Handle count queries efficiently

**Files to modify**:
- `packages/fhirant_db/lib/db/fhirant_db.dart` (add count method)
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`

#### 3.2 Pagination Links (MEDIUM PRIORITY - 3-4 hours)
- [ ] Generate Bundle.link entries (first, previous, next, last)
- [ ] Calculate based on total count, current offset, and count
- [ ] Build proper URLs with all search parameters preserved

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`
- Create: `packages/fhirant_server/lib/src/utils/bundle_builder.dart` (new)

#### 3.3 Include/RevInclude (MEDIUM PRIORITY - 6-8 hours)
- [ ] Parse `_include` and `_revinclude` parameters
- [ ] Fetch referenced resources
- [ ] Add to Bundle.entry
- [ ] Support multiple levels (e.g., `_include:iterate`)

**Files to modify**:
- `packages/fhirant_server/lib/src/utils/search_parser.dart`
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`

#### 3.4 Response Shaping (_summary, _elements) (LOW PRIORITY - 4-6 hours)
- [ ] Implement `_summary` parameter (true, data, text, count)
- [ ] Implement `_elements` parameter (subset of elements)
- [ ] Filter resource fields before returning

**Files to modify**:
- `packages/fhirant_server/lib/src/utils/response_shaper.dart` (new)
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`

### Phase 4: HTTP Standards (Week 4)

#### 4.1 ETag & Last-Modified (MEDIUM PRIORITY - 3-4 hours)
- [ ] Generate ETag from resource versionId
- [ ] Set Last-Modified from meta.lastUpdated
- [ ] Check If-Match header for conditional updates
- [ ] Return 412 Precondition Failed if version mismatch

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`
- `packages/fhirant_server/lib/src/middlewares/conditional_middleware.dart` (new)

#### 4.2 Conditional Operations (MEDIUM PRIORITY - 4-5 hours)
- [ ] If-None-Exist header for conditional create
- [ ] If-Match header for conditional update
- [ ] Conditional delete support

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`
- `packages/fhirant_server/lib/src/middlewares/conditional_middleware.dart`

#### 4.3 Content Negotiation (LOW PRIORITY - 4-6 hours)
- [ ] Parse Accept header
- [ ] Support application/fhir+json (current)
- [ ] Support application/fhir+xml (requires XML serialization)
- [ ] Support application/json fallback
- [ ] Return 406 Not Acceptable if unsupported format

**Files to modify**:
- `packages/fhirant_server/lib/src/middlewares/content_negotiation_middleware.dart` (new)
- May need XML serialization library

#### 4.4 Prefer Header (LOW PRIORITY - 2-3 hours)
- [ ] Handle Prefer: return=minimal (204 No Content)
- [ ] Handle Prefer: return=representation (200/201 with body)

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/resource_handler.dart`

### Phase 5: FHIR Operations (Week 5)

#### 5.1 $everything Operation (HIGH PRIORITY - 6-8 hours)
- [ ] Implement Patient/$everything
- [ ] Return all related resources (Observations, Conditions, etc.)
- [ ] Support other resource types with $everything
- [ ] Handle pagination for large result sets

**Files to create**:
- `packages/fhirant_server/lib/src/handlers/everything_handler.dart`

**Files to modify**:
- `packages/fhirant_server/lib/src/fhirant_server.dart` (add route)

#### 5.2 Other Operations (LOW PRIORITY - varies)
- [ ] $document (Document generation)
- [ ] $expand (ValueSet expansion)
- [ ] $lookup (CodeSystem lookup)
- [ ] $translate (ConceptMap translation)
- [ ] $closure (Closure table management)
- [ ] $subsumes (Code subsumption)

### Phase 6: Advanced Features (Week 6+)

#### 6.1 Audit Logging (MEDIUM PRIORITY - 4-5 hours)
- [ ] Log all CRUD operations to logs table
- [ ] Log search operations
- [ ] Include user, timestamp, resource type, operation type
- [ ] Create audit log middleware

**Files to modify**:
- `packages/fhirant_server/lib/src/middlewares/audit_middleware.dart` (new)
- All handlers to trigger audit logs

#### 6.2 CORS Support (LOW PRIORITY - 1-2 hours)
- [ ] Add CORS headers middleware
- [ ] Support OPTIONS preflight requests
- [ ] Configurable allowed origins

**Files to create**:
- `packages/fhirant_server/lib/src/middlewares/cors_middleware.dart`

#### 6.3 Enhanced Error Handling (MEDIUM PRIORITY - 3-4 hours)
- [ ] Use proper HTTP status codes (400, 404, 409, 412, etc.)
- [ ] Return detailed OperationOutcome with proper issue codes
- [ ] Include diagnostics and location information

**Files to modify**:
- All handlers
- Create: `packages/fhirant_server/lib/src/utils/error_builder.dart` (new)

#### 6.4 Compartments (LOW PRIORITY - 8-10 hours)
- [ ] Implement compartment-based queries
- [ ] Support /Patient/{id}/Observation syntax
- [ ] Handle compartment definitions

**Files to create**:
- `packages/fhirant_server/lib/src/handlers/compartment_handler.dart`

#### 6.5 Subscriptions (LOW PRIORITY - 10-15 hours)
- [ ] Subscription resource support
- [ ] Subscription notification handling
- [ ] WebSocket subscription notifications
- [ ] REST-hook subscriptions

**Files to modify**:
- `packages/fhirant_server/lib/src/handlers/websocket_handler.dart`
- Create subscription management system

### Phase 7: Deployment & Configuration (Ongoing)

#### 7.1 Docker Support (LOW PRIORITY - 2-3 hours)
- [ ] Create Dockerfile
- [ ] Create docker-compose.yml
- [ ] Multi-stage build for smaller image

#### 7.2 Configuration System (LOW PRIORITY - 3-4 hours)
- [ ] Environment-based configuration
- [ ] Config file support
- [ ] Different deployment modes (dev, prod)

## Implementation Order Recommendation

### Immediate (This Week)
1. **DELETE endpoint** - Quick win, database method exists
2. **Connect search to handler** - Unlocks full search functionality
3. **Enhanced CapabilityStatement** - Shows what server supports

### Short Term (Next 2 Weeks)
4. Special search parameters (_lastUpdated, _tag, etc.)
5. Reference search with chaining
6. Sorting and OR logic
7. Accurate bundle totals and pagination links

### Medium Term (Next Month)
8. Include/RevInclude
9. ETag/Last-Modified support
10. Conditional operations
11. $everything operation
12. Audit logging

### Long Term (Future)
13. Advanced operations ($document, $expand, etc.)
14. Subscriptions
15. Compartments
16. Content negotiation (XML)
17. Security enhancements (OAuth2, SMART)

## Dependencies

- **DELETE endpoint** → No dependencies, can start immediately
- **Search connection** → No dependencies, database search exists
- **Reference chaining** → Needs basic reference search working
- **Include/RevInclude** → Needs search working
- **Bundle links** → Needs accurate total count
- **ETag/Last-Modified** → Needs version tracking (already exists)
- **$everything** → Needs search and reference resolution

## Testing Strategy

For each feature:
1. Unit tests for parsing/utility functions
2. Integration tests for database operations
3. End-to-end tests for HTTP endpoints
4. Test with real FHIR clients (HAPI, etc.)

## Notes

- The database layer is well-structured with search parameter tables
- The server layer needs to better utilize the database capabilities
- Many features are "plumbing" - connecting existing pieces
- Focus on core REST API first, then advanced features
- Consider FHIR R4 specification compliance as you implement

