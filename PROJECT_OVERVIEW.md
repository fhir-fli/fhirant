# FHIRant Server - Project Overview

## What is FHIRant?

**FHIRant** (Fast Healthcare Interoperability Resources Agile Networking Tool) is a **complete, standards-compliant FHIR R4 server** built with Dart/Flutter. The goal is to create a fully functional FHIR server that can be deployed standalone or integrated into Flutter applications, providing comprehensive healthcare data interoperability capabilities.

## Project Vision

Create a **production-ready FHIR R4 server** that:
- ✅ Implements all core FHIR RESTful API operations
- ✅ Supports comprehensive search functionality
- ✅ Provides secure, scalable healthcare data management
- ✅ Works across platforms (server, mobile, desktop)
- ✅ Maintains FHIR specification compliance
- ✅ Offers excellent developer experience

## Architecture

### Package Structure

```
fhirant/
├── fhirant_server/      # HTTP server implementation (Shelf-based)
├── fhirant_db/          # Database layer (Drift/SQLite with search indexing)
├── fhirant_logging/     # Logging utilities
└── fhirant_secure_storage/  # Secure storage for credentials/certificates
```

### Technology Stack

- **Language**: Dart 3.5+
- **Server Framework**: Shelf + Shelf Router
- **Database**: Drift (SQLite) with SQLCipher encryption
- **FHIR Library**: fhir_r4 (custom FHIR R4 implementation)
- **Platform**: Cross-platform (server, iOS, Android, desktop)

## Core Goals

### 1. Complete FHIR RESTful API Implementation

Implement all standard FHIR RESTful operations:

- ✅ **CRUD Operations**
  - ✅ Create (POST /{resourceType})
  - ✅ Read (GET /{resourceType}/{id})
  - ✅ Update (PUT /{resourceType}/{id})
  - ✅ Delete (DELETE /{resourceType}/{id}) - **Recently implemented**
  - ✅ Patch (PATCH /{resourceType}/{id})
  - ✅ Version Read (GET /{resourceType}/{id}/_history/{vid})

- ✅ **Search Operations**
  - ✅ Search (GET /{resourceType}?parameters)
  - ✅ Search parameter parsing and execution
  - ✅ Pagination (_count, _offset)
  - ⏭️ Sorting (_sort) - In progress
  - ⏭️ Includes (_include, _revinclude) - Planned

- ✅ **History Operations**
  - ✅ Resource history
  - ✅ Type history
  - ✅ System history

- ✅ **Bundle Operations**
  - ✅ Transaction bundles
  - ✅ Batch bundles

- ⏭️ **FHIR Operations**
  - ✅ $validate - Basic validation
  - ⏭️ $everything - Planned
  - ⏭️ $document, $expand, $lookup, etc. - Planned

### 2. Comprehensive Search Functionality

Implement all FHIR search parameter types:

- ✅ **Basic Search Types**
  - ✅ String search
  - ✅ Token search
  - ✅ Date search
  - ✅ Number search
  - ✅ Quantity search
  - ✅ URI search

- ✅ **Special Search Parameters**
  - ✅ _id
  - ✅ _lastUpdated - **Recently implemented**
  - ⏭️ _tag - Planned
  - ⏭️ _profile - Planned
  - ⏭️ _security - Planned
  - ⏭️ _source - Planned
  - ⏭️ _has - Planned (reverse chaining)

- ⏭️ **Advanced Search**
  - ⏭️ Reference search with chaining
  - ⏭️ Composite search
  - ⏭️ OR logic (comma-separated values)
  - ⏭️ FHIRPath filtering (_filter)

### 3. FHIR Compliance

- ✅ **CapabilityStatement** - Enhanced with search parameters
- ✅ **OperationOutcome** - Proper error responses
- ✅ **HTTP Standards** - Correct status codes, headers
- ⏭️ **Content Negotiation** - JSON/XML support
- ⏭️ **ETag/Last-Modified** - Version-aware updates
- ⏭️ **Conditional Operations** - If-Match, If-None-Exist

### 4. Security & Standards

- ⏭️ **Authentication** - OAuth2, SMART on FHIR
- ⏭️ **Authorization** - Scope-based access control
- ✅ **Secure Storage** - Encrypted database
- ⏭️ **CORS** - Cross-origin support
- ⏭️ **Audit Logging** - Operation tracking

### 5. Developer Experience

- ✅ **Type Safety** - Full Dart type system
- ✅ **Comprehensive Tests** - Unit and integration tests
- ✅ **Clear Documentation** - Implementation plans, guides
- ⏭️ **Docker Support** - Easy deployment
- ⏭️ **Configuration System** - Environment-based config

## Current Implementation Status

### ✅ Completed (Phase 1)

1. **Core REST API**
   - ✅ All CRUD operations (Create, Read, Update, Delete, Patch)
   - ✅ Resource history endpoints
   - ✅ Bundle transaction/batch support
   - ✅ Basic $validate operation

2. **Search Infrastructure**
   - ✅ Search parameter tables (string, token, date, number, quantity, uri, reference, composite, special)
   - ✅ Search parameter indexing on resource save
   - ✅ Search method implementation
   - ✅ Search parameter parser
   - ✅ Handler integration

3. **Special Search Parameters**
   - ✅ _id search
   - ✅ _lastUpdated search (with all date modifiers)
   - ✅ _tag search
   - ✅ _profile search
   - ✅ _security search
   - ✅ _source search

4. **Advanced Search Features**
   - ✅ Reference search with chaining
   - ✅ Composite search
   - ✅ Sorting (_sort)
   - ✅ Include/RevInclude support

4. **Metadata**
   - ✅ Enhanced CapabilityStatement
   - ✅ Search parameters listed
   - ✅ Operations documented

5. **Testing**
   - ✅ Test infrastructure set up
   - ✅ 13/16 tests passing (81%)
   - ✅ Search parser: 7/7 tests (100%)
   - ✅ DELETE handler: 5/5 tests (100%)
   - ⚠️ GET handler: 6/9 tests passing (edge cases need work)

### ✅ Recently Completed (Phase 2)

1. **Search Enhancements** ✅
   - ✅ _tag search
   - ✅ _profile search
   - ✅ _security search
   - ✅ _source search
   - ✅ Sorting (_sort)
   - ✅ Reference search with chaining
   - ✅ Composite search

2. **Bundle Features** ✅
   - ⚠️ Accurate total count (partially - uses resources.length, TODO for separate count query)
   - ✅ Pagination links (first, previous, next, last)
   - ✅ Include/RevInclude support

### ⏭️ Next Up (Phase 3+)

3. **HTTP Standards**
   - ⏭️ ETag support
   - ⏭️ Last-Modified header
   - ⏭️ Conditional operations
   - ⏭️ Content negotiation

### 🔮 Future (Phase 3+)

1. **Advanced Operations**
   - $everything
   - $document
   - $expand, $lookup, $translate
   - $closure, $subsumes

2. **Subscriptions**
   - Subscription resource support
   - REST-hook notifications
   - WebSocket notifications

3. **Compartments**
   - Compartment-based access control
   - Compartment queries

4. **Security**
   - OAuth2 authentication
   - SMART on FHIR
   - JWT validation
   - Scope-based authorization

5. **Deployment**
   - Docker support
   - Configuration system
   - Production optimizations

## Use Cases

### 1. Standalone FHIR Server
Deploy as a standalone server for:
- Healthcare data management
- FHIR API endpoints
- Integration with other systems
- Testing and development

### 2. Embedded in Flutter Apps
Use as a library in Flutter applications:
- Mobile health apps
- Clinical decision support
- Patient portals
- Research applications

### 3. Development & Testing
- FHIR conformance testing
- Integration testing
- Prototype development
- Educational purposes

## Design Principles

### 1. Standards Compliance
- Follow FHIR R4 specification strictly
- Implement all required operations
- Support standard search parameters
- Use proper HTTP status codes and headers

### 2. Performance
- Efficient database queries
- Indexed search parameters
- Pagination for large result sets
- Optimized resource storage

### 3. Security
- Encrypted database storage
- Secure credential management
- Audit logging
- Authentication/authorization support

### 4. Developer Experience
- Type-safe APIs
- Comprehensive documentation
- Clear error messages
- Easy deployment

### 5. Extensibility
- Modular architecture
- Plugin-friendly design
- Custom search parameters
- Operation extensions

## Technical Highlights

### Database Layer
- **Drift ORM** - Type-safe database access
- **SQLCipher** - Encrypted storage
- **Search Indexing** - Automatic search parameter extraction
- **History Tracking** - Full version history
- **Cross-platform** - Works on all platforms

### Server Layer
- **Shelf Framework** - Lightweight, composable HTTP server
- **Router** - Clean URL routing
- **Middleware** - Rate limiting, logging, CORS
- **Error Handling** - Proper OperationOutcome responses

### Search Implementation
- **Parameter Tables** - Separate tables for each search type
- **Automatic Indexing** - Search parameters extracted on save
- **Efficient Queries** - Optimized database queries
- **Modifier Support** - All FHIR search modifiers

## Project Status Summary

### Overall Progress: ~60% Complete (Core FHIR Functionality)

**Phase 1 (Core REST API)**: ✅ **~95% Complete**
- All CRUD operations ✅
- Search infrastructure ✅
- Full search implementation ✅
- History ✅
- Bundles ✅
- Enhanced CapabilityStatement ✅

**Phase 2 (Search Enhancements)**: ✅ **~90% Complete**
- Special parameters: 5/6 done (_id, _lastUpdated, _tag, _profile, _security, _source)
- Sorting: ✅ Complete
- Reference chaining: ✅ Complete
- Composite search: ✅ Complete
- Include/RevInclude: ✅ Complete
- Bundle pagination links: ✅ Complete

**Phase 3 (Advanced Features)**: ⏭️ **~10% Complete**
- Operations: 1/8 done ($validate)
- Subscriptions: Not started
- Compartments: Not started
- Response shaping: Not started

**Phase 4 (Production Ready)**: ⏭️ **~15% Complete**
- Security: Basic structure
- Deployment: Not started
- Configuration: Not started
- ETag/Last-Modified: Not started
- Conditional operations: Not started

## Why This Project?

### The Problem
- Many FHIR servers are complex, heavyweight, or language-specific
- Need for a modern, cross-platform FHIR server
- Flutter/Dart ecosystem needs FHIR server capabilities
- Educational and development use cases

### The Solution
- **Lightweight** - Simple, focused implementation
- **Cross-platform** - Works everywhere Dart/Flutter works
- **Standards-compliant** - Follows FHIR R4 specification
- **Developer-friendly** - Type-safe, well-documented
- **Extensible** - Easy to add custom features

## Target Users

1. **Healthcare Developers** - Building FHIR-compliant applications
2. **Researchers** - Managing healthcare data for research
3. **Educators** - Teaching FHIR concepts
4. **Organizations** - Needing a lightweight FHIR server
5. **Flutter Developers** - Building health apps with embedded FHIR

## Success Criteria

A successful FHIRant server should:

1. ✅ **Pass FHIR Conformance Tests** - Validate against official test suites
2. ✅ **Support All Core Operations** - CRUD, search, history, bundles
3. ✅ **Handle Real-World Workloads** - Performance under load
4. ✅ **Be Production-Ready** - Security, monitoring, deployment
5. ✅ **Have Comprehensive Documentation** - Easy to use and extend

## Getting Started

### For Developers
1. Review `IMPLEMENTATION_PLAN.md` for development roadmap
2. Check `MISSING_FEATURES.md` for what's still needed
3. Read `TESTING_BEST_PRACTICES.md` for testing approach
4. See `NEXT_STEPS.md` for immediate priorities

### For Users
1. Check `packages/fhirant_server/README.md` for server setup
2. Review API documentation (when available)
3. See examples in test files

## Contributing

The project follows these principles:
- **Test-Driven Development** - Write tests as you go
- **Incremental Progress** - Complete features fully before moving on
- **Documentation** - Document decisions and implementations
- **Standards Compliance** - Follow FHIR specification strictly

## Roadmap

### Short Term (This Month)
- ✅ Complete Phase 1 (Core REST API)
- ⏭️ Implement special search parameters (_tag, _profile)
- ⏭️ Add sorting support
- ⏭️ Fix remaining test issues

### Medium Term (Next 2-3 Months)
- Complete Phase 2 (Search Enhancements)
- Implement reference chaining
- Add Include/RevInclude support
- Enhance error handling

### Long Term (3-6 Months)
- Complete Phase 3 (Advanced Features)
- Add security (OAuth2, SMART)
- Production deployment features
- Performance optimizations

## Conclusion

FHIRant is building a **complete, standards-compliant FHIR R4 server** that can serve as:
- A standalone healthcare data server
- An embedded component in Flutter apps
- A development and testing tool
- An educational resource

The project is making steady progress, with core functionality in place and a clear path forward for completing all FHIR requirements.

**Current Focus**: Completing search functionality and special parameters to unlock the full power of FHIR search capabilities.

