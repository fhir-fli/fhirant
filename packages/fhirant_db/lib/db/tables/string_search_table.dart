import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// String Search Parameter Table
class StringSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();

  /// Normalized string value for case- and accent-insensitive searches
  TextColumn get stringValue => text()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};

  /// Index string value for improved search performance
  List<Column<String>> get indexedColumns => [stringValue];
}

extension StringSearchParametersExtension on fhir.FhirBase {
  List<StringSearchParametersCompanion> toStringSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final results = <StringSearchParametersCompanion>[];

    switch (this) {
      case fhir.FhirString stringValue:
        if (stringValue.valueString != null) {
          results.add(StringSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            stringValue: Value(_normalizeString(stringValue.valueString!)),
          ));
        }
        return results;

      case fhir.HumanName humanName:
        // Extract given, family, prefix, suffix, text parts from HumanName
        final nameParts = <String>[];

        if (humanName.family?.valueString != null) {
          nameParts.add(humanName.family!.valueString!);
        }

        if (humanName.given != null) {
          for (final given in humanName.given!) {
            if (given.valueString != null) {
              nameParts.add(given.valueString!);
            }
          }
        }

        if (humanName.prefix != null) {
          for (final prefix in humanName.prefix!) {
            if (prefix.valueString != null) {
              nameParts.add(prefix.valueString!);
            }
          }
        }

        if (humanName.suffix != null) {
          for (final suffix in humanName.suffix!) {
            if (suffix.valueString != null) {
              nameParts.add(suffix.valueString!);
            }
          }
        }

        if (humanName.text?.valueString != null) {
          nameParts.add(humanName.text!.valueString!);
        }

        // Add all name parts as separate entries
        for (var i = 0; i < nameParts.length; i++) {
          results.add(StringSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex: Value(paramIndex ?? i),
            stringValue: Value(_normalizeString(nameParts[i])),
          ));
        }
        return results;

      case fhir.Address address:
        // Extract line, city, district, state, postalCode, country from Address
        final addressParts = <String>[];

        if (address.line != null) {
          for (final line in address.line!) {
            if (line.valueString != null) {
              addressParts.add(line.valueString!);
            }
          }
        }

        if (address.city?.valueString != null) {
          addressParts.add(address.city!.valueString!);
        }

        if (address.district?.valueString != null) {
          addressParts.add(address.district!.valueString!);
        }

        if (address.state?.valueString != null) {
          addressParts.add(address.state!.valueString!);
        }

        if (address.postalCode?.valueString != null) {
          addressParts.add(address.postalCode!.valueString!);
        }

        if (address.country?.valueString != null) {
          addressParts.add(address.country!.valueString!);
        }

        if (address.text?.valueString != null) {
          addressParts.add(address.text!.valueString!);
        }

        // Add all address parts as separate entries
        for (var i = 0; i < addressParts.length; i++) {
          results.add(StringSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex: Value(paramIndex ?? i),
            stringValue: Value(_normalizeString(addressParts[i])),
          ));
        }
        return results;

      case fhir.ContactPoint contactPoint:
        // For ContactPoint, we might want to index the.valueString
        if (contactPoint.value?.valueString != null) {
          results.add(StringSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            stringValue:
                Value(_normalizeString(contactPoint.value!.valueString!)),
          ));
        }
        return results;

      // If it's not one of the known types, return empty
      default:
        return [];
    }
  }

  /// Normalize string for case-insensitive and accent-insensitive searching
  String _normalizeString(String input) {
    // Convert to lowercase for case-insensitivity
    final normalized = input.toLowerCase();

    // TODO: Implement accent normalization if needed
    // This would depend on what libraries are available in Dart/Flutter
    // For example, you might replace accented characters with non-accented equivalents

    return normalized;
  }
}
