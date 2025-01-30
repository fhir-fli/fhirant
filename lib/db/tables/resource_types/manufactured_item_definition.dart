import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ManufacturedItemDefinitionDrift')
/// [ManufacturedItemDefinition]Table for Drift
class ManufacturedItemDefinitionTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ManufacturedItemDefinitionHistoryDrift')
/// [ManufacturedItemDefinition]HistoryTable for Drift
class ManufacturedItemDefinitionHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
