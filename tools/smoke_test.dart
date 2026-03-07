// Smoke test script for FHIRant server.
//
// Usage:
//   dart run tools/smoke_test.dart [base-url] [--auth]
//
// If no URL is provided, defaults to http://localhost:8080.
// The --auth flag enables Group 7 (authentication) tests.

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// ANSI colours
// ---------------------------------------------------------------------------
const _green = '\x1B[32m';
const _red = '\x1B[31m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _bold = '\x1B[1m';
const _reset = '\x1B[0m';

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
late final HttpClient _client;
late final Uri _base;
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];
final List<String> _cleanupIds = []; // Patient IDs to delete at the end

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Send an HTTP request and return status code + decoded JSON body (if any).
Future<({int status, dynamic body, Map<String, String> headers})> _request(
  String method,
  String path, {
  Object? body,
  Map<String, String>? headers,
  String? token,
}) async {
  final uri = _base.resolve(path);
  final req = await _client.openUrl(method, uri);
  req.headers.set('Content-Type', 'application/fhir+json');
  req.headers.set('Accept', 'application/fhir+json');
  req.headers.set('X-Forwarded-For', '127.0.0.1');
  if (token != null) {
    req.headers.set('Authorization', 'Bearer $token');
  }
  headers?.forEach((k, v) => req.headers.set(k, v));

  if (body != null) {
    final encoded = body is String ? body : jsonEncode(body);
    req.headers.set('Content-Length', utf8.encode(encoded).length.toString());
    req.write(encoded);
  }

  final res = await req.close();
  final resBody = await res.transform(utf8.decoder).join();
  final resHeaders = <String, String>{};
  res.headers.forEach((name, values) {
    resHeaders[name] = values.join(', ');
  });
  dynamic decoded;
  if (resBody.isNotEmpty) {
    try {
      decoded = jsonDecode(resBody);
    } catch (_) {
      decoded = resBody;
    }
  }
  return (status: res.statusCode, body: decoded, headers: resHeaders);
}

/// Record a test result.
void _check(String name, bool condition, [String? detail]) {
  if (condition) {
    _passed++;
    print('  $_green[PASS]$_reset $name');
  } else {
    _failed++;
    final msg = detail != null ? '$name -- $detail' : name;
    _failures.add(msg);
    print('  $_red[FAIL]$_reset $name${detail != null ? ' ($detail)' : ''}');
  }
}

/// Print a group header.
void _group(String title) {
  print('\n$_bold$_cyan=== $title ===$_reset');
}

// ---------------------------------------------------------------------------
// Test groups
// ---------------------------------------------------------------------------

Future<void> _testHealthAndMetadata() async {
  _group('Group 1: Health & Metadata');

  // GET /health
  final health = await _request('GET', '/health');
  _check('GET /health -> 200', health.status == 200,
      'got ${health.status}');
  _check('GET /health body has "status"',
      health.body is Map && (health.body as Map).containsKey('status'));

  // GET /metadata
  final meta = await _request('GET', '/metadata');
  _check('GET /metadata -> 200', meta.status == 200,
      'got ${meta.status}');
  _check(
    'GET /metadata returns CapabilityStatement',
    meta.body is Map &&
        (meta.body as Map)['resourceType'] == 'CapabilityStatement',
  );

  // GET /.well-known/smart-configuration
  final smart = await _request('GET', '/.well-known/smart-configuration');
  _check('GET /.well-known/smart-configuration -> 200',
      smart.status == 200, 'got ${smart.status}');
}

Future<void> _testCrud() async {
  _group('Group 2: CRUD');

  // POST /Patient
  final patient = {
    'resourceType': 'Patient',
    'name': [
      {
        'family': 'SmokeTest',
        'given': ['Original'],
      }
    ],
    'birthDate': '1990-01-01',
  };
  final created = await _request('POST', '/Patient', body: patient);
  _check('POST /Patient -> 201', created.status == 201,
      'got ${created.status}');
  final id = created.body is Map ? (created.body as Map)['id'] : null;
  _check('POST /Patient body has id', id != null);
  if (id == null) return; // cannot continue without id
  _cleanupIds.add(id.toString());

  // GET /Patient/<id>
  final read = await _request('GET', '/Patient/$id');
  _check('GET /Patient/$id -> 200', read.status == 200,
      'got ${read.status}');
  _check(
    'GET /Patient/$id returns same patient',
    read.body is Map && (read.body as Map)['id']?.toString() == id.toString(),
  );

  // PUT /Patient/<id> with updated name
  final updated = Map<String, dynamic>.from(read.body as Map);
  updated['name'] = [
    {
      'family': 'SmokeTest',
      'given': ['Updated'],
    }
  ];
  final putRes = await _request('PUT', '/Patient/$id', body: updated);
  _check('PUT /Patient/$id -> 200', putRes.status == 200,
      'got ${putRes.status}');

  // GET /Patient/<id> verify update
  final verify = await _request('GET', '/Patient/$id');
  final given = _extractGiven(verify.body);
  _check('GET /Patient/$id name updated', given == 'Updated',
      'got "$given"');

  // DELETE /Patient/<id>
  final del = await _request('DELETE', '/Patient/$id');
  _check('DELETE /Patient/$id -> 200 or 204',
      del.status == 200 || del.status == 204, 'got ${del.status}');

  // GET /Patient/<id> after delete -> 410
  final gone = await _request('GET', '/Patient/$id');
  _check('GET /Patient/$id after delete -> 410', gone.status == 410,
      'got ${gone.status}');

  // Remove from cleanup since already deleted
  _cleanupIds.remove(id.toString());
}

String? _extractGiven(dynamic body) {
  if (body is! Map) return null;
  final names = body['name'];
  if (names is! List || names.isEmpty) return null;
  final givens = (names[0] as Map)['given'];
  if (givens is! List || givens.isEmpty) return null;
  return givens[0]?.toString();
}

Future<void> _testSearch() async {
  _group('Group 3: Search');

  // Create 3 patients and 3 observations with different codes
  final patientIds = <String>[];
  for (var i = 1; i <= 3; i++) {
    final res = await _request('POST', '/Patient', body: {
      'resourceType': 'Patient',
      'name': [
        {
          'family': 'SearchTest$i',
          'given': ['Patient$i'],
        }
      ],
    });
    if (res.status == 201 && res.body is Map) {
      final pid = (res.body as Map)['id']?.toString();
      if (pid != null) {
        patientIds.add(pid);
        _cleanupIds.add(pid);
      }
    }
  }

  // Create observations
  final obsIds = <String>[];
  for (var i = 0; i < patientIds.length; i++) {
    final code = 'smoke-test-code-$i';
    final obs = {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [
          {
            'system': 'http://smoke-test.local',
            'code': code,
            'display': 'Smoke Test Code $i',
          }
        ]
      },
      'subject': {
        'reference': 'Patient/${patientIds[i]}',
      },
      'valueString': 'test-value-$i',
    };
    final res = await _request('POST', '/Observation', body: obs);
    if (res.status == 201 && res.body is Map) {
      final oid = (res.body as Map)['id']?.toString();
      if (oid != null) obsIds.add(oid);
    }
  }

  // GET /Observation -> Bundle with entries
  final search = await _request('GET', '/Observation');
  _check('GET /Observation -> 200', search.status == 200,
      'got ${search.status}');
  _check(
    'GET /Observation returns Bundle',
    search.body is Map && (search.body as Map)['resourceType'] == 'Bundle',
  );

  // GET /Observation?code=smoke-test-code-0 -> filtered
  final filtered = await _request(
      'GET', '/Observation?code=smoke-test-code-0');
  _check('GET /Observation?code=smoke-test-code-0 -> 200',
      filtered.status == 200, 'got ${filtered.status}');
  if (filtered.body is Map) {
    final entries = (filtered.body as Map)['entry'] as List?;
    _check(
      'Filtered search returns results',
      entries != null && entries.isNotEmpty,
      'got ${entries?.length ?? 0} entries',
    );
  }

  // GET /Patient?_elements=name -> SUBSETTED tag
  final elements = await _request('GET', '/Patient?_elements=name');
  _check('GET /Patient?_elements=name -> 200', elements.status == 200,
      'got ${elements.status}');
  if (elements.body is Map) {
    final entries = (elements.body as Map)['entry'] as List?;
    if (entries != null && entries.isNotEmpty) {
      final resource =
          (entries[0] as Map)['resource'] as Map<String, dynamic>?;
      // Check for SUBSETTED tag in meta
      final meta = resource?['meta'] as Map?;
      final tags = meta?['tag'] as List?;
      final hasSubsetted = tags?.any((t) =>
              (t as Map)['code'] == 'SUBSETTED') ??
          false;
      _check('_elements response has SUBSETTED tag', hasSubsetted);
    } else {
      _check('_elements response has entries', false, 'no entries returned');
    }
  }

  // Cleanup observations
  for (final oid in obsIds) {
    await _request('DELETE', '/Observation/$oid');
  }
}

Future<void> _testBundles() async {
  _group('Group 4: Bundles');

  final bundle = {
    'resourceType': 'Bundle',
    'type': 'transaction',
    'entry': [
      {
        'resource': {
          'resourceType': 'Patient',
          'name': [
            {
              'family': 'BundleTestA',
              'given': ['Alice'],
            }
          ],
        },
        'request': {
          'method': 'POST',
          'url': 'Patient',
        },
      },
      {
        'resource': {
          'resourceType': 'Patient',
          'name': [
            {
              'family': 'BundleTestB',
              'given': ['Bob'],
            }
          ],
        },
        'request': {
          'method': 'POST',
          'url': 'Patient',
        },
      },
    ],
  };

  final res = await _request('POST', '/', body: bundle);
  _check('POST / transaction Bundle -> 200', res.status == 200,
      'got ${res.status}');
  _check(
    'Response is a Bundle',
    res.body is Map && (res.body as Map)['resourceType'] == 'Bundle',
  );

  // Verify both patients created
  if (res.body is Map) {
    final entries = (res.body as Map)['entry'] as List?;
    _check('Response Bundle has 2 entries',
        entries != null && entries.length == 2,
        'got ${entries?.length ?? 0}');

    // Track IDs for cleanup
    if (entries != null) {
      for (final entry in entries) {
        final response = (entry as Map)['response'] as Map?;
        final location = response?['location']?.toString();
        if (location != null && location.contains('/')) {
          final parts = location.split('/');
          if (parts.length >= 2) {
            _cleanupIds.add(parts[1]);
          }
        }
      }
    }
  }
}

Future<void> _testHistory() async {
  _group('Group 5: History');

  // Create a patient
  final created = await _request('POST', '/Patient', body: {
    'resourceType': 'Patient',
    'name': [
      {'family': 'HistoryTest', 'given': ['V1']},
    ],
  });
  if (created.status != 201 || created.body is! Map) {
    _check('Create patient for history test', false,
        'got ${created.status}');
    return;
  }
  final id = (created.body as Map)['id']?.toString();
  if (id == null) {
    _check('Patient has id', false);
    return;
  }
  _cleanupIds.add(id);

  // Update twice (with small delays to get distinct version IDs)
  await Future<void>.delayed(const Duration(seconds: 1));
  final v1 = Map<String, dynamic>.from(created.body as Map);
  v1['name'] = [
    {'family': 'HistoryTest', 'given': ['V2']},
  ];
  await _request('PUT', '/Patient/$id', body: v1);

  await Future<void>.delayed(const Duration(seconds: 1));
  final v2Read = await _request('GET', '/Patient/$id');
  if (v2Read.body is Map) {
    final v2 = Map<String, dynamic>.from(v2Read.body as Map);
    v2['name'] = [
      {'family': 'HistoryTest', 'given': ['V3']},
    ];
    await _request('PUT', '/Patient/$id', body: v2);
  }

  // GET /Patient/<id>/_history
  final history = await _request('GET', '/Patient/$id/_history');
  _check('GET /Patient/$id/_history -> 200', history.status == 200,
      'got ${history.status}');
  if (history.body is Map) {
    final entries = (history.body as Map)['entry'] as List?;
    _check(
      'History Bundle has 3 entries',
      entries != null && entries.length == 3,
      'got ${entries?.length ?? 0} entries',
    );
  }
}

Future<void> _testBackupRestore() async {
  _group('Group 6: Backup/Restore');

  // POST /$backup
  final backup = await _request('POST', '/\$backup');
  _check('POST /\$backup -> 200', backup.status == 200,
      'got ${backup.status}');
  _check(
    'Backup returns a Bundle',
    backup.body is Map && (backup.body as Map)['resourceType'] == 'Bundle',
  );

  // POST /$restore with a small test Bundle
  final restoreBundle = {
    'resourceType': 'Bundle',
    'type': 'collection',
    'entry': [
      {
        'resource': {
          'resourceType': 'Patient',
          'id': 'smoke-restore-test',
          'name': [
            {'family': 'RestoreTest', 'given': ['Restored']},
          ],
        },
      },
    ],
  };
  final restore = await _request('POST', '/\$restore', body: restoreBundle);
  _check('POST /\$restore -> 200', restore.status == 200,
      'got ${restore.status}');
  _check(
    'Restore returns OperationOutcome',
    restore.body is Map &&
        (restore.body as Map)['resourceType'] == 'OperationOutcome',
  );

  // Cleanup the restored patient
  await _request('DELETE', '/Patient/smoke-restore-test');
}

Future<void> _testAuth() async {
  _group('Group 7: Auth');

  // Use a unique username to avoid collisions
  final ts = DateTime.now().millisecondsSinceEpoch;
  final username = 'smoketest_$ts';
  // Password must meet NIST 800-63B policy: min 12 chars, not common
  final password = 'SmokeT3st!Pw_$ts';

  // POST /auth/register
  final reg = await _request('POST', '/auth/register', body: {
    'username': username,
    'password': password,
    'role': 'clinician',
  });
  // First user gets 201 (bootstrap), subsequent may need admin token
  _check(
    'POST /auth/register -> 201 or 403',
    reg.status == 201 || reg.status == 403,
    'got ${reg.status}',
  );

  if (reg.status != 201) {
    print('  ${_yellow}[SKIP]$_reset Cannot test auth further -- '
        'registration requires admin token (users already exist)');
    return;
  }

  // POST /auth/login
  final login = await _request('POST', '/auth/login', body: {
    'username': username,
    'password': password,
  });
  _check('POST /auth/login -> 200', login.status == 200,
      'got ${login.status}');
  final token =
      login.body is Map ? (login.body as Map)['token']?.toString() : null;
  _check('Login response has token', token != null);

  if (token != null) {
    // GET /Patient with Bearer token
    final authed = await _request('GET', '/Patient', token: token);
    _check('GET /Patient with token -> 200', authed.status == 200,
        'got ${authed.status}');
  }

  // GET /Patient without token (should be 401 in non-dev mode)
  // This is best-effort -- in dev mode it will return 200
  final noAuth = await _request('GET', '/Patient');
  if (noAuth.status == 401) {
    _check('GET /Patient without token -> 401 (non-dev mode)', true);
  } else {
    print('  ${_yellow}[INFO]$_reset GET /Patient without token returned '
        '${noAuth.status} (server may be in dev mode)');
  }
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

Future<void> _cleanup() async {
  if (_cleanupIds.isEmpty) return;
  print('\n${_bold}Cleaning up ${_cleanupIds.length} test resource(s)...$_reset');
  for (final id in _cleanupIds) {
    try {
      await _request('DELETE', '/Patient/$id');
    } catch (_) {
      // best effort
    }
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  // Parse arguments
  String baseUrl = 'http://localhost:8080';
  bool runAuth = false;

  for (final arg in args) {
    if (arg == '--auth') {
      runAuth = true;
    } else if (!arg.startsWith('-')) {
      baseUrl = arg;
    }
  }

  // Strip trailing slash
  if (baseUrl.endsWith('/')) {
    baseUrl = baseUrl.substring(0, baseUrl.length - 1);
  }

  _base = Uri.parse(baseUrl);
  _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (_, __, ___) => true; // allow self-signed

  print('${_bold}FHIRant Smoke Test$_reset');
  print('Target: $baseUrl');
  print('Auth tests: ${runAuth ? "enabled" : "disabled (use --auth to enable)"}');

  // Check connectivity first
  try {
    final probe = await _request('GET', '/health');
    if (probe.status == 0) throw Exception('no response');
  } on SocketException catch (e) {
    print('\n${_red}ERROR: Cannot connect to $baseUrl$_reset');
    print('  $e');
    print('  Is the server running?');
    exit(1);
  } on HttpException catch (e) {
    print('\n${_red}ERROR: HTTP error connecting to $baseUrl$_reset');
    print('  $e');
    exit(1);
  } catch (e) {
    // The health check itself might have worked (we already recorded the
    // result inside _request); if the status was fine, keep going.
    if (e is! FormatException) {
      print('\n${_red}ERROR: Cannot connect to $baseUrl$_reset');
      print('  $e');
      exit(1);
    }
  }

  try {
    await _testHealthAndMetadata();
    await _testCrud();
    await _testSearch();
    await _testBundles();
    await _testHistory();
    await _testBackupRestore();
    if (runAuth) {
      await _testAuth();
    }
  } catch (e, st) {
    print('\n${_red}UNEXPECTED ERROR: $e$_reset');
    print(st);
    _failed++;
  } finally {
    await _cleanup();
    _client.close();
  }

  // Summary
  final total = _passed + _failed;
  print('\n$_bold--- Summary ---$_reset');
  print('$_green$_passed passed$_reset, '
      '${_failed > 0 ? '$_red$_failed failed$_reset' : '${_green}0 failed$_reset'} '
      '($total total)');

  if (_failures.isNotEmpty) {
    print('\n${_red}Failures:$_reset');
    for (final f in _failures) {
      print('  - $f');
    }
  }

  exit(_failed > 0 ? 1 : 0);
}
