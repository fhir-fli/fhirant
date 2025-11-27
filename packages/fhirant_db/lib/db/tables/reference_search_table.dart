import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// Enhanced Reference Search Parameter Table
class ReferenceSearchParameters extends Table {
  TextColumn get resourceType => text()();
  TextColumn get id => text()();
  DateTimeColumn get lastUpdated => dateTime()();
  TextColumn get searchPath => text()();
  IntColumn get paramIndex => integer()();

  /// Original reference string as it appears in the resource
  TextColumn get referenceValue => text()();

  /// Parsed reference components
  TextColumn get referenceResourceType => text().nullable()();
  TextColumn get referenceIdPart => text().nullable()();
  TextColumn get referenceVersion => text().nullable()();
  TextColumn get referenceBaseUrl => text().nullable()();

  /// For identifier-based references (only applies to `fhir.Reference`)
  TextColumn get identifierSystem => text().nullable()();
  TextColumn get identifierValue => text().nullable()();

  @override
  Set<Column> get primaryKey => {resourceType, id, searchPath, paramIndex};

  /// Index columns commonly used in searching
  List<Column<String>> get indexedColumns => [
        referenceResourceType,
        referenceIdPart,
        identifierSystem,
        identifierValue,
      ];
}

extension ReferenceSearchParametersExtension on fhir.FhirBase {
  /// Produce one or more [ReferenceSearchParametersCompanion] entries
  /// if `this` is a [fhir.Reference] or [fhir.FhirCanonical].
  ///
  /// Otherwise, returns an empty list.
  List<ReferenceSearchParametersCompanion> toReferenceSearchParameter(
    String resourceType,
    String id,
    DateTime lastUpdated,
    String searchPath,
    int? paramIndex,
  ) {
    final results = <ReferenceSearchParametersCompanion>[];

    switch (this) {
      case fhir.Reference ref:
        // 1) Parse the reference string (e.g., "Patient/123", absolute URLs, etc.)
        final referenceComponents = _parseReference(ref.reference?.valueString);

        // 2) Build the companion object
        results.add(
          ReferenceSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),

            // Actual reference string
            referenceValue: ref.reference?.valueString == null
                ? const Value.absent()
                : Value(ref.reference!.valueString!),

            // Parsed reference components
            referenceResourceType: referenceComponents.resourceType == null
                ? const Value.absent()
                : Value(referenceComponents.resourceType!),
            referenceIdPart: referenceComponents.id == null
                ? const Value.absent()
                : Value(referenceComponents.id!),
            referenceVersion: referenceComponents.version == null
                ? const Value.absent()
                : Value(referenceComponents.version!),
            referenceBaseUrl: referenceComponents.baseUrl == null
                ? const Value.absent()
                : Value(referenceComponents.baseUrl!),

            // For identifier-based references
            identifierSystem: ref.identifier?.system?.valueString == null
                ? const Value.absent()
                : Value(ref.identifier!.system!.valueString!.toString()),
            identifierValue: ref.identifier?.value?.valueString == null
                ? const Value.absent()
                : Value(ref.identifier!.value!.valueString!),
          ),
        );

      case fhir.FhirCanonical canonical:
        // 1) Parse the canonical string. It's often a URL with optional version
        //    e.g.: "http://example.org/fhir/StructureDefinition/MyStruct|1.2.3"
        //    We'll reuse the same _parseReference function for a consistent breakdown.
        final referenceComponents =
            _parseReference(canonical.valueString?.toString());

        // 2) Build the companion
        results.add(
          ReferenceSearchParametersCompanion(
            resourceType: Value(resourceType),
            id: Value(id),
            lastUpdated: Value(lastUpdated),
            searchPath: Value(searchPath),
            paramIndex:
                paramIndex == null ? const Value.absent() : Value(paramIndex),

            // The canonical's actual string
            referenceValue: canonical.valueString == null
                ? const Value.absent()
                : Value(canonical.valueString!.toString()),

            // We attempt to fill referenceResourceType, referenceIdPart, etc.
            referenceResourceType: referenceComponents.resourceType == null
                ? const Value.absent()
                : Value(referenceComponents.resourceType!),
            referenceIdPart: referenceComponents.id == null
                ? const Value.absent()
                : Value(referenceComponents.id!),
            referenceVersion: referenceComponents.version == null
                ? const Value.absent()
                : Value(referenceComponents.version!),
            referenceBaseUrl: referenceComponents.baseUrl == null
                ? const Value.absent()
                : Value(referenceComponents.baseUrl!),

            // Canonicals do not have an identifier object, so we leave these absent.
            identifierSystem: const Value.absent(),
            identifierValue: const Value.absent(),
          ),
        );

      // If `this` is not a `Reference` or `FhirCanonical`, do nothing
      default:
        return results;
    }

    return results;
  }

  /// Attempts to parse a reference/canonical string into sub-components
  /// (e.g., resource type, ID, version, baseUrl).
  ReferenceComponents _parseReference(String? referenceString) {
    if (referenceString == null || referenceString.isEmpty) {
      return ReferenceComponents();
    }

    // 1) Check for absolute URLs: "http://example.org/Patient/123"
    if (referenceString.startsWith('http')) {
      final uri = Uri.parse(referenceString);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2) {
        return ReferenceComponents(
          baseUrl:
              '${uri.scheme}://${uri.authority}${uri.path.substring(0, uri.path.indexOf(pathSegments[pathSegments.length - 2]))}',
          resourceType: pathSegments[pathSegments.length - 2],
          id: pathSegments[pathSegments.length - 1],
        );
      }
    }

    // 2) Handle versioned references, e.g. "Patient/123/_history/1"
    if (referenceString.contains('/_history/')) {
      final parts = referenceString.split('/_history/');
      final version = parts.length > 1 ? parts[1] : null;
      final resourceParts = parts[0].split('/');
      if (resourceParts.length >= 2) {
        return ReferenceComponents(
          resourceType: resourceParts[resourceParts.length - 2],
          id: resourceParts[resourceParts.length - 1],
          version: version,
        );
      }
    }

    // 3) Simple references "Patient/123"
    final parts = referenceString.split('/');
    if (parts.length == 2) {
      return ReferenceComponents(
        resourceType: parts[0],
        id: parts[1],
      );
    }

    // 4) ID-only references "123"
    //    or Canonical references that don't match typical patterns
    if (!referenceString.contains('/')) {
      return ReferenceComponents(
        id: referenceString,
      );
    }

    // If none of the above patterns matched, just return an empty
    // or partially filled object.
    return ReferenceComponents();
  }
}

/// Simple class to hold the parsed reference fields
class ReferenceComponents {
  final String? resourceType;
  final String? id;
  final String? version;
  final String? baseUrl;

  ReferenceComponents({
    this.resourceType,
    this.id,
    this.version,
    this.baseUrl,
  });
}
