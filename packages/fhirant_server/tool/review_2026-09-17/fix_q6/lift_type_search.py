#!/usr/bin/env python3
"""Lifts the body of `_searchResources` (resource_handler.dart) into
`typeSearch`, a function with explicit inputs and a Bundle result, so the
Bundle entry search can call the same search as the REST path
(fhirant REVIEW-2026-09-17 Q6). One-shot; kept as the record of the edit.

Every replacement below is a Dart identifier or statement, matched exactly:
case-sensitive on purpose. Each asserts how many times it matched, so a
drift in the source fails loudly instead of editing the wrong thing.
"""
from pathlib import Path

p = Path('lib/src/handlers/resource_handler.dart')
s = p.read_text()
start = s.index('Future<Response> _searchResources(')
end = s.index('/// The most included resources one page carries')
region = s[start:end]


def rep(old, new, count=1):
    global region
    n = region.count(old)
    assert n == count, (old[:70], n, count)
    region = region.replace(old, new)


HEAD_OLD = '''Future<Response> _searchResources(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
  Map<String, List<String>> queryParams,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching resources of type: $resourceType',
    );

    // Parse query parameters into search params and pagination params
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
'''

TAIL_START = '  } on ValueSetRefusal catch (e) {'
tail_at = region.index(TAIL_START)
tail = region[tail_at:]
region = region[:tail_at]

assert region.startswith(HEAD_OLD)
region = region[len(HEAD_OLD):]

WRAPPER = '''Future<Response> _searchResources(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
  Map<String, List<String>> queryParams,
) async {
  final type = fhir.R4ResourceType.fromString(resourceType);
  if (type == null) {
    FhirantLogging().logWarning(
      'Invalid resource type requested: $resourceType',
    );
    return _validationErrorResponse('Invalid resource type');
  }
  // Patient-level scope enforcement: the whole search runs inside the
  // patient's compartment, as the compartment context of R4B search.html
  // 3.1.1.2, one SQL condition in the store. A type the compartment does
  // not include comes back empty from the store. This used to fetch every
  // id in the compartment for the type and pass the list back in as `_id`.
  final patientId = patientContextFor(request, resourceType, 's');
  try {
    final bundle = await typeSearch(
      dbInterface,
      type,
      queryParams,
      requestedUri: request.requestedUri,
      handling: FhirHttpHeaders.parsePreferHandling(request.headers),
      principal: Principal.of(request),
      compartment: patientId == null ? null : patientCompartment(patientId),
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } on SearchRefused catch (e) {
    return _searchRefusal(e.message, e.code);
'''

TYPE_SEARCH_HEAD = '''
/// The type-level search, `GET [base]/[type]?[parameters]`: the searchset
/// Bundle for [queryParams] on [type], with `_has`, `_include`,
/// `_revinclude`, `_summary`, `_elements`, `_filter`, `_total`, the page
/// and its links, or a [SearchRefused] for a query the server will not
/// answer (issue code and message as the REST path has always sent them).
///
/// ONE search. The REST handler wraps the Bundle in a Response and a
/// `SearchRefused` in a 400; a type-level GET entry of a batch or
/// transaction Bundle wraps them in an entry. The entry used to run a second,
/// reduced search that knew `searchParams`, `_count`, `_offset` and `_sort`
/// and nothing else, so `Patient?_has:...` inside a batch answered every
/// patient (fhirant REVIEW-2026-09-17 Q6).
///
/// [requestedUri] is what the links are built from (the REST request's
/// URI; for an entry, the entry's URL under the base). [handling] is the
/// `Prefer: handling=` value in force. Includes are authorised against
/// [principal], and the whole search runs inside [compartment] when the
/// caller's search of the type is confined.
Future<fhir.Bundle> typeSearch(
  FhirAntDb dbInterface,
  fhir.R4ResourceType type,
  Map<String, List<String>> queryParams, {
  required Uri requestedUri,
  required String handling,
  Principal? principal,
  CompartmentScope? compartment,
}) async {
  final resourceType = type.toString();
  FhirantLogging().logInfo('Fetching resources of type: $resourceType');

    // Parse query parameters into search params and pagination params
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
'''

rep('''    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

''', '')

rep("      return _searchRefusal(invalidParams.join('; '), fhir.IssueType.invalid);",
    "      throw SearchRefused(fhir.IssueType.invalid, invalidParams.join('; '));")

rep('''      return _searchRefusal(
        'This server defines no named queries; _query=$namedQuery is not '
        'recognised.',
        fhir.IssueType.notSupported,
      );''', '''      throw SearchRefused(
        fhir.IssueType.notSupported,
        'This server defines no named queries; _query=$namedQuery is not '
        'recognised.',
      );''')

rep('    final handling = FhirHttpHeaders.parsePreferHandling(request.headers);\n', '')

# The eight refusals that went through _validationErrorResponse keep its
# issue code, `processing`.
rep('return _validationErrorResponse(', 'throw SearchRefused(fhir.IssueType.processing, ', 8)

rep('''    // Patient-level scope enforcement: the whole search runs inside the
    // patient's compartment, as the compartment context of R4B search.html
    // 3.1.1.2, one SQL condition in the store. A type the compartment does
    // not include comes back empty from the store. This used to fetch every
    // id in the compartment for the type and pass the list back in as `_id`.
    final patientId = patientContextFor(request, resourceType, 's');
    final compartment =
        patientId == null ? null : patientCompartment(patientId);

''', '')

rep('        return _emptySearchBundle(request, total, links);',
    '''        return fhir.Bundle(
          type: fhir.BundleType.searchset,
          total: total != 'none' ? fhir.FhirUnsignedInt(0) : null,
          link: [links.self(requestedUri)],
        );''')

n_uri = region.count('request.requestedUri')
assert n_uri >= 3, n_uri
region = region.replace('request.requestedUri', 'requestedUri')
print('request.requestedUri ->', n_uri)

rep('    final principal = Principal.of(request);\n', '')

rep('''      return Response.ok(
        bundle.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );''', '      return bundle;', 2)
rep('''    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );''', '    return bundle;')

leftover = [
    l for l in region.splitlines()
    if not l.strip().startswith('//')
    and 'request' in l.replace('requestedUri', '').replace('requested', '')
]
assert not leftover, leftover

REFUSED = '''}

/// A type-level search the server will not answer: the OperationOutcome
/// issue [code] and [message] the REST path sends with its 400, so a
/// Bundle entry can send the same.
class SearchRefused implements Exception {
  /// Creates the refusal.
  const SearchRefused(this.code, this.message);

  /// The OperationOutcome issue code.
  final fhir.IssueType code;

  /// What was refused and why.
  final String message;

  @override
  String toString() => 'SearchRefused($code): $message';
}

'''

new_region = WRAPPER + tail + TYPE_SEARCH_HEAD + region + REFUSED
s = s[:start] + new_region + s[end:]

# _emptySearchBundle served only the lifted body.
assert s.count('_emptySearchBundle(') == 1, s.count('_emptySearchBundle(')
a = s.index('Response _emptySearchBundle(')
b = s.index('\n}\n', a) + 3
s = s[:a] + s[b:].lstrip('\n')

p.write_text(s)
print('written', len(s))
