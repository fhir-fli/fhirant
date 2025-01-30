import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('CompartmentDefinitionDrift')
/// [CompartmentDefinition]Table for Drift
class CompartmentDefinitionTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CompartmentDefinitionHistoryDrift')
/// [CompartmentDefinition]HistoryTable for Drift
class CompartmentDefinitionHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
