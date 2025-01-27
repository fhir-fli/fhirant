import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';

void main() {
  for (final resource in R4ResourceType.typesAsStrings) {
    if (![
      'Condition',
      'Encounter',
      'Location',
      'MedicationAdministration',
      'MedicationDispense',
      'MedicationRequest',
      'Medication',
      'Observation',
      'Patient',
      'Procedure',
      'Specimen',
    ].contains(resource)) {
      final updatedResource =
          ['Endpoint', 'Group', 'List'].contains(resource)
              ? 'Fhir$resource'
              : resource;
      var fileString = """
import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('${updatedResource}Drift')
/// [$updatedResource]Table for Drift
class ${updatedResource}Table extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();
""";

      if (resource.isCanonicalResource) {
        fileString += """
  /// URL column
  TextColumn get url => text().customConstraint('NOT NULL')();

  /// Status column
  TextColumn get status => text().customConstraint('NOT NULL')();

  /// Date column
  IntColumn get date => integer().nullable()();

  /// Title column
  TextColumn get title => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
        {url},
        {status},
      ];
""";
      }

      fileString += """
}

@DataClassName('${updatedResource}HistoryDrift')
/// [$updatedResource]HistoryTable for Drift
class ${updatedResource}HistoryTable extends Table {
  /// ID column
  TextColumn get id => text().customConstraint('NOT NULL')();

  /// Last updated column
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();

  /// Resource column
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
""";

      final fileName = resource.toLowerSnakeCase();
      File('tables/$fileName.dart').writeAsStringSync(fileString);
    }
  }
}
