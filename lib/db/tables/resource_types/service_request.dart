import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ServiceRequestDrift')
/// [ServiceRequest]Table for Drift
class ServiceRequestTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ServiceRequestHistoryDrift')
/// [ServiceRequest]HistoryTable for Drift
class ServiceRequestHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
