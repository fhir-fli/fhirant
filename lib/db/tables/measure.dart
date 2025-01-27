import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('MeasureDrift')
/// [Measure]Table for Drift
class MeasureTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
  /// URL column
  TextColumn get url => text().customConstraint('NOT NULL')();

  /// Status column
  TextColumn get status => text().customConstraint('NOT NULL')();

  /// Date column
  IntColumn get date => integer().nullable()();

  /// Title column
  TextColumn get title => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
        {url},
        {status},
      ];
  
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MeasureHistoryDrift')
/// [Measure]HistoryTable for Drift
class MeasureHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
