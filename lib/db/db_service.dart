// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

/// Service to interact with the SQLite database
class DbService {
  /// Factory constructor to return the singleton instance
  factory DbService() => _instance;

  /// Private constructor
  DbService._();

  static final DbService _instance = DbService._();
  static const _databaseName = 'fhir_clinical.db';
  late final Database _db;
  final SecureStorageService _secureStorageService = SecureStorageService();

  /// Initialize the database with encryption
  Future<void> initializeDatabase() async {
    try {
      final dbPath = path.join(Directory.current.path, _databaseName);
      _db = sqlite3.open(dbPath);

      // Retrieve encryption key from secure storage
      var encryptionKey = await _secureStorageService.getEncryptionKey();

      if (encryptionKey == null) {
        // Generate a key if it doesn't exist
        encryptionKey = _secureStorageService.generateRandomKey();
        await _secureStorageService.saveEncryptionKey(encryptionKey);
      }

      // Apply encryption
      _db.execute('PRAGMA key = "$encryptionKey";');

      // Ensure tables are created
      createTables(_db);
    } catch (e) {
      print('Error initializing database: $e');
      throw Exception('Failed to initialize the database');
    }
  }

  /// Save resources to the database, handling single and bulk inserts
  bool saveResources(List<Resource> resources) {
    if (resources.isEmpty) return true;

    try {
      _db.execute('BEGIN TRANSACTION;');

      final groupedResources = <R4ResourceType, List<Resource>>{};

      // Group resources by type
      for (final resource in resources) {
        groupedResources
            .putIfAbsent(resource.resourceType, () => [])
            .add(resource);
      }

      for (final entry in groupedResources.entries) {
        final saveFn = saveFunction(entry.key);
        for (final resource in entry.value) {
          saveFn(_db, resource);
        }
      }

      _db.execute('COMMIT;');
      return true;
    } catch (e) {
      _db.execute('ROLLBACK;');
      print('Error saving resources: $e');
      return false;
    }
  }

  /// Save a single resource using the unified save logic
  bool saveResource(Resource resource) {
    return saveResources([resource]);
  }

  /// Save multiple resources of the same type
  bool bulkSaveResourcesOfSameType<T extends Resource>(List<T> resources) {
    return saveResources(resources);
  }

  /// Save mixed resources
  bool bulkSaveMixedResources(List<Resource> resources) {
    return saveResources(resources);
  }

  /// Fetch all resources of a specific type
  List<String> getAllResourcesStrings(String resourceType) {
    try {
      final query = 'SELECT resource FROM $resourceType';
      final results = _db.select(query);
      return results.map((row) => row['resource'] as String).toList();
    } catch (e) {
      print('Error retrieving all resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch all resources of a specific type
  List<Resource> getAllResources(String resourceType) {
    try {
      final query = 'SELECT resource FROM $resourceType';
      final results = _db.select(query);
      return results.map((row) {
        final resourceJson = row['resource'] as String;
        return Resource.fromJsonString(resourceJson);
      }).toList();
    } catch (e) {
      print('Error retrieving all resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch resources with pagination
  List<Resource> getResourcesWithPagination({
    required String resourceType,
    required int count,
    required int offset,
  }) {
    try {
      final query = '''
        SELECT resource 
        FROM $resourceType 
        LIMIT ? OFFSET ?
      ''';

      final results = _db.select(query, [count, offset]);

      return results.map((row) {
        final resourceJson = row['resource'] as String;
        return Resource.fromJsonString(resourceJson);
      }).toList();
    } catch (e) {
      print('Error retrieving paginated resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch a specific resource by its ID
  Resource? getResource(String resourceType, String id) {
    try {
      final query = 'SELECT resource FROM $resourceType WHERE id = ?';
      final results = _db.select(query, [id]);

      if (results.isNotEmpty) {
        final resourceJson = results.first['resource'] as String;
        return Resource.fromJsonString(resourceJson);
      }
    } catch (e) {
      print('Error retrieving resource of type $resourceType with ID $id: $e');
    }
    return null;
  }

  /// Get a count of resources by type
  int getResourceCount(String resourceType) {
    try {
      final query = 'SELECT COUNT(*) AS count FROM $resourceType';
      final results = _db.select(query);
      if (results.isNotEmpty) {
        return results.first['count'] as int;
      }
    } catch (e) {
      print('Error counting resources of type $resourceType: $e');
    }
    return 0;
  }

  /// Export resources of a specific type to NDJSON and compress to .tar.gz
  Future<bool> exportResourcesToNDJSON(
    String resourceType,
    String filePath,
  ) async {
    try {
      // Retrieve resources as JSON strings from the database
      final resources = getAllResourcesStrings(resourceType);
      if (resources.isEmpty) {
        print('No resources found for type $resourceType.');
        return false;
      }

      // Partition resources into smaller files if needed
      // (10,000 resources per file)
      var partitionIndex = 1;
      final stringBuffer = StringBuffer();
      final partitionedFiles = <String, String>{};

      for (var i = 0; i < resources.length; i++) {
        stringBuffer.writeln(resources[i]);

        // Write a partition file after every 10,000 resources or at the end
        if ((i + 1) % 10000 == 0 || i == resources.length - 1) {
          final fileName = '$resourceType-part$partitionIndex';
          partitionedFiles[fileName] = stringBuffer.toString();
          partitionIndex++;
          stringBuffer.clear();
        }
      }

      // Compress partitioned NDJSON files into a .tar.gz archive
      final compressedData = await FhirBulk.toTarGzFile(partitionedFiles);
      if (compressedData == null) {
        print('Failed to compress NDJSON files for type $resourceType.');
        return false;
      }

      // Write the compressed data to the specified file path
      await File(filePath).writeAsBytes(compressedData);
      print('Resources of type $resourceType exported successfully '
          'to $filePath.');
      return true;
    } catch (e) {
      print('Error exporting resources of type $resourceType to NDJSON: $e');
      return false;
    }
  }

  /// Update a resource in the database
  bool updateResource(Resource resource) {
    try {
      final updateFn = saveFunction(resource.resourceType);
      return updateFn(_db, resource);
    } catch (e) {
      print('Error updating resource of type ${resource.resourceType}: $e');
      return false;
    }
  }

  /// Delete a resource by its ID
  bool deleteResource(String resourceType, String id) {
    try {
      final deleteQuery = 'DELETE FROM $resourceType WHERE id = ?';
      _db.execute(deleteQuery, [id]);
      return true;
    } catch (e) {
      print('Error deleting resource of type $resourceType with ID $id: $e');
      return false;
    }
  }

  /// Close the database connection
  void close() {
    try {
      _db.dispose();
    } catch (e) {
      print('Error closing database connection: $e');
    }
  }

  /// Fetch all valid resource types with resources in the database
  Future<List<String>> getValidResourceTypes() async {
    final validTypes = <String>[];

    try {
      for (final resourceType in R4ResourceType.typesAsStrings) {
        final adjustedType =
            ['Endpoint', 'Group', 'List'].contains(resourceType)
                ? 'Fhir$resourceType'
                : resourceType;

        final count = getResourceCount(adjustedType);
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

      print('Resources loaded from assets with prefix $prefix.');
    } catch (e) {
      print('Error loading resources from assets: $e');
    }

    return loadedResourceTypes;
  }

  /// Process a single file and store resources in the database
  Future<void> _processFile(String file) async {
    final content = await rootBundle.loadString(file);

    if (file.endsWith('.ndjson')) {
      _processNdjson(content);
    } else if (file.endsWith('.json')) {
      _processJson(content);
    }
  }

  void _processNdjson(String content) {
    final lines = content.split('\n').where((line) => line.isNotEmpty);
    final resources = lines.map(Resource.fromJsonString).toList();
    bulkSaveResourcesOfSameType(resources);
  }

  void _processJson(String content) {
    final resource = Resource.fromJsonString(content);
    if (resource is Bundle) {
      final bundleResources = resource.entry
              ?.map((entry) => entry.resource)
              .whereType<Resource>()
              .toList() ??
          [];
      bulkSaveMixedResources(bundleResources);
    } else {
      saveResource(resource);
    }
  }
}
