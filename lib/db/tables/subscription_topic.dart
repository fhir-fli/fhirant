import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('SubscriptionTopicDrift')
/// [SubscriptionTopic]Table for Drift
class SubscriptionTopicTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// URL column
  TextColumn get url => text()();

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

@DataClassName('SubscriptionTopicHistoryDrift')
/// [SubscriptionTopic]HistoryTable for Drift
class SubscriptionTopicHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
