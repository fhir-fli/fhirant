// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ObservationDrift')
/// [Observation]Table for Drift
class ObservationTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  /// Patient ID column
  TextColumn get patientId => text().customConstraint('NOT NULL')();

  /// Type column
  TextColumn get type => text().nullable()();

  /// Value column
  RealColumn get value => real().nullable()();

  /// Unit column
  TextColumn get unit => text().nullable()();

  /// Effective date and time column
  IntColumn get effectiveDateTime => integer().nullable()();
}

@DataClassName('ObservationHistoryDrift')
/// [Observation]HistoryTable for Drift
class ObservationHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
