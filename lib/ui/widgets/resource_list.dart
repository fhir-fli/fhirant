import 'package:fhir_r4/fhir_r4.dart';
import 'package:flutter/material.dart';
import 'package:json_view/json_view.dart';

/// ResourceList
class ResourceList extends StatelessWidget {
  /// Constructor
  const ResourceList(this.resources, {super.key});

  /// List of FHIR Resources
  final List<Resource> resources;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return const Center(
        child: Text(
          'No resources available',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      itemCount: resources.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final resource = resources[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            title: Row(
              children: [
                const Icon(Icons.folder, color: Colors.indigo),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'ID: ${resource.id?.value ?? "Unknown"}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            children: [
              Divider(color: Colors.grey[300], thickness: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 300,
                  ),
                  child: _buildJsonView(resource, context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build a JsonView widget with error handling
  Widget _buildJsonView(Resource resource, BuildContext context) {
    try {
      final json = resource.toJson();
      return JsonView(
        json: json,
      );
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Error displaying resource data: $e',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
  }
}
