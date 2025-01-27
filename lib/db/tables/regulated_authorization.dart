import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('RegulatedAuthorizationDrift')
/// [RegulatedAuthorization]Table for Drift
class RegulatedAuthorizationTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
  
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RegulatedAuthorizationHistoryDrift')
/// [RegulatedAuthorization]HistoryTable for Drift
class RegulatedAuthorizationHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
