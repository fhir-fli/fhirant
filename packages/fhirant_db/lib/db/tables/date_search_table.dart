import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Date Search Parameter Table
class DateSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();
  TextColumn get dateString => text()();

  /// Date value; storing as a DateTime allows for comparisons,
  /// but if you need to preserve a specific string format, consider using text()
  DateTimeColumn get dateValue => dateTime()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};
}

extension DateSearchParametersExtension on fhir.FhirBase {
  List<DateSearchParametersCompanion> toDateSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final results = <DateSearchParametersCompanion>[];

    switch (this) {
      case fhir.FhirDate date:
        if (date.valueString != null) {
          results.add(DateSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            dateString: Value(date.valueString!),
            dateValue: date.valueDateTime != null
                ? Value(date.valueDateTime!)
                : Value.absent(),
          ));
        }
        return results;

      case fhir.FhirDateTime dateTime:
        if (dateTime.valueString != null) {
          results.add(DateSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            dateString: Value(dateTime.valueString!),
            dateValue: dateTime.valueDateTime != null
                ? Value(dateTime.valueDateTime!)
                : Value.absent(),
          ));
        }
        return results;

      case fhir.FhirInstant instant:
        if (instant.valueString != null) {
          results.add(DateSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            dateString: Value(instant.valueString!),
            dateValue: instant.valueDateTime != null
                ? Value(instant.valueDateTime!)
                : Value.absent(),
          ));
        }
        return results;

      // If it's not one of the known types, return empty or throw
      default:
        return [];
    }
  }
}
