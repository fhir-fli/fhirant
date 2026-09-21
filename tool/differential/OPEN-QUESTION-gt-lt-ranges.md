# ONE QUESTION OPEN — for HL7 (Zulip #fhir/implementers)

Asked as confirmation, not as a blocker: reading A is implemented as of
2026-09-21, because two reference servers answer that way.

Paste the block below. It names no file of ours and needs no context from
this repository.

---

R4B search.html 3.1.1.4.5 gives, for the ordered parameter types, verbatim:

> **gt** — the value for the parameter in the resource is greater than the
> provided value — the range above the search value intersects (i.e.
> overlaps) with the range of the target value

A search value of `70` has the implicit range [69.5, 70.5). A stored value
of exactly `70` has the same range.

Does `value-quantity=gt70` match a stored `70`?

**Reading A — "the range above the search value" is (70.5, ∞)**, the interval
above the search value's whole range. It does not overlap [69.5, 70.5), so a
stored 70 does not match. `ge` then adds something: its second clause ("or
the range of the search value fully contains the range of the target value")
is what admits the stored 70.

**Reading B — "the range above the search value" is (70, ∞)**, the interval
above the point. It overlaps [69.5, 70.5) at (70, 70.5), so a stored 70
matches. `ge`'s containment clause then adds nothing for this row, since
`gt` already matched it.

The same question applies to `lt` and the lower bound.

What we have found:

- HAPI FHIR 8.13.9 answers reading A: `gt70` excludes a stored 70, `ge70`
  includes it. Measured over the same 50 resources loaded into both servers.
- Firely Server 6.9.1 (`server.fire.ly`) answers reading A too. Read-only
  probes against its own data, three Observations with `_id` pinned so only
  that resource could match, at 120 mm[Hg], 16 /min and 98 %: `gt` and `lt`
  at the stored value returned nothing, `ge` and `le` returned the resource.
- `test.fhir.org` did not respond, so Grahame Grieve's reference server is
  unchecked.
- The same sentence covers `date`, and for dates every boundary case we ran
  against HAPI agreed on reading A.
- Microsoft's server widens by half a unit of the last decimal place, which
  is neither reading exactly.

Suites after implementing reading A: fhir_db 37, the R4 binding 484, R5 481,
R6 479, and the server on top of it 1,298.

Which reading is intended for number and quantity? If it is A, is the
difference between `gt` and `ge` at a value equal to the search value the
intended distinction?
