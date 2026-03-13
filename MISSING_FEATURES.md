# Missing Features in FHIRant Server

## Errors/User suggestions
- "Application not responding" on first load, continuously displayed on first run
- Easier display, allow individual resources to be seen (yaml/json)
  - ideally with links

**Last Updated**: Current implementation status after major feature additions

## Database Layer (Search Functionality)

### Search Parameter Types
- ✅ String search - IMPLEMENTED
- ✅ Token search - IMPLEMENTED  
- ✅ Date search - IMPLEMENTED
- ✅ Number search - IMPLEMENTED
- ✅ Quantity search - IMPLEMENTED
- ✅ URI search - IMPLEMENTED
- ✅ Reference search - IMPLEMENTED (with chaining support)
- ✅ Composite search - IMPLEMENTED
- ✅ Special search parameters - MOSTLY IMPLEMENTED
  - ✅ _id - IMPLEMENTED
  - ✅ _lastUpdated - IMPLEMENTED
  - ✅ _tag - IMPLEMENTED
  - ✅ _profile - IMPLEMENTED
  - ✅ _security - IMPLEMENTED
  - ✅ _source - IMPLEMENTED
  - ❌ _has - NOT IMPLEMENTED (reverse chaining - complex)

### Search Features
- ✅ Combining multiple parameters with AND logic - IMPLEMENTED
- ✅ OR logic within a single parameter (comma-separated values) - IMPLEMENTED
- ✅ Sorting (_sort parameter) - IMPLEMENTED
- ✅ Include/RevInclude (_include and _revinclude) - IMPLEMENTED
- ❌ Response shaping (_summary and _elements) - NOT IMPLEMENTED
- ❌ Contained resources (_contained and _containedType) - NOT IMPLEMENTED
- ❌ FHIRPath filtering (_filter parameter) - NOT IMPLEMENTED
- ❌ Accent normalization for string searches - NOT IMPLEMENTED (marked as TODO)

## Server Layer - Core RESTful API

### HTTP Methods
- ✅ DELETE /{resourceType}/{id} - IMPLEMENTED

### Search Implementation
- ✅ getResourcesHandler uses search functionality - IMPLEMENTED
- ✅ Search parameters from query string are parsed and used - IMPLEMENTED
- ✅ Pagination, sorting, includes all handled - IMPLEMENTED

### CapabilityStatement
- ✅ /metadata returns enhanced CapabilityStatement with:
  - ✅ Search parameters for each resource type
  - ✅ Supported operations ($validate)
  - ✅ Search parameter details (type, modifiers)
  - ✅ Interaction codes (search-type, delete enabled)
  - ⏭️ Additional operations ($everything, etc.) - PARTIALLY IMPLEMENTED

### FHIR Operations
- ✅ $validate - IMPLEMENTED (basic)
- ❌ $everything - NOT IMPLEMENTED (e.g., Patient/$everything)
- ❌ $document - NOT IMPLEMENTED
- ❌ $expand - NOT IMPLEMENTED (for ValueSet)
- ❌ $lookup - NOT IMPLEMENTED (for CodeSystem)
- ❌ $translate - NOT IMPLEMENTED (for ConceptMap)
- ❌ $closure - NOT IMPLEMENTED
- ❌ $subsumes - NOT IMPLEMENTED

### Conditional Operations
- ❌ If-None-Exist header support - NOT IMPLEMENTED (for conditional create)
- ❌ If-Match header support - NOT IMPLEMENTED (for conditional update)
- ❌ Conditional delete - NOT IMPLEMENTED

### Subscriptions
- ❌ Subscription resource support - NOT IMPLEMENTED
- ❌ Subscription notification handling - NOT IMPLEMENTED
- ❌ WebSocket subscription notifications - NOT IMPLEMENTED (websocket handler exists but not functional)

### Compartments
- ❌ Compartment-based access control - NOT IMPLEMENTED
- ❌ Compartment queries (e.g., /Patient/{id}/Observation) - NOT IMPLEMENTED

### HTTP Headers & Standards
- ❌ ETag support - NOT IMPLEMENTED (for version-aware updates)
- ❌ Last-Modified header - NOT IMPLEMENTED
- ✅ Location header - IMPLEMENTED (set on POST)
- ❌ Prefer header - NOT IMPLEMENTED (return=minimal, return=representation)
- ❌ Vary header - NOT IMPLEMENTED
- ❌ Content-Location header - NOT IMPLEMENTED

### Content Types
- ✅ application/fhir+json - IMPLEMENTED
- ❌ application/fhir+xml - NOT IMPLEMENTED
- ❌ application/json - NOT IMPLEMENTED (fallback)
- ❌ application/xml - NOT IMPLEMENTED
- ❌ Content negotiation (Accept header) - NOT IMPLEMENTED

### Bundle Features
- ⚠️ Accurate total count in search result bundles - PARTIALLY IMPLEMENTED (uses resources.length, TODO for separate count query)
- ✅ Bundle.link entries for pagination - IMPLEMENTED (first, previous, next, last)
- ⚠️ Bundle.total accurate count - PARTIALLY IMPLEMENTED (needs separate count query)

### Error Handling
- ✅ OperationOutcome resources for errors - IMPLEMENTED
- ⚠️ Detailed OperationOutcome - PARTIALLY IMPLEMENTED (could be enhanced with more issue codes)
- ✅ Proper HTTP status codes (400, 404, 500) - IMPLEMENTED
- ❌ Additional status codes (409, 412) - NOT IMPLEMENTED (for conditional operations)

### Validation
- ✅ Basic $validate operation - IMPLEMENTED
- ❌ Detailed validation results - NOT FULLY IMPLEMENTED
- ❌ Profile validation - NOT IMPLEMENTED
- ❌ Terminology validation - NOT IMPLEMENTED

### Security
- ❌ OAuth2 authentication - NOT IMPLEMENTED
- ❌ SMART on FHIR - NOT IMPLEMENTED
- ❌ JWT validation - NOT IMPLEMENTED
- ❌ Token-based authorization - NOT IMPLEMENTED
- ❌ Scope-based access control - NOT IMPLEMENTED
- ✅ Basic auth middleware exists but is commented out

### CORS
- ❌ CORS headers - NOT IMPLEMENTED (needed for web clients)

### Audit Logging
- ❌ Audit logging to logs table - NOT IMPLEMENTED
  - Logs table exists in database
  - No audit log entries are being created for operations
  - Should log: create, read, update, delete, search operations

### GraphQL
- ❌ FHIR GraphQL endpoint - NOT IMPLEMENTED (optional but mentioned in TODOs)

## Deployment

### Docker
- ❌ Dockerfile - NOT CREATED
- ❌ docker-compose.yml - NOT CREATED

### Configuration
- ❌ Configuration system for different deployment modes - NOT IMPLEMENTED
- ❌ Environment-based configuration - NOT IMPLEMENTED

### Flutter Mobile
- ✅ dart:io is supported (iOS/Android) - COMPATIBLE
- ❌ Isolate-based server execution - NOT IMPLEMENTED (should run in separate isolate)
- ❌ Mobile permissions handling - NOT IMPLEMENTED (network, storage)
- ❌ Portable paths for database/certificates - NEEDS VERIFICATION

## Summary

**Total Missing Items: ~30+** (down from ~50+)

### Critical Missing (Core FHIR Functionality):
1. ✅ ~~DELETE endpoint~~ - **COMPLETE**
2. ✅ ~~Full search implementation~~ - **COMPLETE**
3. ✅ ~~Reference search with chaining~~ - **COMPLETE**
4. ✅ ~~Special search parameters~~ - **COMPLETE** (except _has)
5. ✅ ~~Sorting, includes~~ - **COMPLETE**
6. ❌ Conditional operations - NOT IMPLEMENTED
7. ⚠️ Proper OperationOutcome error responses - PARTIALLY IMPLEMENTED
8. ✅ ~~Complete CapabilityStatement~~ - **COMPLETE**

### Important Missing (FHIR Standards):
9. FHIR operations ($everything, $document, etc.) - NOT IMPLEMENTED
10. Subscriptions - NOT IMPLEMENTED
11. Compartments - NOT IMPLEMENTED
12. ETag/Last-Modified support - NOT IMPLEMENTED
13. Content negotiation - NOT IMPLEMENTED
14. Audit logging - NOT IMPLEMENTED
15. Response shaping (_summary, _elements) - NOT IMPLEMENTED

### Nice to Have:
16. GraphQL - NOT IMPLEMENTED
17. Advanced security (OAuth2, SMART) - NOT IMPLEMENTED
18. Docker deployment - NOT IMPLEMENTED
19. Enhanced configuration - NOT IMPLEMENTED
20. _has search (reverse chaining) - NOT IMPLEMENTED

## Progress Summary

**Phase 1 (Core REST API)**: ✅ **~95% Complete**
- All CRUD operations ✅
- Search infrastructure ✅
- Basic search ✅
- History ✅
- Bundles ✅
- CapabilityStatement ✅

**Phase 2 (Search Enhancements)**: ✅ **~90% Complete**
- Special parameters: 5/6 done (_id, _lastUpdated, _tag, _profile, _security, _source)
- Sorting: ✅ Done
- Reference chaining: ✅ Done
- Composite: ✅ Done
- Include/RevInclude: ✅ Done

**Phase 3 (Advanced Features)**: ⏭️ **~10% Complete**
- Operations: 1/8 done ($validate)
- Subscriptions: Not started
- Compartments: Not started

**Phase 4 (Production Ready)**: ⏭️ **~15% Complete**
- Security: Basic structure
- Deployment: Not started
- Configuration: Not started
