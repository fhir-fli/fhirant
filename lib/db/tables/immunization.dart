import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('Immunization')
/// [Immunization] table for Drift
class ImmunizationTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
}

@DataClassName('ImmunizationHistory')
/// [Immunization] history table for Drift
class ImmunizationHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
