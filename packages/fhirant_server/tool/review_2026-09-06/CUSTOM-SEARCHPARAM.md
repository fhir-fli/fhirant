# Custom SearchParameters: FHIRPath at write time, measured (2026-09-13)

Question open since 2026-08-27: a privileged user uploads a SearchParameter,
runs `$reindex`, and the new parameter works. Two routes were named: evaluate
the expression with the `fhir_path` engine on every save (runtime), or feed
custom definitions through the generator (build time).

## What the reference servers do

Both evaluate the FHIRPath expression when a resource is stored, and both
need a reindex for data stored before the parameter existed.

Smile CDR / HAPI FHIR, "Custom Search Parameters" (smilecdr.com docs, read
2026-09-13): *"The `SearchParameter.expression` element determines the exact
path within the resource that should be extracted and indexed when a target
resource is being stored."* and *"assuming the new parameter is valid and
active, all resource changes (creates, updates, etc.) will be indexed by the
new search parameter."* and *"new search parameters can cause an issue when
data already exists in the repository because old data won't yet be indexed
by the new search parameter."*

Azure Health Data Services FHIR service, "Create custom search parameters"
(learn.microsoft.com, read 2026-09-13): *"To create a new search parameter,
`POST` a `SearchParameter` resource to the FHIR service database."* and
*"Each time you create, update, or delete a search parameter, you need to run
a reindex job to accept the changes."* and *"The new search parameter appears
in the capability statement of the FHIR service after you `POST` the search
parameter to the database and reindex your database."*

## Measurement

`custom_searchparam_bench.dart`, results in `custom_searchparam_bench.tsv`
(label `mimic2000`), disagreements in `custom_searchparam_bench.tsv.mismatches.tsv`.
Corpus: the first 2,000 lines of each MIMIC ndjson file in `assets/mimic`
(21 resource types, 20,000+ resources). Route A is the generated extractor
(`r4Model.extract`). Route B parses every R4 SearchParameter expression
fragment once (1,724 fragments, 136 bases, 76 ms, 0 parse errors) and
evaluates each on every resource with `FHIRPathEngine`, handing the values to
the same row builders. Rows are compared as parameter name plus value.

Microseconds per resource, in-process, one isolate:

| resource | n | generated extract | FHIRPath extract | whole batched save |
|---|---|---|---|---|
| Observation (chartevents) | 2,000 | 89 | 158 | 278 |
| Observation (labevents) | 2,000 | 73 | 141 | 308 |
| MedicationAdministration | 2,000 | 50 | 296 | 273 |
| Medication | 2,000 | 27 | 38 | 191 |
| Specimen | 1,513 | 8 | 38 | 151 |
| Condition (first file, includes JIT warm-up) | 442 | 475 | 259 | 489 |
| Patient | 10 | 226 | 672 | 584 |

Run-to-run variance is real: across three runs of the same corpus the
FHIRPath column moved by up to 5x on one type (MedicationAdministration 54,
285, 296) while the generated column stayed within 2x. The order of
magnitude, not the ratio on one row, is the finding.

The whole save is `saveResources` in batches of 500 into an in-memory
`FhirAntDb`: extract, index rows, history. A single HTTP save with audit is
milliseconds; the extraction difference is tens of microseconds.

Rows: route B produced no row route A did not (`only_fp` 0 on every type).
Route A produced rows route B did not, all of two kinds:

- `_profile`, `_source`, `_text`: common parameters, excluded from route B
  by construction (they are written on `Resource`/`DomainResource`).
- `patient`, 2,694 rows: every `X.subject.where(resolve() is Patient)`
  expression. The engine's `resolve()` reaches contained resources only
  (no `hostServices` is wired; fhirpath-never-queries-a-store memory), so
  the filter returns nothing. The generated extractor compiles it to a test
  on the reference string. Any runtime route needs a resolver that, given
  `Patient/123`, answers the type from the string, which is what the
  reference servers do at index time.

## What each route costs

Runtime (what HAPI and Azure do): `fhir_db` gains the `fhir_path` engine
(pure Dart, model-independent over `FhirNode`; its dependencies are
`fhir_node`, which `fhir_db` already has, `collection` and `ucum`). Each
binding supplies the engine's version context through the `FhirModel` seam.
A `hostServices` resolver for `resolve()` in `fhir_db`. In fhirant: accept a
posted SearchParameter (today it is stored and nothing reads it), list it in
the CapabilityStatement, `$reindex`. Extraction cost roughly doubles for the
custom parameters only; the built-in set keeps the generated extractor.

Build time: no new dependency, but a parameter exists only after a
regeneration and a redeploy, so a deployment cannot add one. Neither
reference server works this way.

## Recommendation

Runtime, for uploaded SearchParameters, keeping the generated extractor for
the specification's own set (measured 1.4 to 6 times faster, typed, and it
already handles `resolve()`). Whether the generated extractor should later
go entirely is a separate decision, answerable once the resolver exists: on
this corpus the two routes agree on every non-common row.
