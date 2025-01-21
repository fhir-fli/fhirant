import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FHIR NDJSON Loader',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const FhirLoaderScreen(),
    );
  }
}

class FhirLoaderScreen extends StatefulWidget {
  const FhirLoaderScreen({super.key});

  @override
  State<FhirLoaderScreen> createState() => _FhirLoaderScreenState();
}

class _FhirLoaderScreenState extends State<FhirLoaderScreen> {
  final DbService sqlite3Service = DbService(); // SQLite3 service
  String resultMessage = 'Press the button to start loading FHIR resources.';

  @override
  void dispose() {
    sqlite3Service.close();
    super.dispose();
  }

  Future<void> _loadFhirResources() async {
    setState(() {
      resultMessage = 'Loading resources...';
    });

    try {
      // Read the asset manifest and filter for NDJSON files
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      final ndjsonFiles = manifestMap.keys
          .where(
            (key) => key.startsWith('mimic-fhir') && key.endsWith('.ndjson'),
          )
          .toList();

      // Benchmark SQLite3
      final sqlite3Stopwatch = Stopwatch()..start();
      for (final file in ndjsonFiles) {
        final fileContent = await rootBundle.loadString(file);
        final lines = fileContent.split('\n').where((line) => line.isNotEmpty);

        final resources = <Resource>[];
        for (final line in lines) {
          final resource = Resource.fromJsonString(line);
          resources.add(resource);
          print(resource.path);
        }
        sqlite3Service.bulkSaveResourcesOfSameType(resources);
        resources.clear();
      }
      sqlite3Stopwatch.stop();

      setState(() {
        resultMessage =
            'SQLite3 loaded resources in ${sqlite3Stopwatch.elapsed.inMilliseconds} ms.\n';
      });
    } catch (e) {
      setState(() {
        resultMessage = 'An error occurred while loading resources: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FHIR NDJSON Loader')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              resultMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadFhirResources,
              child: const Text('Load FHIR Resources'),
            ),
          ],
        ),
      ),
    );
  }
}
