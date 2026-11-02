# Validation measured, 2026-11-01

Question (Grey): do our own apps' writes need validating at runtime? Plan:
validate bumblebee's Idai corpus (1,000 visits, 3,721 resources) against
base types and claimed profiles; 0 errors would mean validate in tests only.

**Answer: not measurable yet. The validator gives wrong answers on HL7's own
published examples, so no count it produces means anything.**

Script: `measure_corpus.dart`. Raw outputs in the dated folders here.

## Runs

| Folder | Corpus | Cache | Rows | Result |
|---|---|---|---|---|
| `idai-2026-11-01/` | Idai, first 143 resources | DbResourceCache, type-code fix in | 171 validations in 23 min (stopped) | 60 threw, 95 with errors, 16 clean; the errors are the engine's, see below |
| `hl7-examples-2026-11-01/` | 138 HL7 R4B examples of the 7 Idai types | DbResourceCache | 13 (590 s timeout) | 12 with errors, 1 threw; 16.5–48.9 s each |
| `hl7-examples-memory-2026-11-01/` | same, first 13 | CanonicalResourceCache, same resources | 13 | 12 with errors, 1 threw; median 9 ms, max 121 ms |

In the Idai run the 16 clean validations are the 16 Patients, which carry
only primitive elements. All 16 Encounters and all 16 ServiceRequests threw,
and so did all 28 validations against a bumblebee profile
(child-protection-status 15, rehabilitation-need 13).

The examples come from `fhir_generator/fhir_r4/examples-json` (every
Patient, Encounter, Condition, Observation, RelatedPerson, ServiceRequest
and Procedure there without a `meta.profile`: 52, 23, 20, 16, 12, 10, 5).

## Findings

1. **Fixed here: DbResourceCache could not resolve a data type.** The engine
   asks for a complex element's type by its type code (`HumanName`).
   ElementDefinition.type.code (packaged profiles-types.ndjson, 4.3.0):
   "References are URLs that are relative to
   http://hl7.org/fhir/StructureDefinition". The cache searched for a url
   of `HumanName`. Every complex element of every resource sent to
   `$validate` was reported "No StructureDefinition or Profile found".
   Test: `validate_profile_test.dart`, "a data type is resolved from its
   type code" (seen failing first). CanonicalResourceCache has the same
   gap: 128 of its 192 error issues on the examples are this message.
2. **DbResourceCache is ~2,000× slower than the in-memory cache** on the
   same resources (16.5 s vs 9 ms median for a Condition). Not diagnosed.
3. **The engine (fhir_validation 0.13.0) reports false errors on valid
   resources with either cache:** "Context is null for <invariant>" (52),
   "Unable to determine context type" (16), "Element type or path is
   missing for node" (12), and codes rejected against **example**
   bindings: Condition.code and Condition.bodySite are `example`
   (packaged profiles-resources.ndjson), and CodeSystem binding-strength
   (valuesets.ndjson, 4.3.0, verbatim) defines `example` as "Instances are
   not expected or even encouraged to draw from the specified value set."
4. **The engine throws on Encounter** (`Primitive element is not a
   Primitive or a List: ObjectNode`, validate_structure.dart:479) on both
   Idai `e000` and HL7 `emerg`; and on a ServiceRequest it throws for a
   terminology.hl7.org value set not in the packaged spec.
5. **fhir_r4_validation's integration tests assert nothing about
   validity**: `expect(results, isNotNull)` with the comment "Actual
   errors may vary". No test anywhere checks that a valid resource passes.
6. The engine ignores `meta.profile`; it validates against one
   StructureDefinition, the base type unless one is passed.
