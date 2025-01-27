// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('MedicationRequestDrift')
/// [MedicationRequest]Table for Drift
class MedicationRequestTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  /// Patient ID column
  TextColumn get patientId => text().customConstraint('NOT NULL')();

  /// Medication ID column
  TextColumn get medicationId => text().customConstraint('NOT NULL')();

  /// Intent column
  TextColumn get intent => text().nullable()();

  /// Priority column
  TextColumn get priority => text().nullable()();

  /// Status column
  TextColumn get status => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
    {patientId},
    {status},
  ];
}

@DataClassName('MedicationRequestHistoryDrift')
/// [MedicationRequest]HistoryTable for Drift
class MedicationRequestHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
