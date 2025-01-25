import 'package:fhir_r4/fhir_r4.dart';
import 'package:flutter/material.dart';
import 'package:json_view/json_view.dart';

/// ResourceList
class ResourceList extends StatelessWidget {
  /// Constructor
  const ResourceList(this.resources, {super.key});

  /// Resources
  final List<Resource> resources;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: resources.length,
      itemBuilder: (context, index) {
        final resource = resources[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExpansionTile(
            title: Text('ID: ${resource.id?.value ?? "Unknown"}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 300, // Set a maximum height for the JSON view
                  ),
                  child: JsonView(
                    json: resource.toJson(), // Directly display the JSON
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
