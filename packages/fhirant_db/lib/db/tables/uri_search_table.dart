import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// URI Search Parameter Table
class UriSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();

  /// The URI value, stored as text
  TextColumn get uriValue => text()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};

  /// Index URI value for improved search performance
  List<Column<String>> get indexedColumns => [uriValue];
}

extension UriSearchParametersExtension on fhir.FhirBase {
  List<UriSearchParametersCompanion> toUriSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final results = <UriSearchParametersCompanion>[];

    switch (this) {
      case fhir.FhirUrl url:
        if (url.valueString != null) {
          results.add(UriSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            uriValue: Value(_normalizeUri(url.valueString!.toString())),
          ));
        }
        return results;

      case fhir.FhirCanonical canonical:
        if (canonical.valueString != null) {
          results.add(UriSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            uriValue: Value(_normalizeUri(canonical.valueString!.toString())),
          ));
        }
        return results;

      case fhir.FhirUri uri:
        if (uri.valueString != null) {
          results.add(UriSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),
            uriValue: Value(_normalizeUri(uri.valueString!.toString())),
          ));
        }
        return results;

      // If it's not one of the known types, return empty
      default:
        return [];
    }
  }

  /// Normalize URI for consistent searching
  String _normalizeUri(String input) {
    // Basic normalization for URIs

    // Remove trailing slashes
    var normalized =
        input.endsWith('/') ? input.substring(0, input.length - 1) : input;

    try {
      // Parse as URI to handle more complex normalization
      final uri = Uri.parse(normalized);

      // Build normalized URI with consistent casing for scheme and host
      if (uri.scheme.isNotEmpty && uri.host.isNotEmpty) {
        normalized = '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}';

        // Add port if non-standard
        if (uri.port != 80 && uri.port != 443 && uri.port != 0) {
          normalized += ':${uri.port}';
        }

        // Add path, query and fragment
        if (uri.path.isNotEmpty) {
          normalized += uri.path;
        }

        if (uri.query.isNotEmpty) {
          normalized += '?${uri.query}';
        }

        if (uri.fragment.isNotEmpty) {
          normalized += '#${uri.fragment}';
        }
      }
    } catch (e) {
      // If URI parsing fails, just return the input with minimal normalization
      print('Error normalizing URI: $e');
    }

    return normalized;
  }
}
