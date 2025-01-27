// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ProcedureDrift')
/// [Procedure]Table for Drift
class ProcedureTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  /// Patient ID column
  TextColumn get patientId => text().customConstraint('NOT NULL')();

  /// Code column
  TextColumn get code => text().customConstraint('NOT NULL')();

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
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
