import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('EventDefinitionDrift')
/// [EventDefinition]Table for Drift
class EventDefinitionTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// URL column
  TextColumn get url => text().nullable()();

  /// Status column
  TextColumn get status => text()();

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

@DataClassName('EventDefinitionHistoryDrift')
/// [EventDefinition]HistoryTable for Drift
class EventDefinitionHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
