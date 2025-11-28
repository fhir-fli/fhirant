// ignore_for_file: lines_longer_than_80_chars, avoid_print
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
        resource: Value(newResource.resourceTypeString),
        lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
      ));

      // Append the new version to the ResourcesHistory table
      await into(resourcesHistory).insert(ResourcesHistoryCompanion(
        resourceType: Value(resource.resourceType.toString()),
        id: Value(newResource.id!.valueString!),
        resource: Value(newResource.resourceTypeString),
        lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
      ));
      final updated = await _updateSearchParameters(resource);
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
              resource: Value(newResource.resourceTypeString),
              lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
            ),
          );
          historyCompanions.add(
            ResourcesHistoryCompanion(
              resourceType: Value(resource.resourceType.toString()),
              id: Value(newResource.id!.valueString!),
              resource: Value(newResource.resourceTypeString),
              lastUpdated: Value(newResource.meta!.lastUpdated!.valueDateTime!),
            ),
          );
        }

        batch.insertAllOnConflictUpdate(resources, resourceCompanions);
        batch.insertAll(resourcesHistory, historyCompanions);
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

  Future<int> deleteResource(
      fhir.R4ResourceType resourceType, String id) async {
    final resourceTypeString = resourceType.toString();
    // Delete from the main table only.
    return (delete(resources)
          ..where((tbl) =>
              tbl.resourceType.equals(resourceTypeString) & tbl.id.equals(id)))
        .go();
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
  Future<void> clear() async {}
}
