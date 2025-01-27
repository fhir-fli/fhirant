import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('ResearchStudy')
/// [ResearchStudy] table for Drift
class ResearchStudyTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
}

@DataClassName('ResearchStudyHistory')
/// [ResearchStudy] history table for Drift
class ResearchStudyHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
