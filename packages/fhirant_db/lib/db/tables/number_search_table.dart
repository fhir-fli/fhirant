import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Number Search Parameter Table
class NumberSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();

  /// The FHIR search path (e.g., "Observation.valueQuantity.value")
  TextColumn get searchPath => text()();

  /// Index to differentiate multiple values for the same search path
  IntColumn get paramIndex => integer()();

  /// The numeric value extracted from the resource
  RealColumn get numberValue => real()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};
}

extension NumberSearchParametersExtension on fhir.FhirBase {
  List<NumberSearchParametersCompanion> toNumberSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final fhir.FhirBase fhirObject = this;
    final searchParameters = <NumberSearchParametersCompanion>[];
    if (fhirObject is fhir.FhirNumber && fhirObject.valueNum != null) {
      searchParameters.add(NumberSearchParametersCompanion(
        resourceType: Value(resourceType),
        id: Value(id),
        lastUpdated: Value(lastUpdated),
        searchPath: Value(searchPath),
        paramIndex: paramIndex == null ? Value.absent() : Value(paramIndex),
        numberValue: Value(fhirObject.valueNum!.toDouble()),
      ));
    } else {
      throw ArgumentError('Invalid FHIR object type');
    }
    return searchParameters;
  }
}
