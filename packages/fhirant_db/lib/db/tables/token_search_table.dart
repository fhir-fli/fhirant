import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Token Search Parameter Table
class TokenSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();

  /// The system part of the token; may be null if not provided
  TextColumn get tokenSystem => text().nullable()();

  /// The value (code or identifier)
  TextColumn get tokenValue => text()();

  /// Optional display value for human-readable searches
  TextColumn get tokenDisplay => text().nullable()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};

  /// Index token value and system for improved search performance
  List<Column> get indexedColumns => [tokenValue, tokenSystem];
}

extension TokenSearchParametersExtension on fhir.FhirBase {
  List<TokenSearchParametersCompanion> toTokenSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final results = <TokenSearchParametersCompanion>[];

    switch (this) {
      case fhir.FhirCodeEnum enumCode:
        if (enumCode.valueString != null) {
          results.add(TokenSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            tokenSystem: enumCode.system?.toString() != null
                ? Value(enumCode.system.toString())
                : const Value.absent(),
            tokenValue: Value(enumCode.valueString!.toString()),
            tokenDisplay: enumCode.display?.valueString != null
                ? Value(enumCode.display!.valueString!)
                : const Value.absent(),
          ));
        }
        return results;

      case fhir.FhirCode code:
        if (code.valueString != null) {
          results.add(TokenSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            tokenSystem: const Value.absent(),
            tokenValue: Value(code.valueString!),
            tokenDisplay: const Value.absent(),
          ));
        }
        return results;

      case fhir.Coding coding:
        if (coding.code?.valueString != null) {
          results.add(TokenSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            tokenSystem: coding.system?.valueString == null
                ? const Value.absent()
                : Value(coding.system!.valueString!.toString()),
            tokenValue: Value(coding.code!.valueString!),
            tokenDisplay: coding.display?.valueString == null
                ? const Value.absent()
                : Value(coding.display!.valueString!),
          ));
        }
        return results;

      case fhir.CodeableConcept codeableConcept:
        // Process each coding in the CodeableConcept
        final resultList = <TokenSearchParametersCompanion>[];

        if (codeableConcept.coding != null) {
          for (var i = 0; i < codeableConcept.coding!.length; i++) {
            final coding = codeableConcept.coding![i];
            if (coding.code?.valueString != null) {
              resultList.add(TokenSearchParametersCompanion(
                resourceType: Value(resourceType),
                id: Value(id),
                lastUpdated: Value(lastUpdated),
                searchPath: Value(searchPath),
                paramIndex: Value(paramIndex == null ? i : paramIndex * 100 + i),
                tokenSystem: coding.system?.valueString == null
                    ? const Value.absent()
                    : Value(coding.system!.valueString!.toString()),
                tokenValue: Value(coding.code!.valueString!),
                tokenDisplay: coding.display?.valueString == null
                    ? const Value.absent()
                    : Value(coding.display!.valueString!),
              ));
            }
          }
        }

        // Also add the text as a token if present
        if (codeableConcept.text?.valueString != null) {
          final textIndex = codeableConcept.coding?.length ?? 0;
          resultList.add(TokenSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex: Value(paramIndex == null ? textIndex : paramIndex * 100 + textIndex),
            tokenSystem: const Value.absent(),
            tokenValue: Value(codeableConcept.text!.valueString!),
            tokenDisplay: const Value.absent(),
          ));
        }

        return resultList;

      case fhir.Identifier identifier:
        if (identifier.value?.valueString != null) {
          results.add(TokenSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            tokenSystem: identifier.system?.valueString == null
                ? const Value.absent()
                : Value(identifier.system!.valueString!.toString()),
            tokenValue: Value(identifier.value!.valueString!),
            tokenDisplay: const Value.absent(),
          ));
        }
        return results;

      case fhir.FhirBoolean boolean:
        if (boolean.valueString != null) {
          results.add(TokenSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            tokenSystem: const Value.absent(),
            tokenValue: Value(boolean.valueString.toString()),
            tokenDisplay: const Value.absent(),
          ));
        }
        return results;

      // If it's not one of the known types, return empty
      default:
        return [];
    }
  }
}
