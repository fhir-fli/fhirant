import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final searchMap = <String, List<Map<String, String>>>{};
  final Map<String, dynamic> spBundle =
      jsonDecode(await File('search-parameters.json').readAsString());

  for (final Map<String, dynamic> entry
      in spBundle['entry'] ?? <Map<String, dynamic>>[]) {
    final Map<String, dynamic>? sp = entry['resource'];
    final name = sp?['name']?.toString();
    final code = sp?['code']?.toString();
    final type = sp?['type']?.toString();
    final expression = sp?['expression'];

    if (name != null && code != null && type != null && expression != null) {
      for (final base in sp?['base'] ?? <String>[]) {
        if (searchMap[base.toString()] == null) {
          searchMap[base.toString()] = <Map<String, String>>[];
        }
        if (expression.contains('|')) {
          searchMap[base.toString()]!
              .add({'name': name, 'type': type, 'expression': ''});
        } else {
          searchMap[base.toString()]!
              .add({'name': name, 'type': type, 'expression': expression});
        }
      }
    }
  }

  // for (final key in searchMap.keys) {
  //   final List<Map<String, String>> resourceEntries =
  //       searchMap['Resource']!.map((e) {
  //     if (e['expression']!.startsWith('Resource.')) {
  //       return {
  //         'name': e['name']!,
  //         'type': e['type']!,
  //         'expression': e['expression']!.replaceFirst('Resource.', '$key.')
  //       };
  //     }
  //     return e;
  //   }).toList();
  //   if (key != 'Resource') {
  //     searchMap[key] = resourceEntries..addAll(searchMap[key]!);
  //   }
  // }

  searchMap.remove('Resource');
  searchMap.remove('DomainResource');

  // Change the output file name to collections.go
  String goString = '''// collections.go
package main

var collections = []map[string]interface{}{''';

  for (final key in searchMap.keys) {
    goString += mainClass(key);
    searchMap[key]!.forEach((entry) {
      final type = entry['type']!;
      final name = entry['name']!;
      if (name != '_id' &&
          name != '_content' &&
          (name == 'resource' || name == 'versionId')) {
        goString += entries(name, type);
      }
    });
    goString += '''    },
  },''';
    goString += historyClass(key, searchMap[key]!);
  }

  goString += '\n}';

  // Write to collections.go instead of search_parameters_map.go
  await File('collections.go').writeAsString(goString);

  // Generate search_parameters.go file
  // await generateSearchParametersFile(searchMap);
}

String entries(String key, String value) {
  if (['id', 'created', 'updated'].contains(key)) {
    return '';
  }
  key = key.replaceAll('-', '_');
  if (key == 'resource') {
    key = 'resourceSearch';
  }
  switch (value) {
    case 'number':
      return '      {"name": "$key", "type": "number", "required": false},\n';
    case 'date':
      return '      {"name": "$key", "type": "date", "required": false},\n';
    case 'string':
      return '      {"name": "$key", "type": "text", "required": false},\n';
    case 'token':
      return '      {"name": "$key", "type": "json", "options": map[string]interface{}{"maxSize": 5242880}, "required": false},\n';
    case 'reference':
      return '      {"name": "$key", "type": "json", "options": map[string]interface{}{"maxSize": 5242880}, "required": false},\n';
    case 'composite':
      return '      {"name": "$key", "type": "text", "required": false},\n';
    case 'quantity':
      return '      {"name": "$key", "type": "json", "options": map[string]interface{}{"maxSize": 5242880}, "required": false},\n';
    case 'uri':
      return '      {"name": "$key", "type": "url", "required": false},\n';
    case 'special':
      return '      {"name": "$key", "type": "text", "required": false},\n';
    default:
      return '';
  }
}

String mainClass(String className) => '''\n
  {
    "name": "$className",
    "schema": []map[string]interface{}{
      {"name": "versionId", "type": "number", "required": true},
      {"name": "resource", "type": "json", "options": map[string]interface{}{"maxSize": 5242880}, "required": true},
''';

String historyClass(String className, List<Map<String, String>> columns) {
  String historySchema = '''\n
  {
    "name": "${className}History",
    "schema": []map[string]interface{}{
      {"name": "versionId", "type": "number", "required": true},
      {"name": "resource", "type": "json", "options": map[string]interface{}{"maxSize": 5242880}, "required": true},
''';

  columns.forEach((entry) {
    final name = entry['name']!;
    final type = entry['type']!;
    if (name != '_id' &&
        name != '_content' &&
        (name == 'resource' || name == 'versionId')) {
      historySchema += entries(name, type);
    }
  });

  historySchema += '''    },
  },''';

  return historySchema;
}

Future<void> generateSearchParametersFile(
    Map<String, List<Map<String, String>>> searchMap) async {
  String searchParamsGoString = '''// search_parameters.go
package main

type SearchParameter struct {
	Code       string
	Expression string
}

var searchParamsByResourceType = map[string][]SearchParameter{''';

  searchMap.forEach((resourceType, params) {
    searchParamsGoString += '''
    "$resourceType": {''';
    params.forEach((entry) {
      final name = entry['name']!;
      final expression = entry['expression']!;
      searchParamsGoString += '''
      {
        Code: "$name",
        Expression: "$expression",
      },''';
    });
    searchParamsGoString += '''
    },''';
  });

  searchParamsGoString += '''
}
''';

  // Write to search_parameters.go
  await File('search_parameters.go').writeAsString(searchParamsGoString);
}

JsonEncoder encoder = JsonEncoder.withIndent('  ');

String prettyPrint(Map<String, Map<String, String>> searchMap) {
  return encoder.convert(searchMap);
}
