import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ChargeItemDrift')
/// [ChargeItem]Table for Drift
class ChargeItemTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ChargeItemHistoryDrift')
/// [ChargeItem]HistoryTable for Drift
class ChargeItemHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
