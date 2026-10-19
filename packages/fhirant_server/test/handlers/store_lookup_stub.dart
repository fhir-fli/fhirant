import 'package:fhirant_db/fhirant_db.dart';
import 'package:mocktail/mocktail.dart';

class _MockFhirDao extends Mock implements FhirDao {}

/// Has the mocked [db] answer the search-parameter lookup the handlers make
/// (`storeLookup`) as a store with no uploaded SearchParameter does: no
/// registry, and the specification's definitions.
void stubStoreLookup(FhirAntDb db) {
  final dao = _MockFhirDao();
  when(() => dao.lookupDefinition(any(), any())).thenAnswer(
    (i) => searchParameterFor(
      i.positionalArguments[0] as String,
      i.positionalArguments[1] as String,
    ),
  );
  when(() => db.customSearchParameters).thenAnswer((_) async => null);
  when(() => db.fhirDao).thenReturn(dao);
}
