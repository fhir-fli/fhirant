/// The `id` datatype. R4B datatypes.html `id`, verbatim (read 2026-09-18):
/// "Any combination of upper- or lower-case ASCII letters ('A'..'Z', and
/// 'a'..'z', numerals ('0'..'9'), '-' and '.', with a length limit of 64
/// characters." and "Regex: [A-Za-z0-9\-\.]{1,64}".
///
/// Checked where a client supplies an id: the id segment of a Bundle entry
/// URL (REVIEW-2026-09-17 Q7) and `PUT /[type]/[id]` (C5: `PUT
/// /Patient/a$b_c` was a 201, and the id then reached every URL the server
/// builds from it).
final RegExp fhirIdGrammar = RegExp(r'^[A-Za-z0-9\-\.]{1,64}$');

/// Whether [id] is an `id` by the grammar above.
bool isFhirId(String id) => fhirIdGrammar.hasMatch(id);
