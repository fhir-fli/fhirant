import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('EvidenceVariable')
/// [EvidenceVariable] table for Drift
class EvidenceVariableTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
}

@DataClassName('EvidenceVariableHistory')
/// [EvidenceVariable] history table for Drift
class EvidenceVariableHistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
