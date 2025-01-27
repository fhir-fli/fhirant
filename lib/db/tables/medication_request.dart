// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('MedicationRequestDrift')
/// [MedicationRequest]Table for Drift
class MedicationRequestTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// Patient ID column
  TextColumn get patientId => text()();

  /// Medication ID column
  TextColumn get medicationId => text()();

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

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MedicationRequestHistoryDrift')
/// [MedicationRequest]HistoryTable for Drift
class MedicationRequestHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
