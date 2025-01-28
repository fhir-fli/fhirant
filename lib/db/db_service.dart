// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/services.dart';

/// Service to interact with the SQLite database
class DbService {
  /// Factory constructor for accessing the instance
  factory DbService() => _instance;

  /// Internal constructor
  DbService._();

  // Singleton instance
  static final DbService _instance = DbService._();

  // The actual database instance
  late final AppDatabase _db;

  /// Initialize the database
  Future<void> initialize() async {
    _db = AppDatabase();
  }

  /// Close the database connection
  void close() {
    try {
      _db.close();
    } catch (e) {
      print('Error closing database connection: $e');
    }
  }

  /// Fetch all resources of a specific type as strings
  Future<List<String>> getAllResourcesStrings(
    R4ResourceType resourceType,
  ) async {
    try {
      final table = getTableByType(resourceType, _db);

      final results = await _db.select(table).get();
      return results.map((row) {
        // ignore: avoid_dynamic_calls
        final resource = row.resource;
        if (resource is String) {
          return resource;
        } else {
          throw Exception('Invalid resource data for type $resourceType');
        }
      }).toList();
    } catch (e) {
      print('Error fetching resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch all resources of a specific type
  Future<List<Resource>> getAllResources(R4ResourceType resourceType) async {
    try {
      final resourceStrings = await getAllResourcesStrings(resourceType);
      return resourceStrings.map(Resource.fromJsonString).toList();
    } catch (e) {
      print('Error converting resources to FHIR objects: $e');
      return [];
    }
  }

  /// Fetch resources with pagination
  Future<List<Resource>> getResourcesWithPagination({
    required R4ResourceType resourceType,
    required int count,
    required int offset,
  }) async {
    try {
      final table = getTableByType(resourceType, _db);

      // Perform the paginated query
      final results =
          await (_db.select(table)..limit(count, offset: offset)).get();

      return results.map((row) {
        // ignore: avoid_dynamic_calls
        final resourceJson = row.resource;
        if (resourceJson is String) {
          return Resource.fromJsonString(resourceJson);
        } else {
          throw Exception(
            'Invalid resource data for type $resourceType: '
            'Expected String, got ${resourceJson.runtimeType}',
          );
        }
      }).toList();
    } catch (e) {
      print('Error retrieving paginated resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch a specific resource by its ID
  Future<Resource?> getResource(R4ResourceType resourceType, String id) async {
    try {
      final table = getTableByType(resourceType, _db);

      final primaryKeyColumn = table.$primaryKey.first;
      final query = _db.select(table)
        ..where((row) => primaryKeyColumn.equals(id));

      final results = await query.get();

      if (results.isNotEmpty) {
        // ignore: avoid_dynamic_calls
        final resourceJson = results.first.resource;
        if (resourceJson is String) {
          return Resource.fromJsonString(resourceJson);
        } else {
          throw Exception(
            'Invalid resource data for type $resourceType: '
            'Expected String, got ${resourceJson.runtimeType}',
          );
        }
      }
    } catch (e) {
      print('Error retrieving resource of type $resourceType with ID $id: $e');
    }
    return null;
  }

  /// Get a count of resources by type
  Future<int> getResourceCount(R4ResourceType resourceType) async {
    try {
      final table = getTableByType(resourceType, _db);

      // Use the primary key column dynamically
      final primaryKeyColumn = table.$primaryKey.first;
      final countExpression = primaryKeyColumn.count();

      final query = _db.selectOnly(table)..addColumns([countExpression]);
      final result = await query.getSingle();

      return result.read(countExpression) ?? 0;
    } catch (e) {
      print('Error counting resources of type $resourceType: $e');
      return 0;
    }
  }

  /// Export resources of a specific type to NDJSON and compress to .tar.gz
  Future<bool> exportResourcesToNDJSON(
    R4ResourceType resourceType,
    String filePath,
  ) async {
    try {
      final resources = await getAllResourcesStrings(resourceType);
      if (resources.isEmpty) {
        print('No resources found for type $resourceType.');
        return false;
      }

      var partitionIndex = 1;
      final stringBuffer = StringBuffer();
      final partitionedFiles = <String, String>{};

      for (var i = 0; i < resources.length; i++) {
        stringBuffer.writeln(resources[i]);

        if ((i + 1) % 10000 == 0 || i == resources.length - 1) {
          final fileName = '$resourceType-part$partitionIndex';
          partitionedFiles[fileName] = stringBuffer.toString();
          partitionIndex++;
          stringBuffer.clear();
        }
      }

      final compressedData = await FhirBulk.toTarGzFile(partitionedFiles);
      if (compressedData == null) {
        print('Failed to compress NDJSON files for type $resourceType.');
        return false;
      }

      await File(filePath).writeAsBytes(compressedData);
      print(
        'Resources of type $resourceType exported successfully to $filePath.',
      );
      return true;
    } catch (e) {
      print('Error exporting resources of type $resourceType to NDJSON: $e');
      return false;
    }
  }

  /// Update a resource in the database
  Future<bool> saveResource(Resource resource) async {
    try {
      await _db.saveResources([resource]);
      return true;
    } catch (e) {
      print('Error updating resource of type ${resource.resourceType}: $e');
      return false;
    }
  }

  /// Fetch all valid resource types with resources in the database
  Future<List<R4ResourceType>> getValidResourceTypes() async {
    final validTypes = <R4ResourceType>[];

    try {
      for (final resourceType in R4ResourceType.values) {
        final count = await getResourceCount(resourceType);
        if (count > 0) {
          validTypes.add(resourceType);
        }
      }
    } catch (e) {
      print('Error fetching valid resource types: $e');
    }

    return validTypes;
  }

  /// Load resources from assets with a specific prefix
  Future<List<String>> loadResourcesFromAssets(String prefix) async {
    print('loading resources from assets with prefix $prefix');
    final loadedResourceTypes = <String>[];

    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      final files = manifestMap.keys.where(
        (key) =>
            key.startsWith(prefix) &&
            (key.endsWith('.json') || key.endsWith('.ndjson')),
      );

      for (final file in files) {
        await _processFile(file);
        final resourceType =
            file.split('/').last.split('-').first; // Extract type
        if (!loadedResourceTypes.contains(resourceType)) {
          loadedResourceTypes.add(resourceType);
        }
      }

      print(
        'Successfully loaded ${loadedResourceTypes.length} '
        'resource type(s) from $prefix.',
      );
    } catch (e) {
      print('Error loading resources from assets with prefix $prefix: $e');
    }

    return loadedResourceTypes;
  }

  /// Process a single file and store resources in the database
  Future<void> _processFile(String file) async {
    final content = await rootBundle.loadString(file);

    if (file.endsWith('.ndjson')) {
      await _processNdjson(content);
    } else if (file.endsWith('.json')) {
      await _processJson(content);
    }
  }

  Future<void> _processNdjson(String content) async {
    final lines = content.split('\n').where((line) => line.isNotEmpty);
    final resources = lines.map(Resource.fromJsonString).toList();
    await _db.saveResources(resources);
  }

  Future<void> _processJson(String content) async {
    final resource = Resource.fromJsonString(content);
    if (resource is Bundle) {
      final bundleResources =
          resource.entry
              ?.map((entry) => entry.resource)
              .whereType<Resource>()
              .toList() ??
          [];
      await _db.saveResources(bundleResources);
    } else {
      await _db.saveResources([resource]);
    }
  }
}
