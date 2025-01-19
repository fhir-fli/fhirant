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
  final DbService dbService = DbService();
  String resultMessage = 'Press the button to start loading FHIR resources.';

  @override
  void dispose() {
    dbService.close();
    super.dispose();
  }

  Future<void> _loadFhirResources() async {
    setState(() {
      resultMessage = 'Loading resources...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      // Get a list of NDJSON files in the assets folder
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      final ndjsonFiles = manifestMap.keys
          .where(
            (key) => key.startsWith('mimic-fhir') && key.endsWith('.ndjson'),
          )
          .toList();

      var totalResources = 0;

      for (final file in ndjsonFiles) {
        final fileContent = await rootBundle.loadString(file);
        final lines = fileContent.split('\n').where((line) => line.isNotEmpty);

        final resources = <Resource>[];
        for (final line in lines) {
          if (line.isEmpty) {
            continue;
          }
          final resource = Resource.fromJsonString(line);
          resources.add(resource);
          // ignore: avoid_print
          print(resource.path);
        }
        final result = DbService().bulkSaveResourcesOfSameType(resources);
        if(result){
          totalResources += resources.length;
        }
        resources.clear();
      }

      stopwatch.stop();

      setState(() {
        resultMessage = 'Successfully loaded $totalResources resources in '
            '${stopwatch.elapsed.inMilliseconds} ms.';
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
