# Testing Guide for FHIRant

## Current Test Status

### Test Results Summary
- **Total Tests**: 16
- **Passing**: 13 (81%)
- **Failing**: 3 (edge cases with empty resources/pagination)

### Test Breakdown

#### Search Parameter Parser Tests
- **Status**: ✅ 7/7 passing (100%)
- **Location**: `packages/fhirant_server/test/utils/search_parser_test.dart`
- **Coverage**:
  - Simple search parameter parsing
  - Pagination parameters (`_count`, `_offset`)
  - Sort parameter parsing
  - Comma-separated values (OR logic)
  - Complex queries with all parameter types
  - `hasSearchParameters` helper method

#### Resource Handler Tests
- **Status**: ⚠️ 6/9 passing (67%)
- **Location**: `packages/fhirant_server/test/handlers/resource_handler_test.dart`
- **Passing**:
  - ✅ DELETE: Returns 204 when resource is successfully deleted
  - ✅ DELETE: Returns 404 when resource does not exist
  - ✅ DELETE: Returns 400 when resource type is invalid
  - ✅ DELETE: Returns 500 when database delete fails
  - ✅ DELETE: Returns 500 when database throws exception
  - ✅ GET: Returns 400 for invalid resource type
- **Failing** (edge cases):
  - ⚠️ GET: Uses search when search parameters are provided
  - ⚠️ GET: Handles default count and offset values
  - ⚠️ GET: Uses pagination when no search parameters provided

## Test Infrastructure

### Setup
- **Framework**: `flutter_test` (required because `fhirant_db` depends on Flutter)
- **Mocking**: `mocktail` (better null-safety than `mockito`)
- **Test Structure**:
  ```
  packages/fhirant_server/test/
    handlers/
      resource_handler_test.dart
    utils/
      search_parser_test.dart
  ```

### Running Tests

```bash
# Run all tests
cd packages/fhirant_server
flutter test

# Run specific test file
flutter test test/utils/search_parser_test.dart
flutter test test/handlers/resource_handler_test.dart

# Run with coverage
flutter test --coverage
```

## Testing Strategy by Package

### 1. fhirant_server (High Priority) ✅
**Status**: Tests started, 81% passing

**Test Strategy**:
- ✅ Unit tests for handlers with mocks
- ✅ Unit tests for utilities (search parser)
- ⏭️ Integration tests for full HTTP flow (planned)

**Current Coverage**:
- Search parameter parsing: 100%
- DELETE endpoint: 100%
- GET resources handler: 67% (edge cases need work)

### 2. fhirant_db (Critical) ⏭️
**Status**: Test infrastructure created, needs implementation

**Test Strategy**:
- ⏭️ Unit tests for CRUD operations
- ⏭️ Unit tests for search functionality
- ⏭️ Unit tests for search parameter indexing
- ⏭️ Integration tests with real database

**Priority**: HIGH - This is the foundation of the server

### 3. fhirant_secure_storage (Medium Priority) ⏭️
**Status**: No tests yet

**Test Strategy**:
- ⏭️ Unit tests for storage operations
- ⏭️ Mock external dependencies (flutter_secure_storage)

### 4. fhirant_logging (Low Priority) ⏭️
**Status**: No tests yet

**Test Strategy**:
- ⏭️ Basic unit tests for logging functionality
- ⏭️ Simple smoke tests

## Testing Best Practices

### Test Philosophy
We write tests **as we go** to:
- Catch bugs early
- Document expected behavior
- Enable refactoring with confidence
- Ensure features work before moving to the next one

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
- **In fhirant_server tests**: Mock `fhirant_db` ✅
- **In fhirant_db tests**: Mock `fhirant_secure_storage` if needed
- **In fhirant_secure_storage tests**: Mock `flutter_secure_storage`

### Test Organization
```
fhirant_server/
  test/
    handlers/          # Handler tests with mocks
    utils/             # Utility function tests
    integration/       # Full HTTP flow tests (planned)

fhirant_db/
  test/
    unit/              # Fast, isolated tests
    integration/       # Real database tests
    fixtures/          # Test FHIR resources
```

## Known Issues

### Mock Setup
Some tests have issues with `mocktail` matchers for named parameters. Solutions:
1. Use exact values instead of `any()` where possible ✅ (implemented)
2. Register more fallback values
3. Simplify mocks to be more permissive

### Database Tests
Tests require sqlite3 native library setup. Will work in:
- Integration test environment
- CI/CD with proper setup
- Local environment with sqlite3 installed

## Next Steps

### Immediate
1. Fix 3 failing handler tests (edge cases with empty resources)
2. Add tests for new features:
   - Special search parameters (_tag, _profile, _security, _source)
   - Reference chaining
   - Composite search
   - Include/RevInclude

### Short Term
1. Add `fhirant_db` unit tests (CRUD, search)
2. Add integration tests for database operations
3. Expand edge case coverage

### Medium Term
1. Add `fhirant_secure_storage` tests
2. Add integration tests for full HTTP flow
3. Add performance tests for search

## Test Coverage Goals

- **fhirant_server**: Target 80%+ coverage
- **fhirant_db**: Target 90%+ coverage (critical package)
- **fhirant_secure_storage**: Target 70%+ coverage
- **fhirant_logging**: Target 60%+ coverage (simple package)

## Notes

- Tests use `mocktail` for mocking (better null-safety than `mockito`)
- Must use `flutter_test` because `fhirant_db` has Flutter dependencies
- Import only `fuego_db_interface.dart` in tests to avoid Flutter UI dependencies
- Use `fromJson` for creating test resources to avoid constructor complexity


## Testing Best Practices

### Red-Green-Refactor Cycle (TDD)
**Principle**: Never leave failing tests in the codebase.

**Current Situation**: We have 3 failing tests due to edge cases with empty resources.

**Best Practice**: 
- ✅ **Fix failing tests before moving on** - This is the standard TDD approach
- ✅ **All tests should be green before committing** - This ensures the codebase is always in a working state
- ⚠️ **Exception**: If tests are failing due to external dependencies or infrastructure issues, document them and create a ticket

### Test Coverage Strategy

**Test Pyramid** (from bottom to top):
```
        /\
       /  \  Few Integration Tests
      /____\
     /      \  Some Component Tests  
    /________\
   /          \  Many Unit Tests
  /____________\
```

**Current Status**:
- ✅ Unit tests for utilities (SearchParameterParser) - **Good**
- ✅ Unit tests for handlers (with mocks) - **Good**
- ⚠️ Integration tests - **Missing** (should add later)

### When to Write Tests

**Our Approach**: **Test-After (Pragmatic)** - Write tests immediately after each feature ✅

### Test Quality Standards

**What Makes a Good Test**:
- ✅ **Fast** - Unit tests should run in milliseconds
- ✅ **Isolated** - Tests shouldn't depend on each other
- ✅ **Repeatable** - Same results every time
- ✅ **Self-validating** - Pass/fail is clear
- ✅ **Timely** - Written close to the code

### Handling Failing Tests

**Standard Practice**: **Fix immediately or skip with documentation**

**Options**:
- **Option A: Fix Now** (Recommended) - Fix the edge case issues
- **Option B: Skip with TODO** - Document the issue and create a ticket
- **Option C: Comment Out** (Not Recommended) - Never do this

### Mocking Best Practices

**When to Mock**:
- ✅ External dependencies (database, HTTP clients)
- ✅ Slow operations
- ✅ Unpredictable behavior (time, random)
- ❌ Pure functions (no need to mock)
- ❌ Simple data structures

**What We're Mocking**:
- ✅ `FuegoDbInterface` - External dependency, correct
- ✅ `Request` - External dependency, correct

### Continuous Integration

**Standard Practice**: 
- All tests must pass before merge
- Run tests on every commit
- Fail the build if tests fail

**Current Status**: 
- ⚠️ No CI/CD set up yet
- ⚠️ Tests should be green before setting up CI

### Industry Standards

**Google's Testing Standards**:
- Unit tests: 70-80% of tests
- Integration tests: 20-30% of tests
- All tests must pass before commit

**Microsoft's Testing Standards**:
- Write tests alongside code
- Fix failing tests immediately
- Maintain >80% code coverage

**Our Alignment**:
- ✅ Writing tests alongside code
- ⚠️ Need to fix failing tests (3 edge cases remaining)
- ⏭️ Coverage tracking (to be added)

## Testing Strategy by Package

### Priority Order

1. **fhirant_db** - **CRITICAL** (do this next)
   - Complex logic (search, indexing, CRUD)
   - Everything depends on it
   - Bugs here are hard to find and expensive
   - Already has test dependencies set up

2. **fhirant_secure_storage** - **IMPORTANT** (do after db)
   - Wraps external dependencies
   - Needs to work correctly
   - Medium complexity

3. **fhirant_logging** - **NICE TO HAVE** (can defer)
   - Simple wrapper
   - Low risk of bugs
   - Basic tests sufficient

### Test Coverage Goals

- **fhirant_server**: Target 80%+ coverage
- **fhirant_db**: Target 90%+ coverage (critical package)
- **fhirant_secure_storage**: Target 70%+ coverage
- **fhirant_logging**: Target 60%+ coverage (simple package)
