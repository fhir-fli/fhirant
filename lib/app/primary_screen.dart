import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PrimaryScreen
class PrimaryScreen extends StatefulWidget {
  /// PrimaryScreen
  const PrimaryScreen({super.key});

  @override
  State<PrimaryScreen> createState() => _PrimaryScreenState();
}

class _PrimaryScreenState extends State<PrimaryScreen> {
  final DbService dbService = DbService();
  List<Resource> displayedResources = [];
  List<String> validResourceTypes = [];
  String? selectedResourceType;

  @override
  void initState() {
    super.initState();
    _loadValidResourceTypes(); // Load valid resource types at initialization
  }

  @override
  void dispose() {
    dbService.close();
    super.dispose();
  }

  Future<void> _loadValidResourceTypes() async {
    final validTypes = <String>[];

    for (final resourceType in R4ResourceType.typesAsStrings) {
      final count = dbService.getResourceCount(
        ['Endpoint', 'Group', 'List'].contains(resourceType)
            ? 'Fhir$resourceType'
            : resourceType,
      );
      if (count > 0) {
        validTypes.add(resourceType);
      }
    }

    setState(() {
      validResourceTypes = validTypes;
      if (selectedResourceType != null &&
          !validResourceTypes.contains(selectedResourceType)) {
        selectedResourceType = null; // Reset if current type is no longer valid
      }
    });
  }

  Future<void> _loadFhirResources(String directoryPrefix) async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      final files = manifestMap.keys
          .where(
            (key) =>
                key.startsWith(directoryPrefix) &&
                (key.endsWith('.json') || key.endsWith('.ndjson')),
          )
          .toList();

      for (final file in files) {
        final fileContent = await rootBundle.loadString(file);

        if (file.endsWith('.ndjson')) {
          final lines =
              fileContent.split('\n').where((line) => line.isNotEmpty);
          final resources = lines.map(Resource.fromJsonString).toList();
          dbService.bulkSaveResourcesOfSameType(resources);
        } else if (file.endsWith('.json')) {
          final resource = Resource.fromJsonString(fileContent);
          if (resource is Bundle) {
            final resources = resource.entry
                    ?.map((entry) => entry.resource)
                    .whereType<Resource>()
                    .toList() ??
                [];
            dbService.bulkSaveMixedResources(resources);
          } else {
            dbService.saveResource(resource);
          }
        }
      }

      // Reload valid resource types after loading data
      await _loadValidResourceTypes();
    } catch (e) {
      if (!mounted) return; // Ensure the widget is still part of the tree
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading resources: $e')),
      );
    }
  }

  Future<void> _startServer() async {
    try {
      await ServerManager().start();
      // Check if the widget is still mounted before accessing context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server started on port 8080')),
      );
    } catch (e) {
      // Check again for mounted before accessing context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start server: $e')),
      );
    }
  }

  Future<void> _stopServer() async {
    try {
      await ServerManager().stop();
      // Check if the widget is still mounted before accessing context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server stopped')),
      );
    } catch (e) {
      // Check again for mounted before accessing context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to stop server: $e')),
      );
    }
  }

  void _showResources() {
    if (selectedResourceType == null) return;

    final resources = dbService.getAllResources(selectedResourceType!);
    setState(() {
      displayedResources = resources;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: Image.asset(
            'assets/fhirant_logo.png',
            height: 78, // Adjust size as needed
          ),
        ),
        backgroundColor: Colors.indigo,
      ),
      drawer: FhirantDrawer(
        onLoadMimicData: () => _loadFhirResources('mimic-fhir'),
        onLoadExampleData: () => _loadFhirResources('fhir-assets'),
        onStartServer: _startServer,
        onStopServer: _stopServer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    DatabaseOverview(dbService),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedResourceType,
              hint: const Text('Select Resource Type'),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: validResourceTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type, style: const TextStyle(fontSize: 16)),
                );
              }).toList(),
              onChanged: (type) {
                setState(() {
                  selectedResourceType = type;
                  _showResources();
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ResourceList(displayedResources),
            ),
          ],
        ),
      ),
    );
  }
}
