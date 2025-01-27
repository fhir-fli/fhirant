// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('Condition')
/// [Condition] table for Drift
class ConditionTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  /// Patient ID column
  TextColumn get patientId => text().customConstraint('NOT NULL')();

  /// Clinical status column
  TextColumn get clinicalStatus => text().nullable()();

  /// Verification status column
  TextColumn get verificationStatus => text().nullable()();

  /// Code column
  TextColumn get code => text().nullable()();

  /// Onset date and time column
  IntColumn get onsetDateTime => integer().nullable()();
}

@DataClassName('ConditionHistory')
/// [Condition] table for Drift
class ConditionHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
