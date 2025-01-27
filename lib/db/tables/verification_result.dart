import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;

@DataClassName('VerificationResultDrift')
/// [fhir.VerificationResult]Table for Drift
class VerificationResultTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('VerificationResultHistoryDrift')
/// [fhir.VerificationResult]HistoryTable for Drift
class VerificationResultHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
