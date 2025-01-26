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
      var fileString = '''
import 'package:drift/drift.dart';

@DataClassName('$updatedResource')
class $updatedResource extends Table {
  TextColumn get id => text().customConstraint('NOT NULL PRIMARY KEY')();
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();
  TextColumn get resource => text().customConstraint('NOT NULL')();
''';

      if (resource.isCanonicalResource) {
        fileString += '''
  TextColumn get url => text().customConstraint('NOT NULL')();
  TextColumn get status => text().customConstraint('NOT NULL')();
  IntColumn get date => integer().nullable()();
  TextColumn get title => text().nullable()();

  @override
  List<Set<Column>> get indexes => [
        {url},
        {status},
      ];
''';
      }

      fileString += '''
}

@DataClassName('${updatedResource}History')
class ${updatedResource}History extends Table {
  TextColumn get id => text().customConstraint('NOT NULL')();
  IntColumn get lastUpdated => integer().customConstraint('NOT NULL')();
  TextColumn get resource => text().customConstraint('NOT NULL')();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
''';

      final fileName = resource.toLowerSnakeCase();
      File('tables/$fileName.dart').writeAsStringSync(fileString);
    }
  }
}
