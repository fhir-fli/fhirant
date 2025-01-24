import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json_view/json_view.dart';

/// PrimaryScreen
class PrimaryScreen extends StatefulWidget {
  /// PrimaryScreen
  const PrimaryScreen({super.key});

  @override
  State<PrimaryScreen> createState() => _PrimaryScreenState();
}

class _PrimaryScreenState extends State<PrimaryScreen> {
  final DbService sqlite3Service = DbService();
  String resultMessage = 'Press a button to load resources.';
  List<Resource> displayedResources = [];
  String? selectedResourceType;

  final List<String> resourceTypes = [
    'Patient',
    'Observation',
    'Condition',
    // Add other resource types here
  ];

  @override
  void dispose() {
    sqlite3Service.close();
    super.dispose();
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

      var totalResources = 0;
      final stopwatch = Stopwatch()..start();

      for (final file in files) {
        final fileContent = await rootBundle.loadString(file);

        if (file.endsWith('.ndjson')) {
          final lines =
              fileContent.split('\n').where((line) => line.isNotEmpty);
          final resources = lines.map(Resource.fromJsonString).toList();
          sqlite3Service.bulkSaveResourcesOfSameType(resources);
          totalResources += resources.length;
        } else if (file.endsWith('.json')) {
          final resource = Resource.fromJsonString(fileContent);

          if (resource is Bundle) {
            final resources = <Resource>[];
            for (final entry in resource.entry ?? <BundleEntry>[]) {
              if (entry.resource != null) {
                resources.add(entry.resource!);
              }
            }
            sqlite3Service.bulkSaveMixedResources(resources);
            totalResources += resources.length;
          } else {
            sqlite3Service.saveResource(resource);
            totalResources++;
          }
        }
      }

      stopwatch.stop();
      setState(() {
        resultMessage = 'Loaded $totalResources resources in '
            '${stopwatch.elapsed.inMilliseconds} ms.';
      });
    } catch (e) {
      setState(() {
        resultMessage = 'Error loading resources: $e';
      });
    }
  }

  Future<Map<String, int>> _getResourceCounts() async {
    final counts = <String, int>{};
    for (final resourceType in resourceTypes) {
      final count = sqlite3Service.getResourceCount(resourceType);
      counts[resourceType] = count;
    }
    return counts;
  }

  Widget _buildDatabaseOverview() {
    return FutureBuilder<Map<String, int>>(
      future: _getResourceCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        final counts = snapshot.data ?? {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: counts.entries.map((entry) {
            return Text('${entry.key}: ${entry.value}');
          }).toList(),
        );
      },
    );
  }

  void _showResources() {
    if (selectedResourceType == null) return;

    final resources = sqlite3Service.getAllResources(selectedResourceType!);
    setState(() {
      displayedResources = resources;
    });
  }

  Future<void> _exportData(String resourceType) async {
    final resources = sqlite3Service.getAllResources(resourceType);
    final output = resources.map((r) => r.toJsonString()).join('\n');

    final directory = Directory.current.path; // Adjust as needed
    final file = File('$directory/$resourceType.ndjson');
    await file.writeAsString(output);

    setState(() {
      resultMessage = 'Exported $resourceType to ${file.path}';
    });
  }

  Widget _buildResourceList() {
    if (displayedResources.isEmpty) {
      return const Text('No resources available.');
    }

    return SizedBox(
      height: 400,
      child: ListView.builder(
        itemCount: displayedResources.length,
        itemBuilder: (context, index) {
          final resource = displayedResources[index];
          return ExpansionTile(
            title: Text('ID: ${resource.id?.value ?? "Unknown"}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: JsonView(
                  json: resource.toJson(),
                  styleScheme: JsonStyleScheme(
                    keysStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    valuesStyle: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.green,
                    ),
                    quotation: JsonQuotation.doubleQuote,
                    depth: 1,
                  ),
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
      appBar: AppBar(title: const Text('FHIR ANT')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: 
        Column(
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
                  onPressed: () => _loadFhirResources('mimic-fhir'),
                  child: const Text('Load Mimic Data'),
                ),
                ElevatedButton(
                  onPressed: () => _loadFhirResources('fhir-assets'),
                  child: const Text('Load Example Data'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Database Overview:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildDatabaseOverview(),
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: selectedResourceType != null
                  ? () => _exportData(selectedResourceType!)
                  : null,
              child: const Text('Export Selected Resource'),
            ),
          ],
        ),
      ),
    );
  }
}
