# Where server B's extra 5.5 GB went (2026-11-21)

After the full-store $sync (tool/sync_cost_2026-11-20, run h), B's store was
11.89 GB and A's 6.37 GB with the same 928,935 resources.

Measured with `table_sizes.dart` and `audit_index_rows.dart` on both stores
(outputs `results_a.txt`, `results_b.txt`, `results_b_index_rows.txt`):

- B holds 939,083 AuditEvents: one per copied resource (BALP-style, one per
  Bundle entry) plus the requests themselves. A holds 4,251, because A was
  loaded with `perf_load.dart --server-store`, which writes the store
  directly and is not audited. So the comparison was between an audited and
  an unaudited load, not a cost of $sync: any server that took these
  resources through its API would carry the same records.
- The AuditEvents' JSON is 823 MB (about 880 bytes each). The rest is their
  search-index rows, about 10 per event: token type, subtype, outcome,
  action (939,083 each), entity-type and entity-role (927,009 each);
  reference entity (1,856,144) and patient (927,309); date (939,083).
  Each row is an R4B AuditEvent search parameter.
- `sync_pairs` adds 167 MB (table and its index).

Can an event carry several written resources? No. IHE BALP
(profiles.ihe.net/ITI/BALP, StructureDefinition JSON read 2026-11-21):
in IHE.BasicAudit.Create and .Update, `AuditEvent.entity:data` is 1..1;
PatientCreate and PatientUpdate keep that and add `entity:patient` 1..1.
One event per written resource is what the profile requires.

Found while reading: BALP Create and Update fix `AuditEvent.type` to
`http://terminology.hl7.org/CodeSystem/audit-event-type#rest` and the
subtype to the restful-interaction code. fhirant writes DCM 110112 "Query"
on every event (already listed, unfixed, in REVIEW-2026-09-17-TRIAGE.md).

The stores were deleted after these measurements.

`audit_index_rows.dart` was reformatted for the analyzer after its run (how
the totals line is built; same query). The stores were gone by then, so it
was not rerun.
