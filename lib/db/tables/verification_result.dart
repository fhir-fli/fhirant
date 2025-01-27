import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;

@DataClassName('VerificationResult')
/// [fhir.VerificationResult] table for Drift
class VerificationResultTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
}

@DataClassName('VerificationResultHistory')
/// [fhir.VerificationResult] history table for Drift
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
