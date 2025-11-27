import 'package:drift/drift.dart';

class Resources extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  TextColumn get resource => text()();
  DateTimeColumn get lastUpdated => dateTime()();

  @override
  Set<Column> get primaryKey => {resourceType, id};
}

class ResourcesHistory extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  TextColumn get resource => text()();
  DateTimeColumn get lastUpdated => dateTime()();

  @override
  Set<Column> get primaryKey => {resourceType, id, lastUpdated};
}