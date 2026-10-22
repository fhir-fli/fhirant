// What fhir_r4 0.14.0's FhirXhtml accepts as a narrative, against R4B
// txt-1 (profiles-types.json, Narrative.div).
//
// Two parts, one row each to xhtml_probe.tsv, flushed:
//   case     crafted narratives, each parsed inside a Patient
//   example  every Narrative.div in the published R4B examples: does the
//            model accept the publisher's own narrative?
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/xhtml_probe.dart <R4B examples-json dir>
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;

const _ns = 'xmlns="http://www.w3.org/1999/xhtml"';

const _cases = <String, String>{
  'plain': '<div $_ns><p>Seen today.</p></div>',
  'script': '<div $_ns><script>alert(1)</script></div>',
  'onclick': '<div $_ns><p onclick="alert(1)">x</p></div>',
  'javascript-href': '<div $_ns><a href="javascript:alert(1)">x</a></div>',
  'javascript-img-src': '<div $_ns><img src="javascript:alert(1)"/></div>',
  'style-url':
      '<div $_ns><p style="background:url(javascript:alert(1))">x</p></div>',
  'iframe': '<div $_ns><iframe src="https://example.org"/></div>',
  'form': '<div $_ns><form action="https://example.org"/></div>',
  'sub': '<div $_ns><p>H<sub>2</sub>O</p></div>',
  'u': '<div $_ns><p><u>x</u></p></div>',
  'address': '<div $_ns><address>x</address></div>',
  'wrong-root': '<p $_ns>x</p>',
  'no-namespace': '<div><p>x</p></div>',
  'whitespace-only': '<div $_ns> </div>',
};

String _verdict(Map<String, dynamic> json) {
  try {
    fhir.Resource.fromJson(json);
    return 'accepted';
  } catch (e) {
    return 'refused: ${e.toString().replaceAll(RegExp(r'\s+'), ' ')}';
  }
}

void _walkDivs(Object? node, void Function(Map<String, dynamic>) onText) {
  if (node is Map<String, dynamic>) {
    final text = node['text'];
    if (node['resourceType'] is String && text is Map<String, dynamic>) {
      if (text['div'] is String) onText(node);
    }
    for (final v in node.values) {
      _walkDivs(v, onText);
    }
  } else if (node is List) {
    for (final v in node) {
      _walkDivs(v, onText);
    }
  }
}

void main(List<String> args) {
  final out = File('tool/review_2026-10-17/xhtml_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('part\tname\tverdict\n');
  void row(String part, String name, String verdict) {
    out
      ..writeStringSync('$part\t$name\t$verdict\n')
      ..flushSync();
  }

  for (final MapEntry(:key, :value) in _cases.entries) {
    final v = _verdict({
      'resourceType': 'Patient',
      'text': {'status': 'generated', 'div': value},
    });
    row('case', key, v);
    stdout.writeln('case $key: $v');
  }

  var files = 0;
  var divs = 0;
  var refused = 0;
  final dir = Directory(args[0]);
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    Object? doc;
    try {
      doc = jsonDecode(f.readAsStringSync());
    } on FormatException {
      continue;
    }
    files++;
    _walkDivs(doc, (resource) {
      divs++;
      // Parse the narrative alone, so a fault elsewhere in the resource is
      // not counted against its narrative.
      final v = _verdict({
        'resourceType': 'Basic',
        'code': {'text': 'probe'},
        'text': resource['text'],
      });
      if (v != 'accepted') {
        refused++;
        final name = '${f.uri.pathSegments.last} '
            '${resource['resourceType']}/${resource['id']}';
        row('example', name, v);
      }
    });
  }
  row('summary', 'files $files narratives $divs', 'refused $refused');
  stdout.writeln('files $files narratives $divs refused $refused');
  out.closeSync();
}
