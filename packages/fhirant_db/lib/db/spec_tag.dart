/// The `meta.tag` every resource of the specification load carries, so the
/// store can tell a deployment's own data from the 4,212 conformance
/// resources that ship with the server. A system-level `$export` with no
/// `_type` and `$backup` leave tagged resources out; REST, a resource's own
/// `_history` and the dashboard see them as any resource (REVIEW-2026-09-06
/// §6.1, decided 2026-09-08: the specification stays in `resources`).
///
/// The tag is the server's (REVIEW-2026-09-17 S3): `FhirAntDb` declares it
/// in `FhirDao.serverOwnedTags`, so a client save neither adds it nor keeps
/// it, and only a save made `asServer`, the specification load, writes it.
/// It is declared here, with the store, so that every `FhirAntDb` has the
/// rule however it was opened.
const specTagSystem = 'http://fhirant.fhir-fli.dev/CodeSystem/tags';

/// The code of the specification tag.
const specTagCode = 'spec';
