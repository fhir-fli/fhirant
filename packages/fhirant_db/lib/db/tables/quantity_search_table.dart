import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Quantity Search Parameter Table
class QuantitySearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();

  /// The numeric value part of the quantity
  RealColumn get quantityValue => real()();

  /// Unit (optional)
  TextColumn get quantityUnit => text().nullable()();

  /// Unit system (optional)
  TextColumn get quantitySystem => text().nullable()();

  /// Coded representation of the unit (optional)
  TextColumn get quantityCode => text().nullable()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};
}

extension QuantitySearchParametersExtension on fhir.FhirBase {
  List<QuantitySearchParametersCompanion> toQuantitySearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final fhir.FhirBase fhirObject = this;
    final searchParameters = <QuantitySearchParametersCompanion>[];
    if (fhirObject is fhir.Quantity) {
      searchParameters.add(QuantitySearchParametersCompanion(
        resourceType: Value(resourceType),
        id: Value(id),
        lastUpdated: Value(lastUpdated),
        searchPath: Value(searchPath),
        paramIndex: paramIndex == null ? Value.absent() : Value(paramIndex),
        quantityValue: fhirObject.value?.valueNum != null
            ? Value(fhirObject.value!.valueNum!.toDouble())
            : Value.absent(),
        quantityUnit: fhirObject.unit?.valueString == null
            ? Value.absent()
            : Value(fhirObject.unit!.valueString),
        quantitySystem: fhirObject.system?.valueString == null
            ? Value.absent()
            : Value(fhirObject.system.toString()),
        quantityCode: fhirObject.code?.valueString == null
            ? Value.absent()
            : Value(fhirObject.code!.valueString!),
      ));
    } else {
      throw ArgumentError('Invalid FHIR object type');
    }
    return searchParameters;
  }
}
