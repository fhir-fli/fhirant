// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('LocationTable')
/// [Location]Table for Drift
class LocationTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

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
}

@DataClassName('LocationHistoryTable')
/// [Location]HistoryTable for Drift
class LocationHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
