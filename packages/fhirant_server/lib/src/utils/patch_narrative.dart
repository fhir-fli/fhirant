import 'dart:convert';

/// A patch that would leave a narrative saying what the data no longer
/// says, refused rather than stored (422).
class NarrativeWouldMislead implements Exception {
  /// Creates the refusal for a narrative of [status].
  const NarrativeWouldMislead(this.status);

  /// The narrative's `text.status`.
  final String status;

  /// The words the refusal carries.
  String get message =>
      'The patch changes the data of a resource whose narrative '
      '(text.status "$status") was written by a person and is not generated '
      'from that data, so the narrative would no longer match it. Patch '
      '/text as well, or update the whole resource.';

  @override
  String toString() => message;
}

/// The document to store after a JSON Patch took [before] to [after].
///
/// R4B http.html 3.1.0.6 (read whole 2026-10-17, verbatim): "The server
/// SHALL ensure that the narrative in a resource is not clinically unsafe
/// after the PATCH operation is performed", with the remedies "If the
/// existing narrative has a status != generated, the server could reject
/// the PATCH operation" and "The server could delete the narrative, on the
/// basis that some later process will be able to populate it correctly".
/// A potassium patched from 3.0 to 6.5 used to keep "Potassium 3.0 mmol/L
/// (LOW)" (REVIEW-2026-10-17 finding 4).
///
/// This server generates no narrative. So: when the patch writes `/text`
/// itself, or changes nothing but `text` and `meta`, the client is keeping
/// the narrative and [after] stands; otherwise a `generated` narrative is
/// removed, an `empty` one kept, and any other status (`additional`,
/// `extensions`: words the data does not hold) throws
/// [NarrativeWouldMislead].
Map<String, dynamic> narrativeAfterPatch(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
  List<dynamic> operations,
) {
  final text = before['text'];
  if (text is! Map) return after;
  final writesText = operations.any((op) {
    if (op is! Map) return false;
    final path = op['path'];
    return path is String && (path == '/text' || path.startsWith('/text/'));
  });
  if (writesText || _sameData(before, after)) return after;
  final status = text['status'] as String? ?? '';
  switch (status) {
    case 'empty':
      return after;
    case 'generated':
      return {...after}..remove('text');
    default:
      throw NarrativeWouldMislead(status);
  }
}

/// Whether [a] and [b] differ in nothing but `text` and `meta`.
bool _sameData(Map<String, dynamic> a, Map<String, dynamic> b) {
  String data(Map<String, dynamic> m) {
    final copy = {...m}
      ..remove('text')
      ..remove('meta');
    return jsonEncode(copy);
  }

  return data(a) == data(b);
}
