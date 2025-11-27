import 'package:drift/drift.dart';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Composite Search Parameter Table
/// This example assumes a composite of two values. Depending on your needs,
/// you may adjust the types or add additional components.
class CompositeSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();

  /// First component of the composite value
  TextColumn get component1 => text()();

  /// Second component of the composite value
  TextColumn get component2 => text()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};
}

extension CompositeSearchParametersExtension on fhir.FhirBase {
  List<CompositeSearchParametersCompanion> toCompositeSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    return <CompositeSearchParametersCompanion>[];
  }
}
