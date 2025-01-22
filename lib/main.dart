import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_json/flutter_json.dart';

void main() {
  runApp(const MyApp());
}

/// The main application widget.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FHIR Resource Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const FhirLoaderScreen(),
    );
  }
}

/// A screen for managing FHIR resources.
class FhirLoaderScreen extends StatefulWidget {
  const FhirLoaderScreen({super.key});

  @override
  State<FhirLoaderScreen> createState() => _FhirLoaderScreenState();
}

class _FhirLoaderScreenState extends State<FhirLoaderScreen> {
  final DbService sqlite3Service = DbService(); // SQLite3 service
  String resultMessage = 'Press a button to load resources.';
  List<Resource> displayedResources = [];
  String? selectedResourceType;

  final List<String> resourceTypes = [
    'Patient',
    'Observation',
    'Condition',
    // Add more FHIR resource types as needed
  ];

  @override
  void dispose() {
    sqlite3Service.close();
    super.dispose();
  }

  Future<void> _loadMimicData() async {
    await _loadFhirResources('mimic-fhir');
  }

  Future<void> _loadExampleData() async {
    await _loadFhirResources('fhir-assets');
  }

  Future<void> _loadFhirResources(String directoryPrefix) async {
    setState(() {
      resultMessage = 'Loading resources...';
    });

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

      final stopwatch = Stopwatch()..start();

      for (final file in files) {
        final fileContent = await rootBundle.loadString(file);

        if (file.endsWith('.ndjson')) {
          // NDJSON: Parse line by line
          final lines =
              fileContent.split('\n').where((line) => line.isNotEmpty);
          for (final line in lines) {
            print(line.substring(0, 100));
          }
          final resources = lines.map(Resource.fromJsonString).toList();
          sqlite3Service.bulkSaveResourcesOfSameType(resources);
        } else if (file.endsWith('.json')) {
          // JSON: Parse entire file
          final resource = Resource.fromJsonString(fileContent);
          print('Loaded resource: ${resource.path}');

          if (resource is Bundle) {
            final resources = <Resource>[];

            for (final entry in resource.entry ?? <BundleEntry>[]) {
              if (entry.resource != null) {
                resources.add(entry.resource!); // Ensure non-null resources
              }
            }

            sqlite3Service.bulkSaveMixedResources(resources);
          } else {
            sqlite3Service.saveResource(resource);
          }
        }
      }

      stopwatch.stop();
      setState(() {
        resultMessage =
            'Loaded resources in ${stopwatch.elapsed.inMilliseconds} ms.';
      });
    } catch (e) {
      setState(() {
        resultMessage = 'Error loading resources: $e';
      });
    }
  }

  void _showResources() {
    if (selectedResourceType == null) return;

    final resources = sqlite3Service.getAllResources(selectedResourceType!);
    setState(() {
      displayedResources = resources;
    });
  }

  Widget _buildResourceList() {
    if (displayedResources.isEmpty) {
      return const Text('No resources available.');
    }

    return Expanded(
      child: ListView.builder(
        itemCount: displayedResources.length,
        itemBuilder: (context, index) {
          final resource = displayedResources[index];
          return ExpansionTile(
            title: Text('ID: ${resource.id?.value ?? "Unknown"}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: JsonWidget(
                  json: json.decode(resource.toJsonString()),
                  initialExpandDepth: 2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FHIR Resource Manager')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              resultMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: _loadMimicData,
                  child: const Text('Load Mimic Data'),
                ),
                ElevatedButton(
                  onPressed: _loadExampleData,
                  child: const Text('Load Example Data'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButton<String>(
              value: selectedResourceType,
              hint: const Text('Select Resource Type'),
              items: resourceTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: (type) {
                setState(() {
                  selectedResourceType = type;
                  _showResources();
                });
              },
            ),
            const SizedBox(height: 10),
            _buildResourceList(),
          ],
        ),
      ),
    );
  }
}
