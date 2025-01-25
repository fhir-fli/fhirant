import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';

/// DatabaseOverview
class DatabaseOverview extends StatelessWidget {
  /// Constructor
  const DatabaseOverview(this.dbService, {super.key});

  /// Database Service
  final DbService dbService;

  Future<Map<String, int>> _getResourceCounts() async {
    final counts = <String, int>{};

    for (final resourceType in R4ResourceType.typesAsStrings) {
      final count = dbService.getResourceCount(
        ['Endpoint', 'Group', 'List'].contains(resourceType)
            ? 'Fhir$resourceType'
            : resourceType,
      );
      counts[resourceType] = count;
    }

    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _getResourceCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text(
            'Error: ${snapshot.error}',
            style: const TextStyle(color: Colors.red),
          );
        }

        final counts = (snapshot.data ?? {})
          ..removeWhere((key, value) => value == 0);

        if (counts.isEmpty) {
          return const Text(
            'No resources found in database',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          );
        }

        return ExpansionTile(
          title: const Text(
            'Database Overview',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                thickness: 4,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: counts.entries
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${entry.value} resource(s)',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
