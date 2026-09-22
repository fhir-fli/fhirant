# Repeated code across the family, 2026-09-22

`census.py` counts five-line blocks (whitespace-normalised, comments and
blanks dropped, at least 80 characters) that appear three or more times in
a package's `lib/`. Generated code and data tables are skipped; the skip
list was built by reading the top repeated block of every package. Full
table: `census_2026-09-22.tsv`.

| Package | Repeated blocks | Sites | What the top blocks are |
|---|---|---|---|
| cql | 517 | 8,970 | `super.annotation, super.localId, …` constructor lists on ELM node classes (249 copies); the `before`/`after` operator files. Structural, not a helper missing |
| fhirant_server | 150 | 594 | 55 hand-built error replies, 7 copies of the resource-type check. **A helper is missing** |
| fhirpath | 98 | 467 | parameter lists an interface requires (`ExecutionContext execContext, List<FhirNode> left, …`) |
| orbweaver | 96 | 303 | `flowchart_view.dart` alone holds 96 sites; five painters share `paint()` openings. Some helper missing |
| fhir_r4/r5/r6_mapping | 45–54 | 152–188 | exception classes and Builder `typeByElementName` overrides; structural |
| fhir_r4/r5/r6 core | 19–34 | 80–177 | summary helpers; small |
| fhir_db | 29 | 135 | nine index functions with one parameter list; structural |
| everything else | ≤22 | ≤144 | |

Skipped as generated or data, each checked by reading its top block:
cicada `generated_files/` (CDC data), `fhir_field_map.dart`, at_rest
`searches/search_*.dart` (header: auto-generated), db search tables, cql
`model_info/` and `antlr/`, ucum `defined_units.dart`.

Not distinguished by the census: a repeated parameter list (harmless) from
a repeated decision (a defect). That needs reading each block.
