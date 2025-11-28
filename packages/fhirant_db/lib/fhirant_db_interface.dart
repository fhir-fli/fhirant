import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

class FhirAntDbInterface implements FuegoDbInterface {
  final FhirAntDb _db;

  FhirAntDbInterface(this._db);

  @override
  Future<fhir.Resource?> getResource(
      fhir.R4ResourceType resourceType, String id) async {
    try {
      return await _db.getResource(resourceType, id);
    } catch (e) {
      print('Error retrieving resource: $e');
      return null;
    }
  }

  @override
  Future<bool> saveResource(fhir.Resource resource) async {
    try {
      return await _db.saveResource(resource);
    } catch (e) {
      print('Error saving resource: $e');
      return false;
    }
  }

  @override
  Future<bool> saveResources(List<fhir.Resource> resources) async {
    try {
      return await _db.saveResources(resources);
    } catch (e) {
      print('Error saving resources: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteResource(
      fhir.R4ResourceType resourceType, String id) async {
    try {
      final result = await _db.deleteResource(resourceType, id);
      return result > 0;
    } catch (e) {
      print('Error deleting resource: $e');
      return false;
    }
  }

  @override
  Future<List<fhir.Resource>> getResourcesWithPagination({
    required fhir.R4ResourceType resourceType,
    required int count,
    required int offset,
  }) async {
    try {
      return await _db.getResourcesWithPagination(
        resourceType: resourceType,
        count: count,
        offset: offset,
      );
    } catch (e) {
      print('Error getting paginated resources: $e');
      return [];
    }
  }

  @override
  Future<List<fhir.Resource>> getResourcesByType(
      fhir.R4ResourceType resourceType) async {
    try {
      return await _db.getResourcesByType(resourceType);
    } catch (e) {
      print('Error getting resources by type: $e');
      return [];
    }
  }

  @override
  Future<int> getResourceCount(fhir.R4ResourceType resourceType) async {
    try {
      return await _db.getResourceCount(resourceType);
    } catch (e) {
      print('Error getting resource count: $e');
      return 0;
    }
  }

  @override
  Future<List<fhir.R4ResourceType>> getResourceTypes() async {
    try {
      return await _db.getResourceTypes();
    } catch (e) {
      print('Error getting resource types: $e');
      return [];
    }
  }

  @override
  Future<List<fhir.Resource>> getResourceHistory(
      fhir.R4ResourceType resourceType, String id) async {
    try {
      return await _db.getResourceHistory(resourceType, id);
    } catch (e) {
      print('Error getting resource history: $e');
      return [];
    }
  }

  @override
  Future<void> initialize() async {
    try {
      await _db.initialize();
    } catch (e) {
      print('Error initializing database: $e');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _db.close();
    } catch (e) {
      print('Error closing database connection: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _db.clear();
    } catch (e) {
      print('Error clearing database: $e');
      rethrow;
    }
  }
}
