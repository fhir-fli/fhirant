// ignore_for_file: public_member_api_docs, lines_longer_than_80_chars, unnecessary_statements, avoid_dynamic_calls, unintended_html_in_doc_comment
import 'dart:convert';
import 'dart:io';
// ignore: always_use_package_imports
import 'package:fhir_r4/fhir_r4.dart';

/// This map translates a FHIR SearchParameter "type" (e.g. "token", "string")
/// into (listName, extensionFunctionName).
///
/// Example: "token" → ("tokenParams", "toTokenSearchParameter").
const Map<String, (String listName, String extensionFn)> typeToFunctionMap = {
  'token': ('tokenParams', 'toTokenSearchParameter'),
  'string': ('stringParams', 'toStringSearchParameter'),
  'reference': ('referenceParams', 'toReferenceSearchParameter'),
  'date': ('dateParams', 'toDateSearchParameter'),
  'number': ('numberParams', 'toNumberSearchParameter'),
  'quantity': ('quantityParams', 'toQuantitySearchParameter'),
  'uri': ('uriParams', 'toUriSearchParameter'),
  // If there's any other type (e.g., "composite", "special", etc.), add here:
  'composite': ('compositeParams', 'toCompositeSearchParameter'),
  'special': ('specialParams', 'toSpecialSearchParameter'),
};

/// The main function that generates Dart code from `search-parameters.json`.
void main() {
  // 1) Load and parse the JSON file
  final rawJson = File('search-parameters.json').readAsStringSync();
  final searchParamsRoot = jsonDecode(rawJson);

  // A map of resourceType -> a list of (expression, type)
  final expressions = <String, List<(String, String)>>{};

  // 2) Initialize expressions[resourceType] = [] for all resourceTypes
  for (final t in R4ResourceType.typesAsStrings) {
    expressions[makeDartClass(t)] = [];
  }

  // 3) Extract (expression, type) from each entry in the JSON
  for (final entry in searchParamsRoot['entry'] as List<dynamic>) {
    final resource = entry['resource'];
    final expression = resource['expression'] as String?;
    final type = resource['type'] as String?;
    if (expression == null || type == null) continue;

    // Some search parameters have multiple expressions separated by ' | '
    final expressionList = expression.split(' | ');
    for (final exp in expressionList) {
      // Split on '.' to isolate "where(...)" calls as separate segments
      final segments = exp.split('.');
      if (segments.isEmpty) continue;

      // The first segment is typically the resource type, e.g. "Account"
      final resourceType = segments[0];
      // If it's not a known resource type in R4, skip
      if (!R4ResourceType.typesAsStrings.contains(resourceType)) {
        continue;
      }

      // Store (exp, type) under the resourceType
      expressions[makeDartClass(resourceType)]!.add((exp, type));
    }
  }

  // 4) Build the Dart code
  final sb = StringBuffer()
    ..writeln('// ignore_for_file: dead_null_aware_expression')
    ..writeln('// Generated from FHIR R4 SearchParameter definitions\n')
    ..writeln("import 'package:fhir_r4/fhir_r4.dart' as fhir;\n")
    ..writeln("import 'package:fhirant_db/fhirant_db.dart';")
    ..writeln('extension MakeIterable on fhir.FhirBase {')
    ..writeln('  /// Returns an iterable of the given type.')
    ..writeln('  Iterable<T> makeIterable<T extends fhir.FhirBase>() {')
    ..writeln('    return <T>[this as T];')
    ..writeln('  }')
    ..writeln('}\n')
    ..writeln('extension MakeIterableList on Iterable<fhir.FhirBase?> {')
    ..writeln('  /// Returns an iterable of the given type.')
    ..writeln('  Iterable<T> makeIterable<T extends fhir.FhirBase>() {')
    ..writeln('    return whereType<T>();')
    ..writeln('  }')
    ..writeln('}\n')
    ..writeln('class SearchParameterLists {')
    ..writeln('final stringParams = <StringSearchParametersCompanion>[];')
    ..writeln('final tokenParams = <TokenSearchParametersCompanion>[];')
    ..writeln('final referenceParams = <ReferenceSearchParametersCompanion>[];')
    ..writeln('final dateParams = <DateSearchParametersCompanion>[];')
    ..writeln('final numberParams = <NumberSearchParametersCompanion>[];')
    ..writeln('final quantityParams = <QuantitySearchParametersCompanion>[];')
    ..writeln('final uriParams = <UriSearchParametersCompanion>[];')
    ..writeln(
        ' final compositeParams = <CompositeSearchParametersCompanion>[];')
    ..writeln('final specialParams = <SpecialSearchParametersCompanion>[];')
    ..writeln('}\n')
    ..writeln(
        'SearchParameterLists updateSearchParameters(fhir.Resource resource) {')
    ..writeln('  final resourceType = resource.runtimeType.toString();')
    ..writeln('  final id = resource.id.toString();')
    ..writeln(
        '  final lastUpdated = resource.meta!.lastUpdated!.valueDateTime!;')
    ..writeln(' int i = 0;')
    ..writeln('  final searchParameterLists = SearchParameterLists();')
    ..writeln('  switch (resource) {');

  // For each resource type
  for (final t in R4ResourceType.typesAsStrings) {
    final dartResourceType = makeDartClass(t);
    final expressionList = expressions[dartResourceType];
    if (expressionList == null || expressionList.isEmpty) continue;

    sb.writeln('    case fhir.$dartResourceType _: ');

    // For each (expression, type) in that resource
    for (final exp in expressionList.toSet()) {
      final (rawExpression, paramType) = exp;

      // 1) Figure out which extension function + which companion list
      //    we default to something if the map doesn't recognize the paramType
      final (listName, extensionFn) =
          typeToFunctionMap[paramType] ?? ('unknownParams', 'toUnknownParam');

      // 2) The code that accesses the property, e.g.
      //    "resource.identifier?.makeIterable<fhir.Identifier>()"
      final accessor = buildDartAccessor(exp);

      // 3) Turn "Account.identifier" etc. into the searchPath parameter
      final searchPath = rawExpression;

      // 4) Write comment line for clarity
      sb.writeln('      // $rawExpression ($paramType)');

      // 5) Generate a for-loop
      //    Also note the fallback: we try to parse the <fhir.Something> from the accessor
      //    so we can do something like `?? <fhir.Something>[]`.
      final iterableType = extractIterableType(accessor);

      sb.writeln('i = 0;');
      sb.writeln(
          '      for (final entry in ${_resourceTypeToResource(accessor)} ?? <$iterableType>[]) {');
      sb.writeln('        searchParameterLists.$listName.addAll(');
      sb.writeln('          entry.$extensionFn(');
      final safePath =
          searchPath.contains("'") ? '"$searchPath"' : "'$searchPath'";
      sb.writeln("            resourceType, id, lastUpdated, $safePath, i,");
      sb.writeln('          ),');
      sb.writeln('        );');
      sb.writeln('        i++;');
      sb.writeln('      }');
    }

    sb.writeln('      break;');
  }

  sb.writeln('  }'); // switch end
  sb.writeln(' return searchParameterLists;');
  sb.writeln('}'); // function end

  // 5) Post-process the generated code (an example of a special fix)
  var finalDartCode = sb.toString();
  finalDartCode = finalDartCode.replaceAll(
    'resource.deceasedX?.exists() and Patient?.deceased != false ?? <fhir.FhirBase>[]',
    '[fhir.FhirBoolean(resource.deceasedX != null && resource.deceasedBoolean?.value != false)]',
  );

  // 6) Write to disk
  File('search_parameters.dart').writeAsStringSync(finalDartCode);
}

/// This function is the same as your old one but now we know
/// we're generating code to be used inside a for-loop. We still
/// build a chain of accessors.
String buildDartAccessor((String, String) searchParameter) {
  final segments = searchParameter.$1.split('.');
  if (segments.isEmpty) return '';
  segments[0] = makeDartClass(segments[0]);
  final sb = StringBuffer();
  var isList = false;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final priorPath = segments.sublist(0, i).join('.');
    final fhirField = resolveSimplePath(priorPath);
    if (fhirField == null) {
      if (i == 0) {
        // The first segment is typically something like "Account"
        sb.write(segment);
        if (segments.length == 1) {
          sb.write('.makeIterable<fhir.$segment>()');
        }
      } else {
        if (isList) {
          final thisFhirField = resolveSimplePath(priorPath
              .split('.')
              .sublist(0, priorPath.split('.').length - 1)
              .join('.'));

          sb.write(
              '?.map((e) => e?.${fhirFieldToDartName(segment)})?.makeIterable<fhir.${thisFhirField!.type}>()');
        } else if (segment.contains('[')) {
          final firstSegment = segment.split('[').first;
          sb.write('.$firstSegment?.firstOrNull');
        } else {
          final thisField = resolveSimplePath('$priorPath.$segment');
          final safeSeg = thisField?.type == 'X' ? '${segment}X' : segment;
          sb.write('?.${fhirFieldToDartName(safeSeg)}');
          if (safeSeg == 'resource' && i == segments.length - 1) {
            sb.write('?.makeIterable<fhir.Resource>()');
          }
          if (thisField != null) {
            final thisType =
                inCasePolymorphic(thisField.type, segment, segments);
            if (thisType.isFhirPrimitive || i == segments.length - 1) {
              sb.write('?.makeIterable<fhir.$thisType>()');
            }
          }
        }
      }
      continue;
    }
    isList = isList || fhirField.isList;

    final pattern = RegExp(r'where\(resolve\(\) is (.+)\)');
    if (pattern.hasMatch(segment)) {
      // e.g. "subject.where(resolve() is Patient)"
      final whereSegments = segment.split(' ');
      final type = whereSegments[whereSegments.length - 1].split(')')[0];
      if (i != 0 && isList) {
        sb.write(
            '${whereIsType(type)}?.makeIterable<fhir.${fhirField.type}>()');
      } else {
        sb.write(
            '?.makeIterable<fhir.${fhirField.type}>()${whereIsType(type)}');
      }
      isList = true;
    } else {
      final patternType = RegExp(r"where\(type='(.+)'\)");
      if (patternType.hasMatch(segment)) {
        final match = patternType.firstMatch(segment);
        final type = match?.group(1);
        if (type == null) {
          throw Exception('Type not found in $segment');
        }

        if (i != 0 && isList) {
          sb.write(whereEquals('type', type));
        } else {
          final thisField = fhirFieldMap[fhirField.type]?[segment];
          var thisType = thisField?.type;
          if (thisType == null) {
            throw Exception('Type not found in $segment');
          }
          final safeSeg = thisType == 'X' ? '${segment}X' : segment;
          thisType = inCasePolymorphic(thisType, segment, segments);
          sb.write(
            '.${fhirFieldToDartName(safeSeg)}.makeIterable<fhir.$thisType>()${whereEquals('type', type)}',
          );
        }
        isList = true;
      } else {
        final patternSystem = RegExp(r"where\(system='(.+)'\)");
        if (patternSystem.hasMatch(segment)) {
          final match = patternSystem.firstMatch(segment);
          final type = match?.group(1);
          if (type == null) {
            throw Exception('Type not found in $segment');
          }

          if (i != 0 && isList) {
            sb.write(whereEquals('system', type));
            if (i == segments.length - 1) {
              final thisFhirField = resolveSimplePath(priorPath);
              sb.write('?.makeIterable<fhir.${thisFhirField!.type}>()');
            }
          } else {
            final thisField = fhirFieldMap[fhirField.type]?[segment];
            var thisType = thisField?.type;
            if (thisType == null) {
              throw Exception('Type not found in $segment');
            }
            final safeSeg = thisType == 'X' ? '${segment}X' : segment;
            thisType = inCasePolymorphic(thisType, segment, segments);
            sb.write(
              '.${fhirFieldToDartName(safeSeg)}.makeIterable<fhir.$thisType>()${whereEquals('system', type)}',
            );
          }
          isList = true;
        } else if (isList) {
          // Already in a list context
          final thisField = fhirFieldMap[fhirField.type]?[segment];
          if (thisField == null) {
            throw Exception('Field not found in $segment');
          }
          final thisType = inCasePolymorphic(thisField.type, segment, segments);
          final safeSeg = thisField.type == 'X' ? '${segment}X' : segment;
          if (thisField.isList) {
            sb.write(
              '?.expand((e) => e?.${fhirFieldToDartName(safeSeg)} ?? <fhir.$thisType>[])',
            );
            if (i == segments.length - 1) {
              sb.write('?.makeIterable<fhir.$thisType>()');
            }
          } else {
            sb.write(
              '?.map<fhir.$thisType?>((e) => e?.${fhirFieldToDartName(safeSeg)})',
            );
            if (i == segments.length - 1) {
              sb.write('?.makeIterable<fhir.$thisType>()');
            }
          }
        } else {
          final patternAs = RegExp(r'as\((.+)\)');
          if (patternAs.hasMatch(segment)) {
            final asType = _firstLetterToUpperCase(
              segment.split('as(').last.split(')').first,
            );
            final tempSb = sb.toString();
            sb
              ..clear()
              ..write('${tempSb.substring(0, tempSb.length - 1)}$asType');
            sb.write('?.makeIterable<fhir.${asType.toNamedDartType}>()');
          } else {
            final thisField = fhirFieldMap[fhirField.type]?[segment];
            final safeSeg = thisField?.type == 'X' ? '${segment}X' : segment;
            sb.write('?.${fhirFieldToDartName(safeSeg)}');
            if (thisField != null && i == segments.length - 1) {
              final thisType =
                  inCasePolymorphic(thisField.type, segment, segments);
              sb.write('?.makeIterable<fhir.$thisType>()');
            }
          }
        }
      }
    }
  }
  return sb.toString();
}

/// If we see something like:
///   .makeIterable<fhir.Identifier>()
/// we parse out "Identifier" so we can produce:
///   ?? <fhir.Identifier>[]
///
/// If we find an expansion fallback:
///   expand((e) => e.manifestation ?? <fhir.CodeableConcept>[])
/// we'll detect the "<fhir.CodeableConcept>" part so we can produce
///   ?? <fhir.CodeableConcept>[]
///
/// Otherwise, we default to "fhir.FhirBase".
/// If we see ".makeIterable<fhir.Identifier>()" or ".makeIterable<fhir.Reference>()"
/// we'll return "fhir.Identifier" or "fhir.Reference" for the fallback. Otherwise "fhir.FhirBase".
String extractIterableType(String accessorCode) {
  // Looks for something like:  .makeIterable<fhir.Reference>()
  // or:                        .makeIterable<fhir.Identifier>()
  final match =
      RegExp(r'\.makeIterable<fhir\.([\w?]+)>').firstMatch(accessorCode);
  if (match != null) {
    // e.g. "Reference" or "Reference?" if it had a question mark
    final rawType = match.group(1) ?? 'FhirBase';
    return 'fhir.${rawType.replaceAll('?', '')}';
  }

  // If none found, default:
  return 'fhir.FhirBase';
}

String inCasePolymorphic(String type, String segment, List<String> segments) {
  if (type == 'X') {
    // Find the containing type by walking through the field map
    String containingType = '';
    String currentType = segments[0]; // Start with the resource type

    for (int i = 1; i < segments.length; i++) {
      if (segments[i] == segment) {
        // We've found our segment, so the currentType is the containing type
        containingType = currentType;
        break;
      }

      // Look up the next type in the hierarchy
      final fields = fhirFieldMap[currentType];
      if (fields == null) break;

      final field = fields[segments[i]];
      if (field == null) break;

      currentType = field.type;
    }

    // If we found the containing type, use it. Otherwise, fall back to the resource type
    final typeToAppend =
        containingType.isNotEmpty ? containingType : segments[0];
    return '${_firstLetterToUpperCase(segment)}X$typeToAppend';
  }
  return type;
}

/// For certain resource types like "Group", "Endpoint", "List",
/// we prefix them with "Fhir" to become "FhirGroup", "FhirEndpoint", etc.
String makeDartClass(String type) =>
    ['Group', 'Endpoint', 'List'].contains(type) ? 'Fhir$type' : type;

/// If we see something like: ".where(resolve() is Patient)",
/// generate code that checks if the reference is to 'Patient'.
String whereIsType(String type) => '''
?.where((e) {
    final ref = e?.reference?.toString().split('/') ?? [];
    return ref.length > 1 && ref[ref.length - 2] == '$type';
  })''';

/// If we see ".where(type='foo')", generate code that checks if e?.type?.value is 'foo'.
String whereEquals(String field, String type) =>
    "?.where((e) => e?.$field?.value.toString() == '$type')";

/// `_resourceTypeToResource` used to replace the first segment with `resource`,
/// for lines like `Account.identifier` → `resource.identifier`.
String _resourceTypeToResource(String s) {
  final firstSegment = s.split('.').first;
  return s.replaceFirst(firstSegment, 'resource');
}

String _firstLetterToUpperCase(String s) {
  return s[0].toUpperCase() + s.substring(1);
}

/// Converts a FHIR field name to a Dart-safe field name (avoid keywords).
String fhirFieldToDartName(String field) => const <String>[
      'abstract',
      'else',
      'import',
      'show',
      'as',
      'enum',
      'in',
      'static',
      'assert',
      'export',
      'interface',
      'super',
      'async',
      'extends',
      'is',
      'switch',
      'await',
      'extension',
      'late',
      'sync',
      'break',
      'external',
      'library',
      'this',
      'case',
      'factory',
      'mixin',
      'throw',
      'catch',
      'false',
      'new',
      'true',
      'class',
      'final',
      'null',
      'try',
      'const',
      'finally',
      'on',
      'typedef',
      'continue',
      'for',
      'operator',
      'var',
      'covariant',
      'function',
      'part',
      'void',
      'default',
      'get',
      'required',
      'while',
      'deferred',
      'hide',
      'rethrow',
      'with',
      'do',
      'if',
      'return',
      'yield',
      'dynamic',
      'implements',
      'set',
    ].contains(field)
        ? '${field}_'
        : field;
