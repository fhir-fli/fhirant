import 'dart:io';

import 'package:test/test.dart';

/// A server built in a test names its breached-password lookup. The
/// server's default asks Have I Been Pwned over the network (OWASP ASVS
/// 5.0.0 V6.2.12), and a test that let it would send data out on every run
/// and pass or fail with the connection. So every `FhirAntServer(` under
/// test/ passes `breachedPasswords:` (null, or a stand-in).
void main() {
  test('every FhirAntServer( in test/ passes breachedPasswords', () {
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final missing = <String>[];
    var sites = 0;
    final call = RegExp(r'FhirAntServer\(');
    for (final f in files) {
      if (f.path.endsWith('every_test_server_stays_offline_test.dart')) {
        continue;
      }
      final text = f.readAsStringSync();
      for (final m in call.allMatches(text)) {
        sites++;
        // The call's argument list: up to the matching parenthesis.
        var depth = 0;
        var end = m.end - 1;
        for (var i = m.end - 1; i < text.length; i++) {
          if (text[i] == '(') depth++;
          if (text[i] == ')' && --depth == 0) {
            end = i;
            break;
          }
        }
        if (!text.substring(m.start, end).contains('breachedPasswords:')) {
          final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
          missing.add('${f.path}:$line');
        }
      }
    }
    // 21 when written (2026-11-21): one in test_helpers.dart, 20 elsewhere.
    expect(sites, greaterThanOrEqualTo(21));
    expect(missing, isEmpty);
  });
}
