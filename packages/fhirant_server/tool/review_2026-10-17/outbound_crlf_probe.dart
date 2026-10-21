// OWASP ASVS 5.0.0 V4.2.5 (L3): "if the application ... builds and sends
// requests, it uses validation, sanitization, or other mechanisms to avoid
// creating URIs (such as for API calls) or HTTP request header fields (such
// as Authorization or Cookie), which are too long for the receiving
// component" (read 2026-10-21), plus what CR/LF does in what fhirant sends.
// Subscription delivery sends client-chosen `channel.header` strings and
// `channel.endpoint` through package:http over dart:io. Each case sends
// through that client to a raw socket and records what reached the wire.
// One row per case to outbound_crlf_probe.tsv, flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/outbound_crlf_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final out = File('tool/review_2026-10-17/outbound_crlf_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('case\tclient result\twire (escaped)\n')
    ..flushSync();
  final listener = await ServerSocket.bind('127.0.0.1', 0);
  final wire = StreamController<String>.broadcast();
  listener.listen((s) {
    final got = StringBuffer();
    var answered = false;
    s.listen((b) async {
      got.write(latin1.decode(b));
      if (!answered && '$got'.contains('\r\n\r\n')) {
        answered = true;
        wire.add('$got');
        s.write('HTTP/1.1 200 OK\r\nContent-Length: 0\r\n'
            'Connection: close\r\n\r\n');
        await s.flush();
        await s.close();
      }
    });
  });
  final base = 'http://127.0.0.1:${listener.port}';
  final cases = <(String, String, Map<String, String>)>[
    ('control', '$base/hook', {'X-Test': 'plain'}),
    ('CRLF in a header value', '$base/hook', {'X-Test': 'a\r\nInjected: b'}),
    ('LF in a header value', '$base/hook', {'X-Test': 'a\nInjected: b'}),
    ('CRLF in a header name', '$base/hook', {'X-Test\r\nInjected': 'b'}),
    ('CRLF in the endpoint path', '$base/hook\r\nInjected: b', {}),
    ('64 KiB header value', '$base/hook', {'X-Test': 'a' * 65536}),
  ];
  final client = http.Client();
  for (final (name, url, headers) in cases) {
    String result;
    final seen = wire.stream.first
        .timeout(const Duration(seconds: 3), onTimeout: () => '(nothing)');
    try {
      final r = await client
          .post(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 3));
      result = 'sent, ${r.statusCode}';
    } catch (e) {
      result = 'refused: ${'$e'.split('\n').first}';
    }
    final w = result.startsWith('refused') ? '(not sent)' : await seen;
    final escaped = w
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    final row = [
      name,
      result,
      if (escaped.length > 300) '${escaped.substring(0, 300)}...' else escaped,
    ].join('\t');
    out
      ..writeStringSync('$row\n')
      ..flushSync();
    stdout.writeln(row);
  }
  client.close();
  await listener.close();
  await wire.close();
  out.closeSync();
  exit(0);
}
