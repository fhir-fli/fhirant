# Test fixtures

Published artefacts, copied here **verbatim**, so tests assert against what the
publisher shipped rather than against something I wrote to match my own code.

| file | source | why it is here |
|---|---|---|
| `StructureDefinition-us-core-patient.json` | `hl7.fhir.us.core#3.1.0`, HL7 US Core (CC0) | `$transform` resolves a profiled target through `StructureDefinition.type`. This profile's `type` is `Patient`, which is the case a last-path-segment reading gets wrong. It lived in `~/.fhir/packages` and the test **skipped on CI**, so the change it covers was unverified there. |

Do not trim these to "just the part the test needs". A trimmed fixture is my
construction, and then the test only proves the code agrees with me.
