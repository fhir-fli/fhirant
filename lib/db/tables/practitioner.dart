import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('Practitioner')
/// [Practitioner] table for Drift
class PractitionerTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
}

@DataClassName('PractitionerHistory')
/// [Practitioner] history table for Drift
class PractitionerHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
