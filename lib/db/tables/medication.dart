// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('MedicationDrift')
/// [Medication]Table for Drift
class MedicationTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  /// Code column
  TextColumn get code => text().nullable()();

  /// Status column
  TextColumn get status => text().nullable()();

  /// Manufacturer column
  TextColumn get manufacturer => text().nullable()();

  /// Form column
  TextColumn get form => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
    {code},
    {status},
  ];
}

@DataClassName('MedicationHistoryDrift')
/// [Medication]HistoryTable for Drift
class MedicationHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
