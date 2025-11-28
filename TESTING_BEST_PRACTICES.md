# Testing Best Practices for FHIRant Server

## Standard Best Practices

### 1. **Red-Green-Refactor Cycle (TDD)**
**Principle**: Never leave failing tests in the codebase.

**Current Situation**: We have 3 failing tests due to mock setup issues (not logic errors).

**Best Practice**: 
- ✅ **Fix failing tests before moving on** - This is the standard TDD approach
- ✅ **All tests should be green before committing** - This ensures the codebase is always in a working state
- ⚠️ **Exception**: If tests are failing due to external dependencies or infrastructure issues, document them and create a ticket

**Recommendation**: Fix the 3 failing mock tests now (should take 10-15 minutes).

### 2. **Test Coverage Strategy**

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

**Best Practice**: 
- Write unit tests for pure functions and utilities (✅ Done)
- Write unit tests with mocks for handlers (✅ Done, needs fixes)
- Write integration tests for end-to-end flows (⏭️ Later)

### 3. **When to Write Tests**

**Three Common Approaches**:

#### A. **Test-Driven Development (TDD)** - Strict
1. Write failing test
2. Write minimal code to pass
3. Refactor
4. Repeat

**Pros**: Ensures 100% test coverage, tests drive design
**Cons**: Slower initial development, can feel restrictive

#### B. **Test-After Development** - Pragmatic
1. Write feature
2. Write tests immediately after
3. Fix any issues found

**Pros**: Faster initial development, still good coverage
**Cons**: Might miss edge cases, tests might be biased toward implementation

#### C. **Test-Later** - Not Recommended
1. Write all features
2. Write all tests at the end

**Pros**: Fastest initial development
**Cons**: Hard to test, low coverage, bugs found late

**Our Approach**: **Test-After (B)** - Write tests immediately after each feature ✅

### 4. **Test Quality Standards**

**What Makes a Good Test**:
- ✅ **Fast** - Unit tests should run in milliseconds
- ✅ **Isolated** - Tests shouldn't depend on each other
- ✅ **Repeatable** - Same results every time
- ✅ **Self-validating** - Pass/fail is clear
- ✅ **Timely** - Written close to the code

**What We Have**:
- ✅ Fast (unit tests with mocks)
- ✅ Isolated (each test is independent)
- ✅ Repeatable (no external dependencies)
- ✅ Self-validating (clear assertions)
- ✅ Timely (written right after implementation)

### 5. **Handling Failing Tests**

**Standard Practice**: **Fix immediately or skip with documentation**

**Options**:

#### Option A: Fix Now (Recommended)
```dart
// Fix the mock setup issues
// Takes 10-15 minutes
// Ensures green test suite
```

**Pros**: 
- Clean codebase
- Confidence in code
- No technical debt

**Cons**: 
- Slight delay in feature work

#### Option B: Skip with TODO
```dart
test('uses search when search parameters are provided', () async {
  // TODO: Fix mocktail matcher for named parameters
  // Issue: mocktail.any() doesn't work with named parameters
  // Expected fix: Use argThat or custom matcher
}, skip: 'Mock setup needs fixing');
```

**Pros**: 
- Documents the issue
- Allows moving forward
- Tests still exist

**Cons**: 
- Technical debt
- Easy to forget
- Reduces confidence

#### Option C: Comment Out (Not Recommended)
```dart
// test('uses search...', () { ... });
```

**Pros**: None

**Cons**: 
- Tests get lost
- No documentation
- Bad practice

**Recommendation**: **Option A - Fix Now** (15 minutes max)

### 6. **Test Organization**

**Standard Structure**:
```
test/
  unit/           # Fast, isolated tests
    utils/
    handlers/
  integration/    # Slower, real dependencies
    api/
    database/
  fixtures/       # Test data
    patients.json
    observations.json
```

**Current Structure**:
```
test/
  utils/          ✅ Good
  handlers/       ✅ Good
  (integration/)  ⏭️ Add later
  (fixtures/)     ⏭️ Add later
```

### 7. **Mocking Best Practices**

**When to Mock**:
- ✅ External dependencies (database, HTTP clients)
- ✅ Slow operations
- ✅ Unpredictable behavior (time, random)
- ❌ Pure functions (no need to mock)
- ❌ Simple data structures

**What We're Mocking**:
- ✅ `FuegoDbInterface` - External dependency, correct
- ✅ `Request` - External dependency, correct

**Mock Issues**:
- ⚠️ `mocktail` named parameter matching needs adjustment
- ⚠️ Need to use `argThat` or custom matchers

### 8. **Continuous Integration**

**Standard Practice**: 
- All tests must pass before merge
- Run tests on every commit
- Fail the build if tests fail

**Current Status**: 
- ⚠️ No CI/CD set up yet
- ⚠️ Tests should be green before setting up CI

### 9. **Test Maintenance**

**Best Practices**:
- ✅ Keep tests simple and readable
- ✅ One assertion per test (when possible)
- ✅ Descriptive test names
- ✅ Group related tests
- ✅ Clean up test data

**Our Tests**:
- ✅ Simple and readable
- ✅ Good test names
- ✅ Well grouped
- ✅ No cleanup needed (mocks)

## Recommended Action Plan

### Immediate (Now - 15 minutes)
1. **Fix the 3 failing mock tests**
   - Adjust mocktail matchers for named parameters
   - Use `argThat` or proper matcher syntax
   - Ensure all tests pass

### Short Term (This Week)
2. **Add missing test scenarios**
   - Edge cases for DELETE (already have most)
   - Edge cases for search
   - Error handling paths

3. **Set up test coverage tracking**
   - Add coverage reporting
   - Set minimum coverage threshold (e.g., 80%)

### Medium Term (Next Sprint)
4. **Add integration tests**
   - Test with real database
   - Test full HTTP requests
   - Test error scenarios

5. **Set up CI/CD**
   - Run tests on every PR
   - Enforce test passing before merge

## Industry Standards

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
- ⚠️ Need to fix failing tests (in progress)
- ⏭️ Coverage tracking (to be added)

## Conclusion

**Standard Best Practice**: **Fix failing tests before moving on**

**Why**:
1. Maintains code quality
2. Prevents technical debt
3. Ensures confidence in codebase
4. Makes CI/CD setup easier
5. Follows TDD/red-green-refactor principles

**Time Investment**: 15 minutes to fix mocks vs. hours of debugging later

**Recommendation**: **Fix the 3 failing tests now**, then continue with feature development.

