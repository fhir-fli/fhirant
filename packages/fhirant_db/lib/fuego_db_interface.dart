import 'package:fhir_r4/fhir_r4.dart';

abstract class FuegoDbInterface {
  // Core CRUD
  Future<Resource?> getResource(R4ResourceType resourceType, String id);
  Future<bool> saveResource(Resource resource);
  Future<bool> saveResources(List<Resource> resources);
  Future<bool> deleteResource(R4ResourceType resourceType, String id);

  // Resource Querying
  Future<List<Resource>> getResourcesWithPagination({
    required R4ResourceType resourceType,
    required int count,
    required int offset,
  });
  Future<List<Resource>> getResourcesByType(R4ResourceType resourceType);
  Future<int> getResourceCount(R4ResourceType resourceType);
  Future<List<R4ResourceType>> getResourceTypes();

  // History Management
  Future<List<Resource>> getResourceHistory(
      R4ResourceType resourceType, String id);

  // Database Management
  Future<void> initialize();
  Future<void> close();
  Future<void> clear();
}
