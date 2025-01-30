import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('AllergyIntoleranceDrift')
/// [AllergyIntolerance]Table for Drift
class AllergyIntoleranceTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AllergyIntoleranceHistoryDrift')
/// [AllergyIntolerance]HistoryTable for Drift
class AllergyIntoleranceHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
