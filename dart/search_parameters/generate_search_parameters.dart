import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('search-parameters.json');
  final jsonString = await file.readAsString();
  final jsonResponse = jsonDecode(jsonString);

  final searchParamsBundle = Bundle.fromJson(jsonResponse);

  final queryCode = generateQueryCode(searchParamsBundle);

  // Write the generated query code to a file
  final outputFile = File('query.go');
  await outputFile.writeAsString(queryCode);

  print('Generated query code has been written to ${outputFile.path}');
}

String generateQueryCode(Bundle bundle) {
  final buffer = StringBuffer();

  buffer.writeln('package main');
  buffer.writeln();
  buffer.writeln('import (');
  buffer.writeln('  "fmt"');
  buffer.writeln('  "github.com/pocketbase/pocketbase"');
  buffer.writeln('  "github.com/pocketbase/pocketbase/models"');
  buffer.writeln(')');
  buffer.writeln();
  buffer.writeln(
      'func queryResources(app *pocketbase.PocketBase, resourceType string, searchParams map[string]string) ([]*models.Record, error) {');
  buffer.writeln(
      '  collection, err := app.Dao().FindCollectionByNameOrId(resourceType)');
  buffer.writeln('  if err != nil {');
  buffer.writeln('    return nil, fmt.Errorf("collection not found: %w", err)');
  buffer.writeln('  }');
  buffer.writeln();
  buffer.writeln('  query := app.Dao().RecordQuery(resourceType)');
  buffer.writeln();
  buffer.writeln('  // Add search conditions based on search parameters');
  buffer.writeln('  for param, value := range searchParams {');
  buffer.writeln('    switch param {');

  for (var entry in bundle.entry) {
    final resource = entry.resource;

    if (resource.expression.isNotEmpty) {
      buffer.writeln('    case "${resource.code}":');
      buffer.writeln(
          """      query.AndWhere(fmt.Sprintf("json_extract(resource, '\$.${resource.expression}') = ?", param), value)""");
    } else {
      buffer.writeln('    case "${resource.code}":');
      buffer.writeln(
          """      query.AndWhere(fmt.Sprintf("json_extract(resource, '\$.${resource.code}') = ?", param), value)""");
    }
  }

  buffer.writeln('    default:');
  buffer.writeln(
      """      query.AndWhere(fmt.Sprintf("json_extract(resource, '\$.%s') LIKE ?", param), fmt.Sprintf("%%%s%%", value))""");
  buffer.writeln('    }');
  buffer.writeln('  }');
  buffer.writeln();
  buffer.writeln('  records, err := query.All()');
  buffer.writeln('  if err != nil {');
  buffer.writeln(
      '    return nil, fmt.Errorf("failed to query resources: %w", err)');
  buffer.writeln('  }');
  buffer.writeln();
  buffer.writeln('  return records, nil');
  buffer.writeln('}');

  return buffer.toString();
}

class Bundle {
  List<Entry> entry;

  Bundle({required this.entry});

  factory Bundle.fromJson(Map<String, dynamic> json) {
    var list = json['entry'] as List;
    List<Entry> entryList = list.map((i) => Entry.fromJson(i)).toList();

    return Bundle(entry: entryList);
  }
}

class Entry {
  Resource resource;

  Entry({required this.resource});

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      resource: Resource.fromJson(json['resource']),
    );
  }
}

class Resource {
  String code;
  String expression;

  Resource({required this.code, required this.expression});

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      code: json['code'],
      expression: json['expression'] ?? "", // Fallback for expression field
    );
  }
}
