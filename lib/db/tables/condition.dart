// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ConditionDrift')
/// [Condition]Table for Drift
class ConditionTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// Patient ID column
  TextColumn get patientId => text()();

  /// Clinical status column
  TextColumn get clinicalStatus => text().nullable()();

  /// Verification status column
  TextColumn get verificationStatus => text().nullable()();

  /// Code column
  TextColumn get code => text().nullable()();

  /// Onset date and time column
  IntColumn get onsetDateTime => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ConditionHistoryDrift')
/// [Condition]HistoryTable for Drift
class ConditionHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
