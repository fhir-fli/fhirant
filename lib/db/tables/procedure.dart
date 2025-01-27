// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ProcedureDrift')
/// [Procedure]Table for Drift
class ProcedureTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// Patient ID column
  TextColumn get patientId => text()();

  /// Code column
  TextColumn get code => text()();

  /// Performed date and time column
  IntColumn get performedDateTime => integer().nullable()();

  /// Status column
  TextColumn get status => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
    {patientId},
    {status},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProcedureHistoryDrift')
/// [Procedure]HistoryTable for Drift
class ProcedureHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
