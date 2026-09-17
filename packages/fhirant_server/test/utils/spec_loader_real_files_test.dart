import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_bulk/fhir_r4_bulk.dart' show NdjsonStream;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';
import 'package:test/test.dart';

/// The specification load against the files that ship, not stand-ins.
///
/// Found 2026-09-17 by starting the CLI with `--spec-path`
/// (tool/review_2026-09-17/fix_t1_t2/12_cli_with_spec.log): the load
/// stopped at search-parameters.ndjson on the store's own
/// InvalidSearchParameter exception (no expression; the message is in that
/// log, verbatim from the server, and is ours, not a specification's). So
/// valuesets.ndjson, which sorts after it, never loaded, and the server
/// held 0 CodeSystems, 0 ValueSets and 0 SearchParameters.
///
/// Since fhir_db 0.14.0 every SearchParameter save is checked as a client's
/// upload. The shipped definitions are not uploads: counted 2026-09-17 in
/// assets/fhir_spec/search-parameters.ndjson, 8 of the 1,414 carry no
/// expression, and the rest define codes an upload may not redefine. The
/// other loader tests feed the loader resources they wrote themselves.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() => db.close());

  test('search-parameters.ndjson loads whole, as the server', () async {
    final file = File('assets/fhir_spec/search-parameters.ndjson');
    final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
    // An earlier save has loaded the uploaded-parameter registry, as any
    // earlier file of the load has by the time this one is reached.
    await db.saveResource(fhir.Patient(id: 'p'.toFhirString));

    final (loaded, errors) = await loadSpecLines(
      db,
      NdjsonStream.lines(file.openRead()),
      'search-parameters.ndjson',
    );
    expect((loaded, errors), (lines.length, 0));
    expect(
      await db.getResourceCount(fhir.R4ResourceType.SearchParameter),
      lines.length,
    );
    final stored = await db.getResource(
      fhir.R4ResourceType.SearchParameter,
      'Resource-content',
    );
    expect(isSpecResource(stored!), isTrue);
  });

  test("a client's upload is still checked", () async {
    await db.saveResource(fhir.Patient(id: 'p'.toFhirString));
    expect(
      () => db.saveResource(
        fhir.SearchParameter.fromJson({
          'resourceType': 'SearchParameter',
          'id': 'no-expression',
          'url': 'http://example.org/SearchParameter/no-expression',
          'name': 'x',
          'status': 'active',
          'description': 'x',
          'code': 'x',
          'base': ['Patient'],
          'type': 'string',
        }),
      ),
      throwsA(isA<InvalidSearchParameter>()),
    );
  });
}
