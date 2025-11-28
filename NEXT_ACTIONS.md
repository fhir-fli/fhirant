# Next Actions for FHIRant Server

## Current Status Summary

### ✅ Completed (This Session)
1. **DELETE endpoint** - Fully implemented and tested
2. **Search functionality connection** - Handler uses database search
3. **Search parameter parser** - Complete with 7/7 tests passing
4. **Test infrastructure** - Set up with 13/15 tests passing (87%)
5. **Database search** - Verified implementation exists

### ⚠️ Minor Issues
- 2 tests failing due to mock setup (not logic errors)
- CapabilityStatement needs enhancement

## Recommended Next Steps (Priority Order)

### Option A: Quick Wins (Recommended - 1-2 hours)
**Goal**: Complete Phase 1 and fix remaining issues

1. **Fix 2 failing tests** (15-30 min)
   - Adjust mocktail matchers
   - Get to 100% test passing
   - **Impact**: Clean test suite, confidence in code

2. **Enhance CapabilityStatement** (1-2 hours)
   - Add search parameters for each resource type
   - Enable delete and search-type interactions (already done)
   - Add supported operations list
   - **Impact**: Shows server capabilities, FHIR compliance

**Why this first**: Completes Phase 1, establishes solid foundation

### Option B: Search Enhancements (2-4 hours)
**Goal**: Implement critical search features

1. **Special search parameters** (2-3 hours)
   - `_lastUpdated` - Use meta.lastUpdated
   - `_tag` - Use meta.tag
   - `_profile` - Use meta.profile
   - `_security` - Use meta.security
   - **Impact**: Essential FHIR search features

2. **Sorting (_sort)** (1 hour)
   - Parse sort parameter
   - Implement in database query
   - **Impact**: Users can sort results

**Why this**: These are commonly used FHIR features

### Option C: Continue Feature Development (Ongoing)
**Goal**: Implement remaining missing features

1. **Reference search with chaining** (3-4 hours)
2. **Composite search** (2-3 hours)
3. **Include/RevInclude** (4-6 hours)
4. **Bundle pagination links** (2-3 hours)

## My Recommendation: **Option A** (Quick Wins)

### Immediate Next Steps (Today)

1. **Fix 2 failing tests** (15-30 min)
   ```bash
   # Adjust mocktail matchers in resource_handler_test.dart
   # Use exact values or simpler matchers
   ```

2. **Enhance CapabilityStatement** (1-2 hours)
   - Add search parameters to metadata response
   - This is important for FHIR compliance
   - Shows clients what the server supports

### Why Option A First?

1. **Completes Phase 1** - All core REST API features done
2. **Clean foundation** - 100% tests passing
3. **FHIR compliance** - CapabilityStatement is required
4. **Quick wins** - Visible progress in short time
5. **Sets up for Phase 2** - Clean base for search enhancements

### After Option A (This Week)

Then move to **Option B** - Special search parameters:
- `_lastUpdated` is very commonly used
- `_tag` and `_profile` are important for filtering
- These unlock more FHIR functionality

## Alternative: Fix Tests + Start Search Features

If you want to move faster on features:

1. **Fix 2 tests** (15-30 min) - Quick cleanup
2. **Start `_lastUpdated` search** (1 hour) - High value feature
3. **Implement sorting** (1 hour) - Frequently requested

This gives you:
- Clean test suite
- Two new search features
- Good progress on Phase 2

## Decision Matrix

| Option | Time | Impact | Completeness |
|--------|------|--------|--------------|
| **A: Quick Wins** | 1-2h | High | Completes Phase 1 |
| **B: Search Features** | 2-4h | High | Phase 2 progress |
| **C: Full Features** | 6-10h | Very High | Major progress |

## My Strong Recommendation

**Start with Option A**:
1. Fix the 2 tests (15 min) - Clean up
2. Enhance CapabilityStatement (1-2 hours) - FHIR compliance
3. Then move to Option B - Special search parameters

This gives you:
- ✅ Complete Phase 1
- ✅ 100% tests passing
- ✅ FHIR-compliant metadata
- ✅ Ready for Phase 2

**What would you like to tackle next?**

