// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('LocationDrift')
/// [Location]Table for Drift
class LocationTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// Name column
  TextColumn get name => text().nullable()();

  /// Type column
  TextColumn get type => text().nullable()();

  /// Address column
  TextColumn get address => text().nullable()();

  /// Managing organization column
  TextColumn get managingOrganization => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
    {name},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LocationHistoryDrift')
/// [Location]HistoryTable for Drift
class LocationHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
