// ignore_for_file: lines_longer_than_80_chars, avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_secure_storage/fhirant_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

part 'fhirant_db.g.dart';

@DriftDatabase(tables: [
  Logs,
  Resources,
  ResourcesHistory,
  NumberSearchParameters,
  DateSearchParameters,
  StringSearchParameters,
  TokenSearchParameters,
  QuantitySearchParameters,
  ReferenceSearchParameters,
  CompositeSearchParameters,
  UriSearchParameters,
  SpecialSearchParameters,
])

/// Database for the application
class FhirAntDb extends _$FhirAntDb {
  /// Creates an instance of the database
  FhirAntDb() : super(_openConnection());

  /// Named constructor for testing.
  FhirAntDb.forTesting(super.e);

  /// Default database version for migrations
  @override
  int get schemaVersion => 1;

  /// Secure Storage Service instance
  static final SecureStorageService _secureStorageService =
      SecureStorageService();

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      // 1. Get the correct directory for storing databases on Android (or iOS).
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(dir.path, 'fhirant.db');

      // 2. Ensure SQLCipher is set up
      await setupSqlCipher();

      // 3. Retrieve the encryption key
      final encryptionKey = await _secureStorageService.getEncryptionKey();
      if (encryptionKey == null) {
        throw Exception('Failed to retrieve encryption key.');
      }

      // 4. Initialize the encrypted database
      return NativeDatabase(
        File(dbPath),
        setup: (rawDb) {
          rawDb.execute('PRAGMA key = "$encryptionKey";');

          // Recommended SQLCipher setting
          rawDb.config.doubleQuotedStringLiterals = false;

          // Debug check to ensure SQLCipher is working
          assert(
            _debugCheckHasCipher(rawDb),
            'SQLCipher encryption is not enabled. Verify the setup.',
          );
        },
      );
    });
  }

  /// Debug check to ensure SQLCipher is available
  static bool _debugCheckHasCipher(sqlite3.Database database) {
    try {
      return database.select('PRAGMA cipher_version;').isNotEmpty;
    } catch (e) {
      print('SQLCipher not available: $e');
      return false;
    }
  }

  Future<fhir.Resource?> getResource(
      fhir.R4ResourceType resourceType, String id) async {
    final resourceTypeString = resourceType.toString();
    final query = select(resources)
      ..where((tbl) =>
          tbl.resourceType.equals(resourceTypeString) & tbl.id.equals(id));
    final resourceRow = await query.getSingleOrNull();

    if (resourceRow == null) return null;

    return fhir.Resource.fromJsonString(resourceRow.resource);
  }

  Future<bool> saveResource(fhir.Resource resource) async {
    try {
      final newResource =
          resource.newIdIfNoId().updateVersion(versionIdAsTime: true);

      // Upsert to main Resources table: ensures latest version is stored
      await into(resources).insertOnConflictUpdate(ResourcesCompanion(
        resourceType: Value(resource.resourceType.toString()),
        id: Value(newResource.id!.valueString!),
        resource: Value(newResource.toJsonString()),
        lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
      ));

      // Append the new version to the ResourcesHistory table
      await into(resourcesHistory).insertOnConflictUpdate(ResourcesHistoryCompanion(
        resourceType: Value(resource.resourceType.toString()),
        id: Value(newResource.id!.valueString!),
        resource: Value(newResource.toJsonString()),
        lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
      ));
      final updated = await _updateSearchParameters(newResource);
      return true && updated;
    } catch (e) {
      print('Error in saveResource: $e');
      return false;
    }
  }

  Future<bool> _updateSearchParameters(fhir.Resource resource) async {
    try {
      final searchParams = updateSearchParameters(resource);
      await batch((batch) {
        final resourceType = resource.resourceType.toString();
        final id = resource.id!.valueString!;

        // Delete from all search parameter tables
        batch.deleteWhere(stringSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(tokenSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(referenceSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(dateSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(numberSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(quantitySearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(uriSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(compositeSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));
        batch.deleteWhere(specialSearchParameters,
            (tbl) => tbl.resourceType.equals(resourceType) & tbl.id.equals(id));

        // Insert all search parameters
        if (searchParams.stringParams.isNotEmpty) {
          batch.insertAll(stringSearchParameters, searchParams.stringParams);
        }
        if (searchParams.tokenParams.isNotEmpty) {
          batch.insertAll(tokenSearchParameters, searchParams.tokenParams);
        }
        if (searchParams.referenceParams.isNotEmpty) {
          batch.insertAll(
              referenceSearchParameters, searchParams.referenceParams);
        }
        if (searchParams.dateParams.isNotEmpty) {
          batch.insertAll(dateSearchParameters, searchParams.dateParams);
        }
        if (searchParams.numberParams.isNotEmpty) {
          batch.insertAll(numberSearchParameters, searchParams.numberParams);
        }
        if (searchParams.quantityParams.isNotEmpty) {
          batch.insertAll(
              quantitySearchParameters, searchParams.quantityParams);
        }
        if (searchParams.uriParams.isNotEmpty) {
          batch.insertAll(uriSearchParameters, searchParams.uriParams);
        }
        if (searchParams.compositeParams.isNotEmpty) {
          batch.insertAll(
              compositeSearchParameters, searchParams.compositeParams);
        }
        if (searchParams.specialParams.isNotEmpty) {
          batch.insertAll(specialSearchParameters, searchParams.specialParams);
        }
      });
      return true;
    } catch (e) {
      print('Error updating search parameters: $e');
      return false;
    }
  }

  /// Save multiple FHIR resources in a single batch.
  Future<bool> saveResources(List<fhir.Resource> resourcesList) async {
    try {
      final List<fhir.Resource> newResources = [];
      await batch((batch) {
        final List<ResourcesCompanion> resourceCompanions = [];
        final List<ResourcesHistoryCompanion> historyCompanions = [];

        for (final resource in resourcesList) {
          final newResource =
              resource.newIdIfNoId().updateVersion(versionIdAsTime: true);
          newResources.add(newResource);
          resourceCompanions.add(
            ResourcesCompanion(
              resourceType: Value(resource.resourceType.toString()),
              id: Value(newResource.id!.valueString!),
              resource: Value(newResource.toJsonString()),
              lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
            ),
          );
          historyCompanions.add(
            ResourcesHistoryCompanion(
              resourceType: Value(resource.resourceType.toString()),
              id: Value(newResource.id!.valueString!),
              resource: Value(newResource.toJsonString()),
              lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
            ),
          );
        }

        batch.insertAllOnConflictUpdate(resources, resourceCompanions);
        batch.insertAllOnConflictUpdate(resourcesHistory, historyCompanions);
      });

      final updated = await _updateSearchParametersBulk(newResources);
      return true && updated;
    } catch (e) {
      print('Error in saveResources: $e');
      return false;
    }
  }

  Future<bool> _updateSearchParametersBulk(
      List<fhir.Resource> resources) async {
    try {
      final resourceIdentifiers = resources
          .map((r) => (type: r.resourceType.toString(), id: r.id!.valueString!))
          .toList();
      final searchParameterLists = SearchParameterLists();
      for (final resource in resources) {
        final searchParams = updateSearchParameters(resource);
        searchParameterLists.stringParams.addAll(searchParams.stringParams);
        searchParameterLists.tokenParams.addAll(searchParams.tokenParams);
        searchParameterLists.referenceParams
            .addAll(searchParams.referenceParams);
        searchParameterLists.dateParams.addAll(searchParams.dateParams);
        searchParameterLists.numberParams.addAll(searchParams.numberParams);
        searchParameterLists.quantityParams.addAll(searchParams.quantityParams);
        searchParameterLists.uriParams.addAll(searchParams.uriParams);
        searchParameterLists.compositeParams
            .addAll(searchParams.compositeParams);
        searchParameterLists.specialParams.addAll(searchParams.specialParams);
      }
      await batch((batch) {
        for (final identifier in resourceIdentifiers) {
          // Delete from all search parameter tables
          batch.deleteWhere(
              stringSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              tokenSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              referenceSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              dateSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              numberSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              quantitySearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              uriSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              compositeSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
          batch.deleteWhere(
              specialSearchParameters,
              (tbl) =>
                  tbl.resourceType.equals(identifier.type) &
                  tbl.id.equals(identifier.id));
        }

        // Insert all search parameters
        if (searchParameterLists.stringParams.isNotEmpty) {
          batch.insertAll(
              stringSearchParameters, searchParameterLists.stringParams);
        }
        if (searchParameterLists.tokenParams.isNotEmpty) {
          batch.insertAll(
              tokenSearchParameters, searchParameterLists.tokenParams);
        }
        if (searchParameterLists.referenceParams.isNotEmpty) {
          batch.insertAll(
              referenceSearchParameters, searchParameterLists.referenceParams);
        }
        if (searchParameterLists.dateParams.isNotEmpty) {
          batch.insertAll(
              dateSearchParameters, searchParameterLists.dateParams);
        }
        if (searchParameterLists.numberParams.isNotEmpty) {
          batch.insertAll(
              numberSearchParameters, searchParameterLists.numberParams);
        }
        if (searchParameterLists.quantityParams.isNotEmpty) {
          batch.insertAll(
              quantitySearchParameters, searchParameterLists.quantityParams);
        }
        if (searchParameterLists.uriParams.isNotEmpty) {
          batch.insertAll(uriSearchParameters, searchParameterLists.uriParams);
        }
        if (searchParameterLists.compositeParams.isNotEmpty) {
          batch.insertAll(
              compositeSearchParameters, searchParameterLists.compositeParams);
        }
        if (searchParameterLists.specialParams.isNotEmpty) {
          batch.insertAll(
              specialSearchParameters, searchParameterLists.specialParams);
        }
      });
      return true;
    } catch (e) {
      print('Error updating search parameters in bulk: $e');
      return false;
    }
  }

  Future<bool> deleteResource(
      fhir.R4ResourceType resourceType, String id) async {
    final resourceTypeString = resourceType.toString();
    // Delete from the main table only.
    final count = await (delete(resources)
          ..where((tbl) =>
              tbl.resourceType.equals(resourceTypeString) & tbl.id.equals(id)))
        .go();
    return count > 0;
  }

  /// Retrieve a paginated list of resources of a given type.
  Future<List<fhir.Resource>> getResourcesWithPagination({
    required fhir.R4ResourceType resourceType,
    required int count,
    required int offset,
  }) async {
    final resourceTypeString = resourceType.toString();
    final query = (select(resources)
      ..where((tbl) => tbl.resourceType.equals(resourceTypeString))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastUpdated)])
      ..limit(count, offset: offset));
    final rows = await query.get();
    return rows
        .map((row) => fhir.Resource.fromJsonString(row.resource))
        .toList();
  }

  /// Retrieve all resources of a given type.
  Future<List<fhir.Resource>> getResourcesByType(
      fhir.R4ResourceType resourceType) async {
    final resourceTypeString = resourceType.toString();
    final query = (select(resources)
      ..where((tbl) => tbl.resourceType.equals(resourceTypeString))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastUpdated)]));
    final rows = await query.get();
    return rows
        .map((row) => fhir.Resource.fromJsonString(row.resource))
        .toList();
  }

  /// Return a count of resources for a given type.
  Future<int> getResourceCount(fhir.R4ResourceType resourceType) async {
    final resourceTypeString = resourceType.toString();
    // Create a count expression on the id column.
    final countExp = resources.id.count();
    final query = selectOnly(resources)
      ..addColumns([countExp])
      ..where(resources.resourceType.equals(resourceTypeString));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Retrieve a list of distinct resource types currently stored.
  Future<List<fhir.R4ResourceType>> getResourceTypes() async {
    // Using a custom select to get distinct resource types.
    final results = await customSelect(
      'SELECT DISTINCT resource_type FROM resources;',
      readsFrom: {resources},
    ).get();

    // Adjust the column name if drift-generated name is different.
    final resourceTypeStrings =
        results.map((row) => row.data['resource_type'] as String).toList();

    final resourceTypes = <fhir.R4ResourceType>[];
    for (final resourceTypeString in resourceTypeStrings) {
      final resourceType = fhir.R4ResourceType.fromString(resourceTypeString);
      if (resourceType != null) {
        resourceTypes.add(resourceType);
      } else {
        print('Unknown resource type: $resourceTypeString');
      }
    }
    return resourceTypes;
  }

  Future<List<fhir.Resource>> getResourceHistory(
      fhir.R4ResourceType resourceType, String id) async {
    final resourceTypeString = resourceType.toString();
    final query = select(resourcesHistory)
      ..where((tbl) =>
          tbl.resourceType.equals(resourceTypeString) & tbl.id.equals(id))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastUpdated)]);

    final rows = await query.get();
    return rows.map((row) {
      return fhir.Resource.fromJsonString(row.resource);
    }).toList();
  }

  /// Search resources using search parameters
  Future<List<fhir.Resource>> search({
    required fhir.R4ResourceType resourceType,
    Map<String, List<String>>? searchParameters,
    int? count,
    int? offset,
    List<String>? sort,
  }) async {
    final resourceTypeString = resourceType.toString();

    // Start with all resources of this type
    Set<String> matchingIds = {};
    bool firstParam = true;

    // Process each search parameter (skip if none provided)
    if (searchParameters != null && searchParameters.isNotEmpty) {
    for (final entry in searchParameters.entries) {
      final paramName = entry.key;
      final paramValues = entry.value;

      // Handle special parameters
      if (paramName == '_id') {
        final ids = paramValues.expand((v) => v.split(',')).toSet();
        if (firstParam) {
          matchingIds = ids;
        } else {
          matchingIds = matchingIds.intersection(ids);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_lastUpdated') {
        // _lastUpdated searches the meta.lastUpdated field directly from resources table
        final lastUpdatedIds = await _searchLastUpdatedParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = lastUpdatedIds;
        } else {
          matchingIds = matchingIds.intersection(lastUpdatedIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_tag') {
        // _tag searches meta.tag field
        final tagIds = await _searchTagParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = tagIds;
        } else {
          matchingIds = matchingIds.intersection(tagIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_profile') {
        // _profile searches meta.profile field
        final profileIds = await _searchProfileParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = profileIds;
        } else {
          matchingIds = matchingIds.intersection(profileIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_security') {
        // _security searches meta.security field
        final securityIds = await _searchSecurityParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = securityIds;
        } else {
          matchingIds = matchingIds.intersection(securityIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_source') {
        // _source searches meta.source field
        final sourceIds = await _searchSourceParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = sourceIds;
        } else {
          matchingIds = matchingIds.intersection(sourceIds);
        }
        firstParam = false;
        continue;
      }

      // Determine parameter type and search accordingly
      bool isDateParam = false;
      bool isTokenParam = false;
      bool isNumberParam = false;
      bool isQuantityParam = false;
      bool isUriParam = false;
      bool isReferenceParam = false;
      bool isCompositeParam = false;

      // Check for composite parameter (value contains $)
      // Example: code-value-quantity=8480-6$gt100
      for (final val in paramValues) {
        if (val.contains('\$') && paramName.contains('-')) {
          isCompositeParam = true;
          break;
        }
      }

      // Check for reference chaining (paramName contains '.')
      // Example: organization.name means search organization reference's name field
      bool isChainedReference = paramName.contains('.');

      // Check if value looks like a reference (must contain / like ResourceType/id)
      if (!isDateParam &&
          !isNumberParam &&
          !isQuantityParam &&
          !isTokenParam &&
          !isUriParam) {
        for (final val in paramValues) {
          final valWithoutModifier = val.split(':')[0];
          // Reference must be: ResourceType/id format
          if (RegExp(r'^[A-Z][a-zA-Z]+/[^/]+$')
                  .hasMatch(valWithoutModifier)) {
            isReferenceParam = true;
            break;
          }
        }
      }

      for (final val in paramValues) {
        final valWithoutModifier = val.split(':')[0];

        // Check for token (contains | or :missing without date/number context)
        if (val.contains('|') && !valWithoutModifier.contains('|')) {
          // Token format: system|value
          isTokenParam = true;
        } else if (val.contains('|') &&
            valWithoutModifier.split('|').length >= 2) {
          // Could be quantity: value|unit or system|value|unit
          final parts = valWithoutModifier.split('|');
          // If middle part is numeric, it's likely quantity
          try {
            double.parse(parts.length > 1 ? parts[1] : parts[0]);
            isQuantityParam = true;
          } catch (e) {
            isTokenParam = true;
          }
        }

        // Check for date modifiers
        if (val.contains(':gt') ||
            val.contains(':lt') ||
            val.contains(':ge') ||
            val.contains(':le') ||
            val.contains(':ap') ||
            val.contains(':sa') ||
            val.contains(':eb')) {
          // Check if it's a date pattern
          final datePattern = RegExp(r'^\d{4}(-\d{2})?(-\d{2})?(T.*)?$');
          if (datePattern.hasMatch(valWithoutModifier)) {
            isDateParam = true;
          } else {
            // Could be number/quantity with modifier
            try {
              double.parse(valWithoutModifier);
              isNumberParam = true;
            } catch (e) {
              // Not a number
            }
          }
        }

        // Check if value looks like a date
        if (!isDateParam && !isNumberParam && !isQuantityParam) {
          final datePattern = RegExp(r'^\d{4}(-\d{2})?(-\d{2})?(T.*)?$');
          if (datePattern.hasMatch(valWithoutModifier)) {
            isDateParam = true;
          }
        }

        // Check if value looks like a URI (starts with http://, https://, urn:, etc.)
        if (!isDateParam &&
            !isNumberParam &&
            !isQuantityParam &&
            !isTokenParam &&
            !isUriParam) {
          if (valWithoutModifier.startsWith('http://') ||
              valWithoutModifier.startsWith('https://') ||
              valWithoutModifier.startsWith('urn:') ||
              valWithoutModifier.startsWith('file://')) {
            isUriParam = true;
          }
        }
        // Check if value looks like a number (but not a date)
        if (!isDateParam &&
            !isNumberParam &&
            !isQuantityParam &&
            !isTokenParam) {
          try {
            double.parse(valWithoutModifier);
            // If param name suggests quantity (valueQuantity, etc.), treat as quantity
            if (paramName.toLowerCase().contains('quantity') ||
                paramName.toLowerCase().contains('value')) {
              isQuantityParam = true;
            } else {
              isNumberParam = true;
            }
          } catch (e) {
            // Not a number
          }
        }
      }

      Set<String> paramIds;
      if (isDateParam) {
        paramIds = await _searchDateParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isQuantityParam) {
        paramIds = await _searchQuantityParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isNumberParam) {
        paramIds = await _searchNumberParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isUriParam) {
        paramIds = await _searchUriParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isTokenParam) {
        paramIds = await _searchTokenParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isCompositeParam) {
        paramIds = await _searchCompositeParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isReferenceParam || isChainedReference) {
        paramIds = await _searchReferenceParameter(
          resourceTypeString,
          paramName,
          paramValues,
          isChainedReference,
        );
      } else {
        // Try string and token search tables (most common types)
        final stringIds = await _searchStringParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
        final tokenIds = await _searchTokenParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
        paramIds = stringIds.union(tokenIds);
      }

      if (firstParam) {
        matchingIds = paramIds;
        firstParam = false;
      } else {
        matchingIds = matchingIds.intersection(paramIds);
      }
    }
    }

    // If no search parameters were processed, get all resource IDs
    if (firstParam) {
      final allRows = await (select(resources)
        ..where((tbl) => tbl.resourceType.equals(resourceTypeString)))
        .get();
      matchingIds = allRows.map((r) => r.id).toSet();
    }

    // Retrieve the matching resources
    if (matchingIds.isEmpty) {
      return [];
    }

    final results = <fhir.Resource>[];
    for (final id in matchingIds) {
      final resource = await getResource(resourceType, id);
      if (resource != null) {
        results.add(resource);
      }
    }

    // Apply sorting if specified
    if (sort != null && sort.isNotEmpty) {
      results.sort((a, b) {
        for (final sortParam in sort) {
          final descending = sortParam.startsWith('-');
          final field = descending ? sortParam.substring(1) : sortParam;

          int comparison = 0;

          // Handle special fields
          if (field == '_id') {
            final aId = a.id?.toString() ?? '';
            final bId = b.id?.toString() ?? '';
            comparison = aId.compareTo(bId);
          } else if (field == '_lastUpdated') {
            final aDate = a.meta?.lastUpdated?.valueDateTime ?? DateTime(1970);
            final bDate = b.meta?.lastUpdated?.valueDateTime ?? DateTime(1970);
            comparison = aDate.compareTo(bDate);
          } else {
            // For other fields, try to extract from resource JSON
            // This is a simplified implementation - in production you'd want
            // to use FHIRPath or a more sophisticated field extraction
            try {
              final aJson =
                  jsonDecode(a.toJsonString()) as Map<String, dynamic>;
              final bJson =
                  jsonDecode(b.toJsonString()) as Map<String, dynamic>;

              // Try to find the field (supports dot notation like "name.family")
              dynamic aValue = _getNestedValue(aJson, field);
              dynamic bValue = _getNestedValue(bJson, field);

              if (aValue == null && bValue == null) {
                comparison = 0;
              } else if (aValue == null) {
                comparison = -1;
              } else if (bValue == null) {
                comparison = 1;
              } else {
                final aStr = aValue.toString();
                final bStr = bValue.toString();
                comparison = aStr.compareTo(bStr);
              }
            } catch (e) {
              // If field extraction fails, skip this sort parameter
              continue;
            }
          }

          if (comparison != 0) {
            return descending ? -comparison : comparison;
          }
        }
        return 0;
      });
    }

    // Apply pagination
    if (offset != null && offset > 0) {
      results.removeRange(0, offset > results.length ? results.length : offset);
    }
    if (count != null && count > 0) {
      if (results.length > count) {
        results.removeRange(count, results.length);
      }
    }

    return results;
  }
  /// Get count of resources matching search parameters
  /// This is more efficient than search() when you only need the count
  Future<int> searchCount({
    required fhir.R4ResourceType resourceType,
    Map<String, List<String>>? searchParameters,
  }) async {
    final resourceTypeString = resourceType.toString();

    // If no search parameters, use getResourceCount
    if (searchParameters == null || searchParameters.isEmpty) {
      return await getResourceCount(resourceType);
    }


    // Start with all resources of this type
    Set<String> matchingIds = {};
    bool firstParam = true;

    // Process each search parameter
    for (final entry in searchParameters.entries) {
      final paramName = entry.key;
      final paramValues = entry.value;

      // Handle special parameters
      if (paramName == '_id') {
        final ids = paramValues.expand((v) => v.split(',')).toSet();
        if (firstParam) {
          matchingIds = ids;
        } else {
          matchingIds = matchingIds.intersection(ids);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_lastUpdated') {
        // _lastUpdated searches the meta.lastUpdated field directly from resources table
        final lastUpdatedIds = await _searchLastUpdatedParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = lastUpdatedIds;
        } else {
          matchingIds = matchingIds.intersection(lastUpdatedIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_tag') {
        // _tag searches meta.tag field
        final tagIds = await _searchTagParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = tagIds;
        } else {
          matchingIds = matchingIds.intersection(tagIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_profile') {
        // _profile searches meta.profile field
        final profileIds = await _searchProfileParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = profileIds;
        } else {
          matchingIds = matchingIds.intersection(profileIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_security') {
        // _security searches meta.security field
        final securityIds = await _searchSecurityParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = securityIds;
        } else {
          matchingIds = matchingIds.intersection(securityIds);
        }
        firstParam = false;
        continue;
      }

      if (paramName == '_source') {
        // _source searches meta.source field
        final sourceIds = await _searchSourceParameter(
          resourceTypeString,
          paramValues,
        );
        if (firstParam) {
          matchingIds = sourceIds;
        } else {
          matchingIds = matchingIds.intersection(sourceIds);
        }
        firstParam = false;
        continue;
      }

      // Determine parameter type and search accordingly
      bool isDateParam = false;
      bool isTokenParam = false;
      bool isNumberParam = false;
      bool isQuantityParam = false;
      bool isUriParam = false;
      bool isReferenceParam = false;
      bool isCompositeParam = false;

      // Check for composite parameter (value contains $)
      // Example: code-value-quantity=8480-6$gt100
      for (final val in paramValues) {
        if (val.contains('\$') && paramName.contains('-')) {
          isCompositeParam = true;
          break;
        }
      }

      // Check for reference chaining (paramName contains '.')
      // Example: organization.name means search organization reference's name field
      bool isChainedReference = paramName.contains('.');

      // Check if value looks like a reference (must contain / like ResourceType/id)
      if (!isDateParam &&
          !isNumberParam &&
          !isQuantityParam &&
          !isTokenParam &&
          !isUriParam) {
        for (final val in paramValues) {
          final valWithoutModifier = val.split(':')[0];
          // Reference must be: ResourceType/id format
          if (RegExp(r'^[A-Z][a-zA-Z]+/[^/]+$')
                  .hasMatch(valWithoutModifier)) {
            isReferenceParam = true;
            break;
          }
        }
      }

      for (final val in paramValues) {
        final valWithoutModifier = val.split(':')[0];

        // Check for token (contains | or :missing without date/number context)
        if (val.contains('|') && !valWithoutModifier.contains('|')) {
          // Token format: system|value
          isTokenParam = true;
        } else if (val.contains('|') &&
            valWithoutModifier.split('|').length >= 2) {
          // Could be quantity: value|unit or system|value|unit
          final parts = valWithoutModifier.split('|');
          // If middle part is numeric, it's likely quantity
          try {
            double.parse(parts.length > 1 ? parts[1] : parts[0]);
            isQuantityParam = true;
          } catch (e) {
            isTokenParam = true;
          }
        }

        // Check for date modifiers
        if (val.contains(':gt') ||
            val.contains(':lt') ||
            val.contains(':ge') ||
            val.contains(':le') ||
            val.contains(':ap') ||
            val.contains(':sa') ||
            val.contains(':eb')) {
          // Check if it's a date pattern
          final datePattern = RegExp(r'^\d{4}(-\d{2})?(-\d{2})?(T.*)?$');
          if (datePattern.hasMatch(valWithoutModifier)) {
            isDateParam = true;
          } else {
            // Could be number/quantity with modifier
            try {
              double.parse(valWithoutModifier);
              isNumberParam = true;
            } catch (e) {
              // Not a number
            }
          }
        }

        // Check if value looks like a date
        if (!isDateParam && !isNumberParam && !isQuantityParam) {
          final datePattern = RegExp(r'^\d{4}(-\d{2})?(-\d{2})?(T.*)?$');
          if (datePattern.hasMatch(valWithoutModifier)) {
            isDateParam = true;
          }
        }

        // Check if value looks like a URI (starts with http://, https://, urn:, etc.)
        if (!isDateParam &&
            !isNumberParam &&
            !isQuantityParam &&
            !isTokenParam &&
            !isUriParam) {
          if (valWithoutModifier.startsWith('http://') ||
              valWithoutModifier.startsWith('https://') ||
              valWithoutModifier.startsWith('urn:') ||
              valWithoutModifier.startsWith('file://')) {
            isUriParam = true;
          }
        }
        // Check if value looks like a number (but not a date)
        if (!isDateParam &&
            !isNumberParam &&
            !isQuantityParam &&
            !isTokenParam) {
          try {
            double.parse(valWithoutModifier);
            // If param name suggests quantity (valueQuantity, etc.), treat as quantity
            if (paramName.toLowerCase().contains('quantity') ||
                paramName.toLowerCase().contains('value')) {
              isQuantityParam = true;
            } else {
              isNumberParam = true;
            }
          } catch (e) {
            // Not a number
          }
        }
      }

      Set<String> paramIds;
      if (isDateParam) {
        paramIds = await _searchDateParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isQuantityParam) {
        paramIds = await _searchQuantityParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isNumberParam) {
        paramIds = await _searchNumberParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isUriParam) {
        paramIds = await _searchUriParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isTokenParam) {
        paramIds = await _searchTokenParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isCompositeParam) {
        paramIds = await _searchCompositeParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
      } else if (isReferenceParam || isChainedReference) {
        paramIds = await _searchReferenceParameter(
          resourceTypeString,
          paramName,
          paramValues,
          isChainedReference,
        );
      } else {
        // Try string and token search tables (most common types)
        final stringIds = await _searchStringParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
        final tokenIds = await _searchTokenParameter(
          resourceTypeString,
          paramName,
          paramValues,
        );
        paramIds = stringIds.union(tokenIds);
      }

      if (firstParam) {
        matchingIds = paramIds;
        firstParam = false;
      } else {
        matchingIds = matchingIds.intersection(paramIds);
      }
    }

    // Retrieve the matching resources

    // Return count of matching IDs
    return matchingIds.length;
  }

  Future<Set<String>> _searchStringParameter(
    String resourceType,
    String searchPath,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers
      String? modifier;
      String searchValue = value;

      if (value.contains(':')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          searchValue = parts[0];
          modifier = parts[1];
        }
      }

      // Normalize the search value (same as stored)
      final normalizedValue = _normalizeString(searchValue);

      // Build query with all conditions in one where clause
      final query = select(stringSearchParameters);

      Expression<bool> whereCondition =
          stringSearchParameters.resourceType.equals(resourceType) &
              (stringSearchParameters.searchPath.like('$resourceType.$searchPath') |
               stringSearchParameters.searchPath.like('$resourceType.%.$searchPath'));

      if (modifier == 'exact') {
        whereCondition = whereCondition &
            stringSearchParameters.stringValue.equals(normalizedValue);
      } else if (modifier == 'contains') {
        whereCondition = whereCondition &
            stringSearchParameters.stringValue.like('%$normalizedValue%');
      } else if (modifier == 'missing') {
        // TODO: Handle missing modifier - need to check if parameter exists
        continue;
      } else {
        // Default: contains search (case-insensitive)
        whereCondition = whereCondition &
            stringSearchParameters.stringValue.like('%$normalizedValue%');
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Normalize string for search (case-insensitive, accent-insensitive)
  String _normalizeString(String input) {
    // Convert to lowercase and trim
    // Note: Full accent normalization would require package:intl or similar
    // For now, basic normalization - can be enhanced later
    return input.toLowerCase().trim();
  }

  /// Search using token search parameters
  Future<Set<String>> _searchTokenParameter(
    String resourceType,
    String searchPath,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers (skip if value contains | since : may be part of a URL in system|code)
      String? modifier;
      String searchValue = value;

      if (value.contains(':') && !value.contains('|')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          searchValue = parts[0];
          modifier = parts[1];
        }
      }

      // Handle missing modifier
      if (modifier == 'missing') {
        // Search for resources where this parameter is missing
        // This means no entry exists in tokenSearchParameters for this searchPath
        final allResourceIds = (await (select(resources)
                  ..where((tbl) => tbl.resourceType.equals(resourceType)))
                .get())
            .map((r) => r.id)
            .toSet();

        final resourcesWithParam = (await (selectOnly(tokenSearchParameters)
                  ..addColumns([tokenSearchParameters.id])
                  ..where(
                    tokenSearchParameters.resourceType.equals(resourceType) &
                        (tokenSearchParameters.searchPath.like('$resourceType.$searchPath') |
                         tokenSearchParameters.searchPath.like('$resourceType.%.$searchPath')),
                  ))
                .get())
            .map((r) => r.read(tokenSearchParameters.id)!)
            .toSet();

        matchingIds.addAll(allResourceIds.difference(resourcesWithParam));
        continue;
      }

      // Parse system|value format
      String? system;
      String tokenValue = searchValue;

      if (searchValue.contains('|')) {
        final parts = searchValue.split('|');
        if (parts.length == 2) {
          system = parts[0].isEmpty ? null : parts[0];
          tokenValue = parts[1];
        } else if (parts.length == 1 && searchValue.startsWith('|')) {
          // |value format - system is empty/null, just value
          system = null;
          tokenValue = parts[0];
        } else if (parts.length == 1 && searchValue.endsWith('|')) {
          // system| format - just system, no value
          system = parts[0];
          tokenValue = '';
        }
      }

      // Build query
      final query = select(tokenSearchParameters);

      Expression<bool> whereCondition =
          tokenSearchParameters.resourceType.equals(resourceType) &
              (tokenSearchParameters.searchPath.like('$resourceType.$searchPath') |
               tokenSearchParameters.searchPath.like('$resourceType.%.$searchPath'));

      if (system != null && system.isNotEmpty && tokenValue.isNotEmpty) {
        // system|value - both specified
        whereCondition = whereCondition &
            tokenSearchParameters.tokenSystem.equals(system) &
            tokenSearchParameters.tokenValue.equals(tokenValue);
      } else if (system != null && system.isNotEmpty) {
        // system| - only system specified
        whereCondition =
            whereCondition & tokenSearchParameters.tokenSystem.equals(system);
      } else if (tokenValue.isNotEmpty) {
        // value only - no system
        whereCondition = whereCondition &
            tokenSearchParameters.tokenValue.equals(tokenValue);
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Search using date search parameters
  Future<Set<String>> _searchDateParameter(
    String resourceType,
    String searchPath,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers
      String? modifier;
      String searchValue = value;

      if (value.contains(':')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          searchValue = parts[0];
          modifier = parts[1];
        }
      }

      // Handle missing modifier
      if (modifier == 'missing') {
        final allResourceIds = (await (select(resources)
                  ..where((tbl) => tbl.resourceType.equals(resourceType)))
                .get())
            .map((r) => r.id)
            .toSet();

        final resourcesWithParam = (await (selectOnly(dateSearchParameters)
                  ..addColumns([dateSearchParameters.id])
                  ..where(
                    dateSearchParameters.resourceType.equals(resourceType) &
                        (dateSearchParameters.searchPath.like('$resourceType.$searchPath') |
                         dateSearchParameters.searchPath.like('$resourceType.%.$searchPath')),
                  ))
                .get())
            .map((r) => r.read(dateSearchParameters.id)!)
            .toSet();

        matchingIds.addAll(allResourceIds.difference(resourcesWithParam));
        continue;
      }

      // Parse the date value
      late DateTime searchDate;
      try {
        // Try parsing as DateTime
        if (searchValue.contains('T')) {
          // DateTime format
          searchDate = DateTime.parse(searchValue);
        } else {
          // Date format - set to start of day
          final dateParts = searchValue.split('-');
          if (dateParts.length >= 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            searchDate = DateTime(year, month, day);
          } else if (dateParts.length == 2) {
            // Year-month format
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            searchDate = DateTime(year, month, 1);
          } else if (dateParts.length == 1) {
            // Year only
            final year = int.parse(dateParts[0]);
            searchDate = DateTime(year, 1, 1);
          } else {
            print('Invalid date format: $searchValue');
            continue;
          }
        }
      } catch (e) {
        print('Error parsing date: $searchValue - $e');
        continue;
      }

      // Build query based on modifier
      final query = select(dateSearchParameters);

      Expression<bool> whereCondition =
          dateSearchParameters.resourceType.equals(resourceType) &
              (dateSearchParameters.searchPath.like('$resourceType.$searchPath') |
               dateSearchParameters.searchPath.like('$resourceType.%.$searchPath'));

      switch (modifier) {
        case 'gt':
          // Greater than
          whereCondition = whereCondition &
              dateSearchParameters.dateValue.isBiggerThanValue(searchDate);
          break;
        case 'lt':
          // Less than
          whereCondition = whereCondition &
              dateSearchParameters.dateValue.isSmallerThanValue(searchDate);
          break;
        case 'ge':
          // Greater than or equal
          whereCondition = whereCondition &
              (dateSearchParameters.dateValue.isBiggerOrEqualValue(searchDate) |
                  dateSearchParameters.dateValue.equals(searchDate));
          break;
        case 'le':
          // Less than or equal
          whereCondition = whereCondition &
              (dateSearchParameters.dateValue
                      .isSmallerOrEqualValue(searchDate) |
                  dateSearchParameters.dateValue.equals(searchDate));
          break;
        case 'sa':
          // Starts after - date must be after searchDate
          whereCondition = whereCondition &
              dateSearchParameters.dateValue.isBiggerThanValue(searchDate);
          break;
        case 'eb':
          // Ends before - date must be before searchDate
          whereCondition = whereCondition &
              dateSearchParameters.dateValue.isSmallerThanValue(searchDate);
          break;
        case 'ap':
          // Approximately - within 1 day of searchDate
          final dayBefore = searchDate.subtract(const Duration(days: 1));
          final dayAfter = searchDate.add(const Duration(days: 1));
          whereCondition = whereCondition &
              (dateSearchParameters.dateValue.isBiggerOrEqualValue(dayBefore) &
                  dateSearchParameters.dateValue
                      .isSmallerOrEqualValue(dayAfter));
          break;
        default:
          // Default: equals or contains (for date ranges)
          // For exact match, check if dateValue equals searchDate
          // For ranges, we'd need to check if searchDate falls within the range
          // For now, do an exact match
          whereCondition = whereCondition &
              dateSearchParameters.dateValue.equals(searchDate);
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Search using _lastUpdated parameter (searches meta.lastUpdated directly)
  Future<Set<String>> _searchLastUpdatedParameter(
    String resourceType,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers
      String? modifier;
      String dateValue = value;

      if (value.contains(':')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          dateValue = parts[0];
          modifier = parts[1];
        }
      }

      // Parse the date value
      DateTime? searchDate;
      try {
        // Handle different date formats
        if (dateValue.length == 4) {
          // Year only: YYYY
          searchDate = DateTime(int.parse(dateValue));
        } else if (dateValue.length == 7) {
          // Year-Month: YYYY-MM
          final parts = dateValue.split('-');
          searchDate = DateTime(int.parse(parts[0]), int.parse(parts[1]));
        } else if (dateValue.length == 10) {
          // Date: YYYY-MM-DD
          final parts = dateValue.split('-');
          searchDate = DateTime(
              int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        } else if (dateValue.contains('T')) {
          // DateTime: YYYY-MM-DDTHH:MM:SS or with timezone
          searchDate = DateTime.parse(dateValue);
        } else {
          // Try parsing as-is
          searchDate = DateTime.parse(dateValue);
        }
      } catch (e) {
        // Invalid date format, skip this value
        continue;
      }

      // Build query on resources table
      final query = select(resources);

      Expression<bool> whereCondition =
          resources.resourceType.equals(resourceType);

      // Apply modifier
      if (modifier == null || modifier.isEmpty) {
        // Default: equals (exact match on the date part)
        // For date-only values, match any time on that date
        if (dateValue.length <= 10) {
          // Date precision: match any time on this date
          final startOfDay =
              DateTime(searchDate.year, searchDate.month, searchDate.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));
          whereCondition = whereCondition &
              (resources.lastUpdated.isBiggerOrEqualValue(startOfDay) &
                  resources.lastUpdated.isSmallerThanValue(endOfDay));
        } else {
          // DateTime precision: exact match
          whereCondition =
              whereCondition & resources.lastUpdated.equals(searchDate);
        }
      } else if (modifier == 'gt') {
        // Greater than
        whereCondition = whereCondition &
            resources.lastUpdated.isBiggerThanValue(searchDate);
      } else if (modifier == 'lt') {
        // Less than
        whereCondition = whereCondition &
            resources.lastUpdated.isSmallerThanValue(searchDate);
      } else if (modifier == 'ge') {
        // Greater than or equal
        whereCondition = whereCondition &
            resources.lastUpdated.isBiggerOrEqualValue(searchDate);
      } else if (modifier == 'le') {
        // Less than or equal
        whereCondition = whereCondition &
            resources.lastUpdated.isSmallerOrEqualValue(searchDate);
      } else if (modifier == 'ap') {
        // Approximately (within 1 day)
        final startDate = searchDate.subtract(const Duration(days: 1));
        final endDate = searchDate.add(const Duration(days: 1));
        whereCondition = whereCondition &
            (resources.lastUpdated.isBiggerOrEqualValue(startDate) &
                resources.lastUpdated.isSmallerOrEqualValue(endDate));
      } else if (modifier == 'sa') {
        // Starts after (same as gt)
        whereCondition = whereCondition &
            resources.lastUpdated.isBiggerThanValue(searchDate);
      } else if (modifier == 'eb') {
        // Ends before (same as lt)
        whereCondition = whereCondition &
            resources.lastUpdated.isSmallerThanValue(searchDate);
      } else {
        // Unknown modifier, skip
        continue;
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Search using _tag parameter (searches meta.tag from resource JSON)
  Future<Set<String>> _searchTagParameter(
    String resourceType,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    // Get all resources of this type
    final allResources = await (select(resources)
          ..where((tbl) => tbl.resourceType.equals(resourceType)))
        .get();

    for (final row in allResources) {
      try {
        final resourceJson = jsonDecode(row.resource) as Map<String, dynamic>;
        final meta = resourceJson['meta'] as Map<String, dynamic>?;
        if (meta == null) continue;

        final tags = meta['tag'] as List<dynamic>?;
        if (tags == null || tags.isEmpty) continue;

        // Check if any tag matches any of the search values
        bool matches = false;
        for (final value in values) {
          // Handle token format: system|code or just code
          final parts = value.split('|');
          final searchSystem = parts.length > 1 ? parts[0] : null;
          final searchCode = parts.length > 1 ? parts[1] : parts[0];

          for (final tag in tags) {
            final tagMap = tag as Map<String, dynamic>;
            final system = tagMap['system'] as String?;
            final code = tagMap['code'] as String?;

            if (searchSystem != null) {
              // Match system|code
              if (system == searchSystem && code == searchCode) {
                matches = true;
                break;
              }
            } else {
              // Match code only
              if (code == searchCode) {
                matches = true;
                break;
              }
            }
          }
          if (matches) break;
        }

        if (matches) {
          matchingIds.add(row.id);
        }
      } catch (e) {
        // Skip invalid JSON
        continue;
      }
    }

    return matchingIds;
  }

  /// Search using _profile parameter (searches meta.profile from resource JSON)
  Future<Set<String>> _searchProfileParameter(
    String resourceType,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    // Get all resources of this type
    final allResources = await (select(resources)
          ..where((tbl) => tbl.resourceType.equals(resourceType)))
        .get();

    for (final row in allResources) {
      try {
        final resourceJson = jsonDecode(row.resource) as Map<String, dynamic>;
        final meta = resourceJson['meta'] as Map<String, dynamic>?;
        if (meta == null) continue;

        final profiles = meta['profile'] as List<dynamic>?;
        if (profiles == null || profiles.isEmpty) continue;

        // Check if any profile matches any of the search values
        for (final value in values) {
          for (final profile in profiles) {
            final profileUri = profile is String ? profile : profile.toString();
            if (profileUri == value || profileUri.contains(value)) {
              matchingIds.add(row.id);
              break;
            }
          }
        }
      } catch (e) {
        // Skip invalid JSON
        continue;
      }
    }

    return matchingIds;
  }

  /// Search using _security parameter (searches meta.security from resource JSON)
  Future<Set<String>> _searchSecurityParameter(
    String resourceType,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    // Get all resources of this type
    final allResources = await (select(resources)
          ..where((tbl) => tbl.resourceType.equals(resourceType)))
        .get();

    for (final row in allResources) {
      try {
        final resourceJson = jsonDecode(row.resource) as Map<String, dynamic>;
        final meta = resourceJson['meta'] as Map<String, dynamic>?;
        if (meta == null) continue;

        final securities = meta['security'] as List<dynamic>?;
        if (securities == null || securities.isEmpty) continue;

        // Check if any security label matches any of the search values
        bool matches = false;
        for (final value in values) {
          // Handle token format: system|code or just code
          final parts = value.split('|');
          final searchSystem = parts.length > 1 ? parts[0] : null;
          final searchCode = parts.length > 1 ? parts[1] : parts[0];

          for (final security in securities) {
            final securityMap = security as Map<String, dynamic>;
            final system = securityMap['system'] as String?;
            final code = securityMap['code'] as String?;

            if (searchSystem != null) {
              // Match system|code
              if (system == searchSystem && code == searchCode) {
                matches = true;
                break;
              }
            } else {
              // Match code only
              if (code == searchCode) {
                matches = true;
                break;
              }
            }
          }
          if (matches) break;
        }

        if (matches) {
          matchingIds.add(row.id);
        }
      } catch (e) {
        // Skip invalid JSON
        continue;
      }
    }

    return matchingIds;
  }

  /// Search using _source parameter (searches meta.source from resource JSON)
  Future<Set<String>> _searchSourceParameter(
    String resourceType,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    // Get all resources of this type
    final allResources = await (select(resources)
          ..where((tbl) => tbl.resourceType.equals(resourceType)))
        .get();

    for (final row in allResources) {
      try {
        final resourceJson = jsonDecode(row.resource) as Map<String, dynamic>;
        final meta = resourceJson['meta'] as Map<String, dynamic>?;
        if (meta == null) continue;

        final source = meta['source'] as String?;
        if (source == null) continue;

        // Check if source matches any of the search values
        for (final value in values) {
          if (source == value || source.contains(value)) {
            matchingIds.add(row.id);
            break;
          }
        }
      } catch (e) {
        // Skip invalid JSON
        continue;
      }
    }

    return matchingIds;
  }

  /// Search using composite search parameters
  ///
  /// Composite parameters combine multiple search parameters with $ separator
  /// Example: code-value-quantity=8480-6\$gt100
  /// This searches for resources where code=8480-6 AND value-quantity>100
  Future<Set<String>> _searchCompositeParameter(
    String resourceType,
    String compositeParamName,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    // Parse composite parameter name (e.g., "code-value-quantity")
    final paramParts = compositeParamName.split('-');
    if (paramParts.length < 2) {
      // Not a valid composite parameter
      return matchingIds;
    }

    for (final value in values) {
      // Parse composite value (e.g., "8480-6\$gt100")
      final valueParts = value.split('\$');
      if (valueParts.length != paramParts.length) {
        // Mismatch between parameter parts and value parts
        continue;
      }

      // Build search for each component
      final componentResults = <Set<String>>[];

      for (int i = 0; i < paramParts.length; i++) {
        final componentParam = paramParts[i];
        final componentValue = valueParts[i];

        // Determine component parameter type and search
        Set<String> componentIds;

        // Try to determine type from value or parameter name
        bool isToken = componentValue.contains('|') ||
            componentParam.toLowerCase().contains('code') ||
            componentParam.toLowerCase().contains('status');
        bool isNumber = false;
        bool isQuantity = componentParam.toLowerCase().contains('quantity') ||
            componentParam.toLowerCase().contains('value');
        bool isDate = RegExp(r'^\d{4}').hasMatch(componentValue.split(':')[0]);

        try {
          double.parse(componentValue.split(':')[0]);
          isNumber = true;
          isQuantity =
              isQuantity || componentParam.toLowerCase().contains('value');
        } catch (e) {
          // Not a number
        }

        if (isToken) {
          componentIds = await _searchTokenParameter(
            resourceType,
            componentParam,
            [componentValue],
          );
        } else if (isQuantity) {
          componentIds = await _searchQuantityParameter(
            resourceType,
            componentParam,
            [componentValue],
          );
        } else if (isNumber) {
          componentIds = await _searchNumberParameter(
            resourceType,
            componentParam,
            [componentValue],
          );
        } else if (isDate) {
          componentIds = await _searchDateParameter(
            resourceType,
            componentParam,
            [componentValue],
          );
        } else {
          // Default to string search
          componentIds = await _searchStringParameter(
            resourceType,
            componentParam,
            [componentValue],
          );
        }

        componentResults.add(componentIds);
      }

      // Intersect all component results (AND logic)
      if (componentResults.isNotEmpty) {
        Set<String> intersection = componentResults[0];
        for (int i = 1; i < componentResults.length; i++) {
          intersection = intersection.intersection(componentResults[i]);
        }
        matchingIds.addAll(intersection);
      }
    }

    return matchingIds;
  }

  /// Search using reference search parameters (with optional chaining)
  ///
  /// Examples:
  /// - organization=Organization/123 (simple reference)
  /// - organization.name=Hospital (chained: search organization reference's name field)
  Future<Set<String>> _searchReferenceParameter(
    String resourceType,
    String searchPath,
    List<String> values,
    bool isChained,
  ) async {
    final matchingIds = <String>{};

    if (isChained) {
      // Handle chained reference search
      // Example: organization.name=Hospital
      // 1. Find the reference field (organization)
      // 2. Get the referenced resource IDs
      // 3. Search those resources for the chained field (name)
      // 4. Return the original resource IDs that reference the matching resources

      final parts = searchPath.split('.');
      if (parts.length < 2) {
        // Invalid chaining syntax
        return matchingIds;
      }

      final referenceField = parts[0]; // e.g., "organization"
      final chainedField = parts[1]; // e.g., "name"

      // Step 1: Find all resources that have this reference field
      final referenceParams = await (select(referenceSearchParameters)
            ..where(
              (tbl) =>
                  tbl.resourceType.equals(resourceType) &
                  (tbl.searchPath.like('$resourceType.$referenceField') |
                   tbl.searchPath.like('$resourceType.%.$referenceField')),
            ))
          .get();

      if (referenceParams.isEmpty) {
        return matchingIds;
      }

      // Step 2: Get the referenced resource IDs
      final referencedResourceIds = <String>{};
      final referencedResourceTypes = <String>{};

      for (final param in referenceParams) {
        if (param.referenceResourceType != null &&
            param.referenceIdPart != null) {
          referencedResourceTypes.add(param.referenceResourceType!);
          referencedResourceIds.add(param.referenceIdPart!);
        }
      }

      if (referencedResourceIds.isEmpty) {
        return matchingIds;
      }

      // Step 3: Search the referenced resources for the chained field
      // This is a simplified implementation - in production you'd want to
      // use the proper search parameter tables for the chained field
      final matchingReferencedIds = <String>{};

      for (final refType in referencedResourceTypes) {
        // Get resources of the referenced type
        final refResources = await (select(resources)
              ..where((tbl) => tbl.resourceType.equals(refType)))
            .get();

        // Search in the JSON for the chained field
        for (final row in refResources) {
          if (!referencedResourceIds.contains(row.id)) continue;

          try {
            final resourceJson =
                jsonDecode(row.resource) as Map<String, dynamic>;

            // Try to find the chained field value
            dynamic fieldValue = _getNestedValue(resourceJson, chainedField);

            if (fieldValue != null) {
              final fieldValueStr = fieldValue.toString().toLowerCase();

              // Check if any search value matches
              for (final value in values) {
                final searchValue = value.split(':')[0].toLowerCase();
                if (fieldValueStr.contains(searchValue) ||
                    fieldValueStr == searchValue) {
                  matchingReferencedIds.add(row.id);
                  break;
                }
              }
            }
          } catch (e) {
            // Skip invalid JSON
            continue;
          }
        }
      }

      // Step 4: Find original resources that reference the matching resources
      for (final param in referenceParams) {
        if (param.referenceIdPart != null &&
            matchingReferencedIds.contains(param.referenceIdPart!)) {
          matchingIds.add(param.id);
        }
      }
    } else {
      // Simple reference search (no chaining)
      // Example: organization=Organization/123 or organization=123
      for (final value in values) {
        final searchValue = value.split(':')[0];

        // Parse the reference value
        String? refType;
        String? refId;

        if (searchValue.contains('/')) {
          // Format: ResourceType/id
          final parts = searchValue.split('/');
          if (parts.length >= 2) {
            refType = parts[0];
            refId = parts[1];
          }
        } else {
          // Just an ID - search across all reference types
          refId = searchValue;
        }

        // Build query
        final query = select(referenceSearchParameters);
        Expression<bool> whereCondition =
            referenceSearchParameters.resourceType.equals(resourceType) &
                (referenceSearchParameters.searchPath.like('$resourceType.$searchPath') |
                 referenceSearchParameters.searchPath.like('$resourceType.%.$searchPath'));

        if (refType != null && refId != null) {
          // Match both type and ID
          whereCondition = whereCondition &
              referenceSearchParameters.referenceResourceType.equals(refType) &
              referenceSearchParameters.referenceIdPart.equals(refId);
        } else if (refId != null) {
          // Match just ID (any type)
          whereCondition = whereCondition &
              referenceSearchParameters.referenceIdPart.equals(refId);
        } else if (refType != null) {
          // Match just type
          whereCondition = whereCondition &
              referenceSearchParameters.referenceResourceType.equals(refType);
        }

        query.where((tbl) => whereCondition);

        final rows = await query.get();
        for (final row in rows) {
          matchingIds.add(row.id);
        }
      }
    }

    return matchingIds;
  }

  /// Search using number search parameters
  Future<Set<String>> _searchNumberParameter(
    String resourceType,
    String searchPath,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers
      String? modifier;
      String searchValue = value;

      if (value.contains(':')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          searchValue = parts[0];
          modifier = parts[1];
        }
      }

      // Handle missing modifier
      if (modifier == 'missing') {
        final allResourceIds = (await (select(resources)
                  ..where((tbl) => tbl.resourceType.equals(resourceType)))
                .get())
            .map((r) => r.id)
            .toSet();

        final resourcesWithParam = (await (selectOnly(numberSearchParameters)
                  ..addColumns([numberSearchParameters.id])
                  ..where(
                    numberSearchParameters.resourceType.equals(resourceType) &
                        (numberSearchParameters.searchPath.like('$resourceType.$searchPath') |
                         numberSearchParameters.searchPath.like('$resourceType.%.$searchPath')),
                  ))
                .get())
            .map((r) => r.read(numberSearchParameters.id)!)
            .toSet();

        matchingIds.addAll(allResourceIds.difference(resourcesWithParam));
        continue;
      }

      // Parse the number value
      double searchNumber;
      try {
        searchNumber = double.parse(searchValue);
      } catch (e) {
        print('Error parsing number: $searchValue - $e');
        continue;
      }

      // searchNumber is assigned in all code paths above

      // Build query based on modifier
      final query = select(numberSearchParameters);

      Expression<bool> whereCondition =
          numberSearchParameters.resourceType.equals(resourceType) &
              (numberSearchParameters.searchPath.like('$resourceType.$searchPath') |
               numberSearchParameters.searchPath.like('$resourceType.%.$searchPath'));

      switch (modifier) {
        case 'gt':
          whereCondition = whereCondition &
              numberSearchParameters.numberValue
                  .isBiggerThanValue(searchNumber);
          break;
        case 'lt':
          whereCondition = whereCondition &
              numberSearchParameters.numberValue
                  .isSmallerThanValue(searchNumber);
          break;
        case 'ge':
          whereCondition = whereCondition &
              (numberSearchParameters.numberValue
                      .isBiggerOrEqualValue(searchNumber) |
                  numberSearchParameters.numberValue.equals(searchNumber));
          break;
        case 'le':
          whereCondition = whereCondition &
              (numberSearchParameters.numberValue
                      .isSmallerOrEqualValue(searchNumber) |
                  numberSearchParameters.numberValue.equals(searchNumber));
          break;
        case 'ap':
          // Approximately - within 10% of searchNumber
          final tolerance = searchNumber * 0.1;
          final lowerBound = searchNumber - tolerance;
          final upperBound = searchNumber + tolerance;
          whereCondition = whereCondition &
              (numberSearchParameters.numberValue
                      .isBiggerOrEqualValue(lowerBound) &
                  numberSearchParameters.numberValue
                      .isSmallerOrEqualValue(upperBound));
          break;
        default:
          // Default: exact match
          whereCondition = whereCondition &
              numberSearchParameters.numberValue.equals(searchNumber);
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Search using quantity search parameters
  Future<Set<String>> _searchQuantityParameter(
    String resourceType,
    String searchPath,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers
      String? modifier;
      String searchValue = value;

      if (value.contains(':')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          searchValue = parts[0];
          modifier = parts[1];
        }
      }

      // Handle missing modifier
      if (modifier == 'missing') {
        final allResourceIds = (await (select(resources)
                  ..where((tbl) => tbl.resourceType.equals(resourceType)))
                .get())
            .map((r) => r.id)
            .toSet();

        final resourcesWithParam = (await (selectOnly(quantitySearchParameters)
                  ..addColumns([quantitySearchParameters.id])
                  ..where(
                    quantitySearchParameters.resourceType.equals(resourceType) &
                        (quantitySearchParameters.searchPath.like('$resourceType.$searchPath') |
                         quantitySearchParameters.searchPath.like('$resourceType.%.$searchPath')),
                  ))
                .get())
            .map((r) => r.read(quantitySearchParameters.id)!)
            .toSet();

        matchingIds.addAll(allResourceIds.difference(resourcesWithParam));
        continue;
      }

      // Parse quantity value - format can be: value, value|unit, system|value|unit, etc.
      double quantityValue;
      String? unit;
      String? system;

      try {
        if (searchValue.contains('|')) {
          final parts = searchValue.split('|');
          if (parts.length == 2) {
            // Try value|unit format first
            try {
              quantityValue = double.parse(parts[0]);
              unit = parts[1].isEmpty ? null : parts[1];
            } catch (e) {
              // Try system|value format
              system = parts[0].isEmpty ? null : parts[0];
              quantityValue = double.parse(parts[1]);
            }
          } else if (parts.length == 3) {
            // system|value|unit
            system = parts[0].isEmpty ? null : parts[0];
            quantityValue = double.parse(parts[1]);
            unit = parts[2].isEmpty ? null : parts[2];
          } else {
            print('Invalid quantity format: $searchValue');
            continue;
          }
        } else {
          // Just value
          quantityValue = double.parse(searchValue);
        }
      } catch (e) {
        print('Error parsing quantity: $searchValue - $e');
        continue;
      }

      // Build query based on modifier
      final query = select(quantitySearchParameters);

      Expression<bool> whereCondition =
          quantitySearchParameters.resourceType.equals(resourceType) &
              (quantitySearchParameters.searchPath.like('$resourceType.$searchPath') |
               quantitySearchParameters.searchPath.like('$resourceType.%.$searchPath'));

      // Add value comparison
      switch (modifier) {
        case 'gt':
          whereCondition = whereCondition &
              quantitySearchParameters.quantityValue
                  .isBiggerThanValue(quantityValue);
          break;
        case 'lt':
          whereCondition = whereCondition &
              quantitySearchParameters.quantityValue
                  .isSmallerThanValue(quantityValue);
          break;
        case 'ge':
          whereCondition = whereCondition &
              (quantitySearchParameters.quantityValue
                      .isBiggerOrEqualValue(quantityValue) |
                  quantitySearchParameters.quantityValue.equals(quantityValue));
          break;
        case 'le':
          whereCondition = whereCondition &
              (quantitySearchParameters.quantityValue
                      .isSmallerOrEqualValue(quantityValue) |
                  quantitySearchParameters.quantityValue.equals(quantityValue));
          break;
        case 'ap':
          // Approximately - within 10% of quantityValue
          final tolerance = quantityValue * 0.1;
          final lowerBound = quantityValue - tolerance;
          final upperBound = quantityValue + tolerance;
          whereCondition = whereCondition &
              (quantitySearchParameters.quantityValue
                      .isBiggerOrEqualValue(lowerBound) &
                  quantitySearchParameters.quantityValue
                      .isSmallerOrEqualValue(upperBound));
          break;
        default:
          // Default: exact match on value
          whereCondition = whereCondition &
              quantitySearchParameters.quantityValue.equals(quantityValue);
      }

      // Add unit/system filters if provided
      if (unit != null) {
        whereCondition =
            whereCondition & quantitySearchParameters.quantityUnit.equals(unit);
      }
      if (system != null) {
        whereCondition = whereCondition &
            quantitySearchParameters.quantitySystem.equals(system);
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Search using URI search parameters
  Future<Set<String>> _searchUriParameter(
    String resourceType,
    String searchPath,
    List<String> values,
  ) async {
    final matchingIds = <String>{};

    for (final value in values) {
      // Handle modifiers
      String? modifier;
      String searchValue = value;

      if (value.contains(':')) {
        final parts = value.split(':');
        if (parts.length == 2) {
          searchValue = parts[0];
          modifier = parts[1];
        }
      }

      // Handle missing modifier
      if (modifier == 'missing') {
        final allResourceIds = (await (select(resources)
                  ..where((tbl) => tbl.resourceType.equals(resourceType)))
                .get())
            .map((r) => r.id)
            .toSet();

        final resourcesWithParam = await (selectOnly(uriSearchParameters)
              ..addColumns([uriSearchParameters.id])
              ..where(
                uriSearchParameters.resourceType.equals(resourceType) &
                    (uriSearchParameters.searchPath.like('$resourceType.$searchPath') |
                     uriSearchParameters.searchPath.like('$resourceType.%.$searchPath')),
              ))
            .get()
            .then((rows) =>
                rows.map((r) => r.read(uriSearchParameters.id)!).toSet());

        matchingIds.addAll(allResourceIds.difference(resourcesWithParam));
        continue;
      }

      // URI search is typically exact match or prefix match
      final query = select(uriSearchParameters);

      Expression<bool> whereCondition =
          uriSearchParameters.resourceType.equals(resourceType) &
              (uriSearchParameters.searchPath.like('$resourceType.$searchPath') |
               uriSearchParameters.searchPath.like('$resourceType.%.$searchPath'));

      // URI search: exact match by default, or :above for prefix match
      if (modifier == 'above') {
        // Prefix match - URI starts with searchValue

        uriSearchParameters.uriValue.like('$searchValue%');
      } else {
        // Default: exact match
        whereCondition =
            whereCondition & uriSearchParameters.uriValue.equals(searchValue);
      }

      query.where((tbl) => whereCondition);

      final rows = await query.get();
      for (final row in rows) {
        matchingIds.add(row.id);
      }
    }

    return matchingIds;
  }

  /// Initialize the database (if needed).
  Future<void> initialize() async {
    // Since LazyDatabase opens the connection on first use,
    // you can run a simple query to ensure it is ready.
    await customSelect('SELECT 1').get();
  }

  /// Close the database connection.
  @override
  Future<void> close() async {
    await super.close();
  }

  /// Clear all resources (and history) from the database.
  Future<void> clear() async {
    await batch((batch) {
      // Delete all resources
      batch.deleteWhere(resources, (tbl) => const Constant(true));

      // Delete all resource history
      batch.deleteWhere(resourcesHistory, (tbl) => const Constant(true));

      // Delete all search parameters
      batch.deleteWhere(stringSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(tokenSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(
          referenceSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(dateSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(numberSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(
          quantitySearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(uriSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(
          compositeSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(specialSearchParameters, (tbl) => const Constant(true));

      // Note: Logs are intentionally NOT cleared to maintain audit trail
    });
  }

  /// Helper method to get nested value from JSON map using dot notation
  dynamic _getNestedValue(Map<String, dynamic> json, String path) {
    final parts = path.split('.');
    dynamic current = json;

    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
        if (current == null) return null;
      } else if (current is List) {
        // For arrays, get first element
        if (current.isNotEmpty && current[0] is Map<String, dynamic>) {
          current = (current[0] as Map<String, dynamic>)[part];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return current;
  }
}
