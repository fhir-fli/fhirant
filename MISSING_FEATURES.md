# Missing Features in FHIRant Server

## Database Layer (Search Functionality)

### Search Parameter Types (Partially Complete)
- ✅ String search - IMPLEMENTED
- ✅ Token search - IMPLEMENTED  
- ✅ Date search - IMPLEMENTED
- ✅ Number search - IMPLEMENTED
- ✅ Quantity search - IMPLEMENTED
- ✅ URI search - IMPLEMENTED
- ❌ Reference search - NOT IMPLEMENTED (with chaining support)
- ❌ Composite search - NOT IMPLEMENTED
- ❌ Special search parameters - PARTIALLY IMPLEMENTED
  - ✅ _id - IMPLEMENTED
  - ❌ _lastUpdated - NOT IMPLEMENTED
  - ❌ _tag - NOT IMPLEMENTED
  - ❌ _profile - NOT IMPLEMENTED
  - ❌ _security - NOT IMPLEMENTED
  - ❌ _source - NOT IMPLEMENTED
  - ❌ _has - NOT IMPLEMENTED

### Search Features
- ✅ Combining multiple parameters with AND logic - IMPLEMENTED
- ❌ OR logic within a single parameter (comma-separated values) - NOT IMPLEMENTED
- ❌ Sorting (_sort parameter) - NOT IMPLEMENTED
- ❌ Include/RevInclude (_include and _revinclude) - NOT IMPLEMENTED
- ❌ Response shaping (_summary and _elements) - NOT IMPLEMENTED
- ❌ Contained resources (_contained and _containedType) - NOT IMPLEMENTED
- ❌ FHIRPath filtering (_filter parameter) - NOT IMPLEMENTED
- ❌ Accent normalization for string searches - NOT IMPLEMENTED (marked as TODO)

## Server Layer - Core RESTful API

### Missing HTTP Methods
- ❌ DELETE /{resourceType}/{id} - NOT IMPLEMENTED (endpoint missing)

### Search Implementation
- ❌ getResourcesHandler does NOT use search functionality - only uses pagination
- ❌ Search parameters from query string are NOT parsed or used
- ❌ Only _count and _offset are currently handled

### CapabilityStatement
- ❌ /metadata returns basic CapabilityStatement but missing:
  - Search parameters for each resource type
  - Supported operations ($validate, $everything, etc.)
  - Search parameter details (type, modifiers, etc.)
  - Interaction codes (search-type is commented out)
  - Delete interaction is commented out

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
- ✅ Location header - PARTIALLY IMPLEMENTED (set on POST, but may need enhancement)
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
- ❌ Accurate total count in search result bundles - NOT IMPLEMENTED (currently returns result.length, not actual total)
- ❌ Bundle.link entries for pagination - NOT IMPLEMENTED (first, previous, next, last)
- ❌ Bundle.total accurate count - NOT IMPLEMENTED

### Error Handling
- ❌ Proper OperationOutcome resources for all errors - NOT IMPLEMENTED
  - Currently returns simple error messages
  - Should return structured OperationOutcome with proper issue codes
  - Should include proper HTTP status codes (400, 404, 409, 412, etc.)

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

**Total Missing Items: ~50+**

### Critical Missing (Core FHIR Functionality):
1. DELETE endpoint
2. Full search implementation (using search parameters)
3. Reference search with chaining
4. Special search parameters (_lastUpdated, _tag, _profile, etc.)
5. Sorting, includes, summaries
6. Conditional operations
7. Proper OperationOutcome error responses
8. Complete CapabilityStatement

### Important Missing (FHIR Standards):
9. FHIR operations ($everything, $document, etc.)
10. Subscriptions
11. Compartments
12. ETag/Last-Modified support
13. Content negotiation
14. Audit logging

### Nice to Have:
15. GraphQL
16. Advanced security (OAuth2, SMART)
17. Docker deployment
18. Enhanced configuration

