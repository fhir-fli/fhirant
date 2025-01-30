import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('PaymentNoticeDrift')
/// [PaymentNotice]Table for Drift
class PaymentNoticeTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PaymentNoticeHistoryDrift')
/// [PaymentNotice]HistoryTable for Drift
class PaymentNoticeHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
