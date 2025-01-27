// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('EncounterDrift')
/// [Encounter]Table for Drift
class EncounterTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  /// Patient ID column
  TextColumn get patientId => text().customConstraint('NOT NULL')();

  /// Encounter type column
  TextColumn get type => text().nullable()();

  /// Start date and time column
  IntColumn get startDateTime => integer().nullable()();

  /// End date and time column
  IntColumn get endDateTime => integer().nullable()();

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

@DataClassName('EncounterHistoryDrift')
/// [Encounter]HistoryTable for Drift
class EncounterHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
