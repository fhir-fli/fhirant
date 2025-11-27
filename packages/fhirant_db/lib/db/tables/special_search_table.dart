import 'package:drift/drift.dart';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Special Search Parameter Table
/// For search parameters that require custom handling.
class SpecialSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();
  /// A generic storage column; adjust type if your special logic requires it
  TextColumn get specialValue => text()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};
}

extension SpecialSearchParametersExtension on fhir.FhirBase {
  List<SpecialSearchParametersCompanion> toSpecialSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    return <SpecialSearchParametersCompanion>[];
  }
}
