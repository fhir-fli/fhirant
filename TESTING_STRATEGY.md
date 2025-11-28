# Testing Strategy for FHIRant Packages

## Overview

We have 4 packages that need testing consideration:
1. **fhirant_server** - Main server package ✅ (tests started)
2. **fhirant_db** - Database layer (critical, complex)
3. **fhirant_logging** - Logging utility (simple, low risk)
4. **fhirant_secure_storage** - Secure storage wrapper (medium complexity)

## Testing Best Practices by Package Type

### 1. **Core Business Logic** (High Priority)
**Packages**: `fhirant_server`, `fhirant_db`

**Why**: These contain the core functionality and business logic.

**Test Strategy**:
- ✅ **Unit tests** for all public APIs
- ✅ **Integration tests** for database operations
- ✅ **Edge case testing** for error conditions
- ✅ **Performance tests** for critical paths

**Current Status**:
- `fhirant_server`: ✅ Tests started (need to fix 3 failing)
- `fhirant_db`: ❌ No tests yet (HIGH PRIORITY)

### 2. **Infrastructure/Utilities** (Medium Priority)
**Packages**: `fhirant_secure_storage`

**Why**: Wraps external dependencies, needs to work correctly.

**Test Strategy**:
- ✅ **Unit tests** for wrapper logic
- ✅ **Mock external dependencies** (flutter_secure_storage)
- ⚠️ **Integration tests** (optional, can be slow)

**Current Status**:
- `fhirant_secure_storage`: ❌ No tests yet (MEDIUM PRIORITY)

### 3. **Simple Utilities** (Low Priority)
**Packages**: `fhirant_logging`

**Why**: Simple wrapper, low risk of bugs.

**Test Strategy**:
- ✅ **Basic unit tests** to ensure it works
- ⚠️ **Can defer** if time-constrained

**Current Status**:
- `fhirant_logging`: ❌ No tests yet (LOW PRIORITY)

## Recommended Testing Priority

### Phase 1: Critical Path (Now)
1. ✅ **fhirant_server** - Fix 3 failing tests (15 min)
2. 🔴 **fhirant_db** - Add tests for core database operations (HIGH PRIORITY)
   - CRUD operations
   - Search functionality
   - Search parameter indexing
   - Error handling

**Why fhirant_db is critical**:
- It's the foundation of the server
- Complex logic (search parameters, indexing)
- Bugs here affect everything
- Already has test dependencies set up

### Phase 2: Infrastructure (Next)
3. 🟡 **fhirant_secure_storage** - Add tests (MEDIUM PRIORITY)
   - Encryption/decryption
   - Storage operations
   - Error handling

### Phase 3: Utilities (Later)
4. 🟢 **fhirant_logging** - Add basic tests (LOW PRIORITY)
   - Logging functionality
   - Log levels
   - Simple smoke tests

## Test Coverage Strategy

### What to Test in Each Package

#### fhirant_db (Critical)
```dart
✅ CRUD operations
  - saveResource()
  - getResource()
  - deleteResource()
  - getResourcesWithPagination()

✅ Search functionality
  - search() with various parameters
  - Search parameter indexing
  - Special search parameters (_lastUpdated, etc.)

✅ Search parameter tables
  - String search parameters
  - Token search parameters
  - Reference search parameters
  - Date search parameters
  - etc.

✅ Error handling
  - Invalid resource types
  - Database errors
  - Missing resources

✅ Edge cases
  - Empty results
  - Large datasets
  - Concurrent operations
```

#### fhirant_secure_storage (Medium)
```dart
✅ Storage operations
  - Write/read
  - Delete
  - Clear

✅ Security
  - Encryption works
  - Keys are secure
  - Data is encrypted at rest

✅ Error handling
  - Storage failures
  - Invalid keys
  - Platform-specific issues
```

#### fhirant_logging (Low)
```dart
✅ Basic functionality
  - Log levels (info, warning, error)
  - Log messages are formatted correctly
  - Logs are actually written

✅ Simple smoke tests
  - Can log without errors
  - Different log levels work
```

## Test Organization

### Recommended Structure

```
fhirant_db/
  test/
    unit/
      fhirant_db_test.dart          # Core CRUD tests
      search_test.dart              # Search functionality
      search_parameters_test.dart   # Search param indexing
    integration/
      database_test.dart             # Real database tests
    fixtures/
      test_resources/                # Test FHIR resources

fhirant_secure_storage/
  test/
    unit/
      secure_storage_test.dart       # Storage operations
      encryption_test.dart           # Encryption tests

fhirant_logging/
  test/
    unit/
      logging_test.dart              # Basic logging tests
```

## Testing Philosophy

### Test at the Right Level

**Don't test implementation details** - Test behavior:
```dart
// ❌ Bad: Testing implementation
test('calls _internalMethod', () { ... });

// ✅ Good: Testing behavior
test('saves resource and returns true', () async {
  final result = await db.saveResource(patient);
  expect(result, isTrue);
  final retrieved = await db.getResource(Patient, '123');
  expect(retrieved, isNotNull);
});
```

### Mock External Dependencies

**In fhirant_server tests**: Mock `fhirant_db` ✅ (already doing this)
**In fhirant_db tests**: Mock `fhirant_secure_storage` if needed
**In fhirant_secure_storage tests**: Mock `flutter_secure_storage`

### Integration Tests

**When to write integration tests**:
- ✅ Critical paths (database operations)
- ✅ Complex interactions between packages
- ⚠️ Can be slower, so use sparingly

**Where**:
- `fhirant_db` - Definitely need integration tests
- `fhirant_server` - Add later for full HTTP flow
- Others - Optional

## Time Estimates

### fhirant_db Tests (Critical)
- **Unit tests**: 4-6 hours
  - CRUD: 1 hour
  - Search: 2-3 hours
  - Search parameters: 1-2 hours
  - Error handling: 30 min
- **Integration tests**: 2-3 hours
- **Total**: 6-9 hours

### fhirant_secure_storage Tests (Medium)
- **Unit tests**: 1-2 hours
- **Total**: 1-2 hours

### fhirant_logging Tests (Low)
- **Unit tests**: 30 minutes
- **Total**: 30 minutes

## Recommendation

### Immediate Action (This Week)
1. ✅ Fix 3 failing tests in `fhirant_server` (15 min)
2. 🔴 **Start `fhirant_db` tests** (highest priority)
   - Begin with CRUD operations
   - Then search functionality
   - This is the foundation everything else depends on

### Next Steps (Next Week)
3. Complete `fhirant_db` tests
4. Add `fhirant_secure_storage` tests

### Later (When Time Permits)
5. Add `fhirant_logging` tests
6. Add integration tests for full server flow

## Key Principle

**Test what matters most**:
- ✅ Core business logic (database, server) - **Test thoroughly**
- ✅ Infrastructure (secure storage) - **Test well**
- ✅ Simple utilities (logging) - **Test basics**

**Don't over-test**:
- ❌ Don't test framework code (Flutter, Dart SDK)
- ❌ Don't test simple getters/setters
- ❌ Don't test third-party libraries

## Conclusion

**Yes, we should write tests for all packages**, but with priorities:

1. **fhirant_db** - **CRITICAL** (do this next)
2. **fhirant_secure_storage** - **IMPORTANT** (do after db)
3. **fhirant_logging** - **NICE TO HAVE** (can defer)

The database package is the most critical because:
- It's complex (search, indexing, CRUD)
- Everything depends on it
- Bugs here are hard to find and expensive
- It already has test dependencies set up

**Recommendation**: Fix the 3 failing server tests, then immediately start on `fhirant_db` tests.

