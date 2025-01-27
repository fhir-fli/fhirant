// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('PatientDrift')
/// [Patient]Table for Drift
class PatientTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// Active column
  BoolColumn get active => boolean().nullable()();

  /// Identifier column
  TextColumn get identifier => text().nullable()();

  /// Family names column
  TextColumn get familyNames => text().nullable()();

  /// Given names column
  TextColumn get givenNames => text().nullable()();

  /// Gender column
  TextColumn get gender => text().nullable()();

  /// Birth date column
  IntColumn get birthDate => integer().nullable()();

  /// Deceased column
  BoolColumn get deceased => boolean().nullable()();

  /// Managing organization column
  TextColumn get managingOrganization => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PatientHistoryDrift')
/// [Patient]HistoryTable for Drift
class PatientHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
